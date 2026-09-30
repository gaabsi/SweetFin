//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import Logging

/// Invitation reçue (EnhancedFin `POST syncplay/invite`).
struct SyncPlayInvite: Identifiable {
    let groupID: String
    let from: String
    var id: String { groupID }
}

/// SweetFin : SyncPlay, côté SweetFin.
///
/// Retient l'état du groupe (lu dans les `GroupUpdate`), exécute les commandes du groupe à
/// l'heure dite (horloge calée sur le serveur), corrige la dérive pendant la lecture et
/// prévient le serveur des actions locales. Seule l'ouverture du média du groupe passe par
/// `UserSessionManager+SocketCommands` (elle a besoin de `playItem`).
@MainActor
final class SyncPlayManager: ObservableObject {

    /// Démarrage du média du groupe, comme jellyfin-web : lecture → pause locale → `Ready`.
    private enum StartPhase: Equatable {
        case idle
        case awaitingPlayback
        /// `positionTicks` : position à annoncer dans `Ready` ; `nil` = celle du lecteur.
        case awaitingPause(positionTicks: Int?)
    }

    // Seuils de jellyfin-web (`PlaybackCore`), en secondes.
    private static let driftCheckInterval: TimeInterval = 1.5
    private static let minDelaySpeedToSync: TimeInterval = 0.06
    private static let maxDelaySpeedToSync: TimeInterval = 3
    private static let speedToSyncDuration: TimeInterval = 1
    private static let minDelaySkipToSync: TimeInterval = 0.4
    /// En dessous, on ne met pas en pause pour attendre `when` : VLC n'aurait pas le temps
    /// de confirmer la pause avant le play (cf. la course du démarrage).
    private static let minScheduledPause: TimeInterval = 0.3

    @Published
    private(set) var group: GroupInfoDto?
    @Published
    private(set) var invite: SyncPlayInvite?
    /// Média du groupe : SyncPlay ne s'occupe que de lui.
    private var itemID: String?
    private var playlistItemID: String?
    /// Dernier état demandé par le groupe. Un changement du lecteur conforme = écho.
    private var groupStatus: MediaPlayerManager.PlaybackRequestStatus?
    /// Position du dernier seek demandé par le groupe (pause et seek se recalent) : son écho est ignoré.
    private var expectedSeekTicks: Int?
    private var startPhase: StartPhase = .idle
    /// VLC a joué le média chargé. Le serveur répond à `SetNewQueue` avant que VLC ait
    /// seulement ouvert le fichier : « chargé » ne veut pas dire « prêt à obéir ».
    private var hasPlaybackStarted = false

    /// Écart d'horloge serveur − local, en secondes.
    private var clockOffset: TimeInterval = 0
    private var clockMeasurements: [(offset: TimeInterval, delay: TimeInterval)] = []
    private var timeSyncTask: Task<Void, Never>?
    /// Dernier `unpause` : référence de la position du groupe pour la correction de dérive.
    private var lastUnpause: (positionTicks: Int, when: Date)?
    /// Play programmé à l'heure `when`, annulé par la commande suivante.
    private var scheduledUnpause: Task<Void, Never>?
    /// Retour à la vitesse normale après un speed-to-sync.
    private var rateReset: Task<Void, Never>?
    /// Correction de dérive suspendue (démarrage, correction en cours) jusqu'à cette date.
    private var driftCheckResumesAt: Date = .distantFuture

    private weak var userSession: UserSession?
    private var cancellables: Set<AnyCancellable> = []
    private var playerCancellable: AnyCancellable?
    private var statusCancellable: AnyCancellable?
    private var seekCancellable: AnyCancellable?
    private var itemCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?
    private weak var player: MediaPlayerManager?
    private let logger = Logger.swiftfin()

    private func observe(socket: ServerSocketManager) {
        socket.syncPlayGroupUpdates
            .sink { [weak self] update in
                Task { @MainActor in self?.onReceive(groupUpdate: update) }
            }
            .store(in: &cancellables)

        // Synchrone : l'attente (`groupStatus`) est notée avant que le lecteur ne bouge,
        // sinon on renverrait l'écho au serveur.
        socket.syncPlayCommands
            .sink { [weak self] command in
                MainActor.assumeIsolated { self?.onReceive(command: command) }
            }
            .store(in: &cancellables)

        // Un DisplayMessage qui porte nos arguments = une invitation.
        socket.generalCommands
            .compactMap { command -> SyncPlayInvite? in
                guard command.name == .displayMessage,
                      let groupID = command.arguments?["SyncPlayGroupId"],
                      let from = command.arguments?["SyncPlayFrom"]
                else { return nil }
                return SyncPlayInvite(groupID: groupID, from: from)
            }
            .sink { [weak self] invite in
                MainActor.assumeIsolated { self?.invite = invite }
            }
            .store(in: &cancellables)

        Container.shared.mediaPlayerManagerPublisher()
            .sink { [weak self] manager in
                Task { @MainActor in self?.observe(player: manager) }
            }
            .store(in: &cancellables)
    }

    private func onReceive(groupUpdate: GroupUpdate) {
        switch groupUpdate {
        case let .syncPlayGroupJoinedUpdate(update):
            group = update.data
            startTimeSync()
        case let .syncPlayUserJoinedUpdate(update):
            guard let name = update.data else { return }
            group?.participants = (group?.participants ?? []) + [name]
        case let .syncPlayUserLeftUpdate(update):
            group?.participants?.removeAll { $0 == update.data }
        case .syncPlayGroupLeftUpdate, .syncPlayNotInGroupUpdate, .syncPlayGroupDoesNotExistUpdate:
            reset()
        case let .syncPlayPlayQueueUpdate(update):
            guard let queue = update.data else { return }
            itemID = queue.playingItem?.itemID
            playlistItemID = queue.playingItem?.playlistItemID
            guard queue.changesPlayingItem else { return }

            if let player, player.item.id == itemID, hasPlaybackStarted {
                readyWithLoadedItem(player, startPositionTicks: queue.startPositionTicks ?? 0)
            } else {
                startPhase = .awaitingPlayback
            }
        default: ()
        }
    }

    private func onReceive(command: SendCommand) {
        scheduledUnpause?.cancel()
        let ticks = command.positionTicks

        switch command.command {
        case .unpause:
            if let ticks, let when = command.when {
                lastUnpause = (ticks, when)
                scheduleUnpause(positionTicks: ticks, when: when)
            } else {
                groupStatus = .playing
                player?.setPlaybackRequestStatus(status: .playing)
            }
        case .pause, .seek:
            // Une pause recale tout le monde au même endroit. Pendant un seek, le groupe
            // attend : chacun reste en pause jusqu'à l'`unpause`.
            groupStatus = .paused
            lastUnpause = nil
            stopDriftCorrection()
            player?.setPlaybackRequestStatus(status: .paused)

            if let ticks {
                seek(to: ticks)
                if command.command == .seek {
                    sendReady(positionTicks: ticks)
                }
            }
        case .stop:
            groupStatus = nil
            lastUnpause = nil
            stopDriftCorrection()
            player?.stop()
        case .none: ()
        }
    }

    /// Comme jellyfin-web : play à l'heure `when` du serveur. Déjà passée (commande reçue en
    /// retard) : on repart tout de suite, là où le groupe doit en être.
    private func scheduleUnpause(positionTicks: Int, when: Date) {
        guard let player else { return }
        let delay = localDate(fromServer: when).timeIntervalSinceNow

        guard delay > 0 else {
            groupStatus = .playing
            seek(to: groupPositionTicks(from: positionTicks, since: when))
            player.setPlaybackRequestStatus(status: .playing)
            resumeDriftCorrection()
            return
        }

        // En attendant `when`, le groupe est encore en pause pour nous. Si l'utilisateur a
        // déjà relancé (action locale), on l'arrête pour partir avec les autres.
        groupStatus = .paused
        if delay > Self.minScheduledPause {
            player.setPlaybackRequestStatus(status: .paused)
        }
        if abs(player.seconds.ticks - positionTicks) > Duration.seconds(Self.minDelaySkipToSync).ticks {
            seek(to: positionTicks)
        }

        scheduledUnpause = Task { [weak self, weak player] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let player else { return }
            groupStatus = .playing
            await player.setPlaybackRequestStatus(status: .playing)
            resumeDriftCorrection()
        }
    }

    private func seek(to ticks: Int) {
        expectedSeekTicks = ticks
        player?.proxy?.setSeconds(.ticks(ticks))
    }

    /// VLC signale ses changements d'état par `setPlaybackRequestStatus`.
    private func observe(player manager: MediaPlayerManager?) {
        player = manager

        itemCancellable = manager?.$playbackItem
            .compactMap { $0 }
            .sink { [weak self] item in
                Task { @MainActor in self?.player(didLoad: item) }
            }

        playerCancellable = manager?.actions
            .sink { [weak self, weak manager] action in
                guard case let .setPlaybackRequestStatus(status) = action, let manager else { return }
                Task { @MainActor in self?.player(manager, didReport: status) }
            }

        // `@Published` renvoie sa valeur actuelle à l'abonnement : ce n'est pas un changement.
        statusCancellable = manager?.$playbackRequestStatus
            .dropFirst()
            .sink { [weak self, weak manager] status in
                guard let manager else { return }
                Task { @MainActor in self?.player(manager, didChangeTo: status) }
            }

        // Chaque nouvelle position de VLC (~50 Hz) : l'heure est prise tout de suite, pas après
        // un saut de fil, pour ne pas fausser l'écart mesuré.
        secondsCancellable = manager?.secondsBox.$value
            .sink { [weak self] position in
                let now = Date()
                MainActor.assumeIsolated { self?.checkDrift(position: position, at: now) }
            }

        seekCancellable = manager?.seeks
            .sink { [weak self, weak manager] seconds in
                guard let manager else { return }
                Task { @MainActor in self?.player(manager, didSeekTo: seconds) }
            }
    }

    // Le serveur relance tout le monde (`unpause`) quand chacun a dit `Ready`.
    private func player(_ manager: MediaPlayerManager, didReport status: MediaPlayerManager.PlaybackRequestStatus) {
        if status == .playing {
            hasPlaybackStarted = true
        }

        guard groupID != nil else { return }

        switch (startPhase, status) {
        case (.awaitingPlayback, .playing):
            // VLC met en pause de façon asynchrone : on attend qu'il le confirme avant `Ready`,
            // sinon l'`unpause` rapide du groupe se fait écraser par cette pause.
            startPhase = .awaitingPause(positionTicks: nil)
            groupStatus = .paused
            manager.proxy?.pause()
        case let (.awaitingPause(positionTicks), .paused):
            startPhase = .idle
            sendReady(positionTicks: positionTicks ?? manager.seconds.ticks)
        default: ()
        }
    }

    // Un média lancé ici, hors demande du groupe : on le propose au groupe. Le serveur
    // renvoie un `PlayQueue` à tous, qui l'ouvrent ; chez nous il est déjà chargé.
    private func player(didLoad item: MediaPlayerItem) {
        hasPlaybackStarted = false

        guard groupID != nil, startPhase == .idle, let id = item.baseItem.id, id != itemID else { return }

        let request = PlayRequestDto(
            playingItemPosition: 0,
            playingQueue: [id],
            startPositionTicks: item.baseItem.startSeconds?.ticks ?? 0
        )
        send(Paths.syncPlaySetNewQueue(request))
    }

    /// Le média du groupe est déjà dans le lecteur (c'est nous qui l'avons proposé) : pas de
    /// rechargement, on se cale sur la position du groupe puis pause et `Ready`.
    private func readyWithLoadedItem(_ manager: MediaPlayerManager, startPositionTicks: Int) {
        groupStatus = .paused
        expectedSeekTicks = startPositionTicks
        manager.proxy?.setSeconds(.ticks(startPositionTicks))

        if manager.playbackRequestStatus == .paused {
            sendReady(positionTicks: startPositionTicks)
        } else {
            // Même attente que le démarrage : VLC confirme la pause avant `Ready`.
            startPhase = .awaitingPause(positionTicks: startPositionTicks)
            manager.proxy?.pause()
        }
    }

    var groupID: String? {
        group?.groupID
    }

    func join(groupID: String) {
        invite = nil
        send(Paths.syncPlayJoinGroup(.init(groupID: groupID)))
    }

    func declineInvite() {
        invite = nil
    }

    func leave() {
        send(Paths.syncPlayLeaveGroup)
    }

    /// Le serveur y fait entrer le créateur : l'état arrive ensuite par `GroupJoined`.
    func createGroup() async throws {
        guard let userSession else { return }
        let name = SyncPlayStrings.groupName(of: userSession.user.username)
        _ = try await userSession.client.send(Paths.syncPlayCreateGroup(.init(groupName: name)))
    }

    func groups() async throws -> [GroupInfoDto] {
        guard let userSession else { return [] }
        return try await userSession.client.send(Paths.syncPlayGetGroups).value
    }

    /// Les comptes actifs du serveur (`GET /Users` n'exige pas d'être admin).
    func users() async throws -> [UserDto] {
        guard let userSession else { return [] }
        return try await userSession.client.send(Paths.getUsers(isDisabled: false)).value
    }

    /// Output :
    /// - delivered (Int) : nombre d'appareils de la cible qui l'ont reçue, 0 = pas connecté
    func invite(userID: String) async throws -> Int {
        guard let userSession, let groupID else { return 0 }
        return try await userSession.enhancedFinClient.inviteToSyncPlay(groupID: groupID, userID: userID)
    }

    // B1 : l'action locale s'applique tout de suite, le serveur aligne les autres.
    private func player(_ manager: MediaPlayerManager, didChangeTo status: MediaPlayerManager.PlaybackRequestStatus) {
        guard startPhase == .idle,
              let groupStatus, status != groupStatus,
              manager.item.id == itemID
        else { return }

        send(status == .paused ? Paths.syncPlayPause : Paths.syncPlayUnpause)
    }

    private func player(_ manager: MediaPlayerManager, didSeekTo seconds: Duration) {
        let ticks = seconds.ticks

        // VLC peut arrondir la cible : on ne compare pas au tick près.
        if let expectedSeekTicks, abs(ticks - expectedSeekTicks) < Duration.seconds(1).ticks {
            self.expectedSeekTicks = nil
            return
        }

        guard startPhase == .idle, groupStatus != nil, manager.item.id == itemID else { return }
        send(Paths.syncPlaySeek(.init(positionTicks: ticks)))
    }

    private func sendReady(positionTicks: Int) {
        let state = PlaybackQueueStateInfo(
            isPlaying: false,
            playlistItemID: playlistItemID,
            positionTicks: positionTicks,
            when: Date().addingTimeInterval(clockOffset)
        )
        send(Paths.syncPlayReady(state))
    }

    /// Hors groupe : on oublie tout ce qui concerne le groupe.
    private func reset() {
        scheduledUnpause?.cancel()
        stopDriftCorrection()
        timeSyncTask?.cancel()
        timeSyncTask = nil
        clockMeasurements = []
        group = nil
        itemID = nil
        playlistItemID = nil
        groupStatus = nil
        expectedSeekTicks = nil
        lastUnpause = nil
        startPhase = .idle
    }

    // MARK: - Horloge (TimeSync de jellyfin-web)

    /// 3 mesures à 1 s d'intervalle, puis une par minute, tant qu'on est dans un groupe.
    private func startTimeSync() {
        guard timeSyncTask == nil else { return }

        timeSyncTask = Task { [weak self] in
            var count = 0
            while !Task.isCancelled {
                await self?.measureClockOffset()
                count += 1
                try? await Task.sleep(for: .seconds(count < 3 ? 1 : 60))
            }
        }
    }

    /// Principe de NTP : l'aller-retour réseau s'annule dans la moyenne des deux écarts.
    /// On garde les 8 dernières mesures et on retient celle au plus court aller-retour,
    /// la moins perturbée par le réseau.
    private func measureClockOffset() async {
        guard let userSession else { return }

        let sent = Date()
        guard let response = try? await userSession.client.send(Paths.getUtcTime).value,
              let received = response.requestReceptionTime,
              let transmitted = response.responseTransmissionTime
        else { return }
        let back = Date()

        let offset = (received.timeIntervalSince(sent) + transmitted.timeIntervalSince(back)) / 2
        let delay = back.timeIntervalSince(sent) - transmitted.timeIntervalSince(received)

        clockMeasurements = Array((clockMeasurements + [(offset, delay)]).suffix(8))
        clockOffset = clockMeasurements.min { $0.delay < $1.delay }?.offset ?? 0
        logger.debug("SyncPlay : horloge", metadata: ["offsetMs": .stringConvertible(Int(clockOffset * 1000)), "rttMs": .stringConvertible(Int(delay * 1000))])
    }

    private func localDate(fromServer date: Date) -> Date {
        date.addingTimeInterval(-clockOffset)
    }

    /// Position du groupe à l'instant `date` : celle de la commande + le temps écoulé depuis.
    private func groupPositionTicks(from positionTicks: Int, since when: Date, at date: Date = Date()) -> Int {
        let elapsed = date.addingTimeInterval(clockOffset).timeIntervalSince(when)
        return positionTicks + Duration.seconds(elapsed).ticks
    }

    // MARK: - Correction de dérive (speed-to-sync de jellyfin-web)

    /// Comme jellyfin-web : pas de correction pendant 1,5 s après un départ, le temps que
    /// le lecteur se stabilise.
    private func resumeDriftCorrection() {
        driftCheckResumesAt = Date().addingTimeInterval(Self.driftCheckInterval)
    }

    private func stopDriftCorrection() {
        driftCheckResumesAt = .distantFuture
        guard rateReset != nil else { return }
        rateReset?.cancel()
        rateReset = nil
        if let player {
            player.proxy?.setRate(player.rate)
        }
    }

    /// Toutes les 1,5 s : écart de 60 ms à 3 s → vitesse `1 + écart / 1 s` pendant 1 s ;
    /// au-delà de 3 s → seek vers la position du groupe.
    private func checkDrift(position: Duration, at date: Date) {
        guard date >= driftCheckResumesAt,
              let player, let lastUnpause,
              groupStatus == .playing, startPhase == .idle,
              player.playbackRequestStatus == .playing,
              player.item.id == itemID
        else { return }

        let groupTicks = groupPositionTicks(from: lastUnpause.positionTicks, since: lastUnpause.when, at: date)
        let diff = Double(groupTicks - position.ticks) / Double(Duration.seconds(1).ticks)
        let absDiff = abs(diff)
        driftCheckResumesAt = date.addingTimeInterval(Self.driftCheckInterval)

        if absDiff >= Self.minDelaySpeedToSync, absDiff < Self.maxDelaySpeedToSync {
            // En forte avance, jellyfin-web allonge la correction plutôt que de descendre
            // sous ×0,2.
            let duration = max(Self.speedToSyncDuration, -diff / 0.8)
            logger.debug("SyncPlay : speed-to-sync", metadata: ["diffMs": .stringConvertible(Int(diff * 1000)), "rate": .stringConvertible(1 + diff / duration)])
            player.proxy?.setRate(Float(1 + diff / duration))
            driftCheckResumesAt = date.addingTimeInterval(max(duration, Self.driftCheckInterval))

            rateReset?.cancel()
            rateReset = Task { [weak self, weak player] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled, let player else { return }
                player.proxy?.setRate(player.rate)
                self?.rateReset = nil
            }
        } else if absDiff >= Self.maxDelaySpeedToSync {
            logger.debug("SyncPlay : skip-to-sync", metadata: ["diffMs": .stringConvertible(Int(diff * 1000))])
            seek(to: groupTicks)
        }
    }

    private func send(_ request: Request<Void>) {
        guard let userSession else { return }

        Task {
            do {
                try await userSession.client.send(request)
            } catch {
                logger.error(
                    "SyncPlay : requête refusée",
                    metadata: ["request": .string(request.id ?? ""), "error": .string(error.localizedDescription)]
                )
            }
        }
    }
}

extension SyncPlayManager: UserSessionService {

    func didStart(userSession: UserSession) {
        self.userSession = userSession
        observe(socket: userSession.serverSocketManager)
    }

    func willStop(userSession: UserSession) {
        cancellables = []
        playerCancellable = nil
        statusCancellable = nil
        seekCancellable = nil
        itemCancellable = nil
        secondsCancellable = nil
        player = nil
        invite = nil
        reset()
    }
}

// Lecture d'une file SyncPlay, partagée avec `UserSessionManager+SocketCommands`.
extension PlayQueueUpdate {

    var playingItem: SyncPlayQueueItem? {
        playlist?[safe: playingItemIndex ?? 0]
    }

    /// Le groupe regarde autre chose. Ajouter ou réordonner la file ne change pas le média.
    var changesPlayingItem: Bool {
        [.newPlaylist, .setCurrentItem, .nextItem, .previousItem].contains(reason)
    }
}
