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
    /// Propre à chaque invitation : une seconde invitation au même groupe relance le bandeau.
    let id = UUID()
    let groupID: String
    let from: String
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
    /// 60 ms chez jellyfin-web : un écho s'entend dès ~20 ms quand deux appareils sont dans
    /// la même pièce. Plancher = bruit de mesure (horloges + position VLC, ~10-15 ms).
    private static let minDelaySpeedToSync: TimeInterval = 0.02
    private static let maxDelaySpeedToSync: TimeInterval = 3
    private static let speedToSyncDuration: TimeInterval = 1
    /// Vitesse plancher d'un rattrapage en avance : en dessous, on allonge la correction.
    private static let minSpeedToSync: Double = 0.2
    private static let minDelaySkipToSync: TimeInterval = 0.4

    // TimeSync de jellyfin-web : 3 mesures rapprochées, puis une par minute, 8 gardées.
    private static let greedyPingCount = 3
    private static let greedyPingInterval: TimeInterval = 1
    private static let pingInterval: TimeInterval = 60
    private static let trackedMeasurements = 8

    /// En dessous, pas de pause pour attendre `when` : VLC n'aurait pas le temps de confirmer
    /// la pause avant le play (cf. la course du démarrage).
    private static let minScheduledPause: TimeInterval = 0.3
    /// Au-delà, `when` est jugé aberrant (horloge locale fausse, mesures ratées) : on part
    /// quand même plutôt que de rester en pause.
    private static let maxScheduledDelay: TimeInterval = 5
    /// VLC arrondit la cible d'un seek : l'écho d'un seek du groupe se reconnaît à 1 s près.
    private static let seekEchoTolerance: TimeInterval = 1
    /// Relance de `Ready` tant que le groupe ne nous a pas relancés (voir `sendReady`) :
    /// toutes les 3 s, 10 fois au plus = les 30 s de patience du serveur.
    private static let readyRetryInterval: TimeInterval = 3
    private static let readyRetryCount = 10
    private static let ticksPerSecond = Double(Duration.seconds(1).ticks)

    @Published
    private(set) var group: GroupInfoDto?
    @Published
    private(set) var pendingInvite: SyncPlayInvite?

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
    private var readyRetry: Task<Void, Never>?
    /// Correction de dérive suspendue (démarrage, correction en cours) jusqu'à cette date.
    private var driftCheckResumesAt: Date = .distantFuture

    private weak var userSession: UserSession?
    private weak var player: MediaPlayerManager?
    private var cancellables: Set<AnyCancellable> = []
    /// Abonnements au lecteur courant, remplacés à chaque nouveau lecteur.
    private var playerCancellables: Set<AnyCancellable> = []
    private let logger = Logger.swiftfin()

    var groupID: String? {
        group?.groupID
    }

    // MARK: - Actions de l'utilisateur

    func join(groupID: String) {
        pendingInvite = nil
        send(Paths.syncPlayJoinGroup(.init(groupID: groupID)))
    }

    func declineInvite() {
        pendingInvite = nil
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
    /// - delivered (Bool) : faux si la personne n'a aucun appareil connecté
    func sendInvite(to userID: String) async throws -> Bool {
        guard let userSession, let groupID else { return false }
        return try await userSession.enhancedFinClient.inviteToSyncPlay(groupID: groupID, userID: userID)
    }

    /// Ce média est déjà dans le lecteur : le groupe ne doit pas le rouvrir. Seule décision,
    /// partagée avec `UserSessionManager+SocketCommands` qui ouvre le média du groupe.
    func hasLoaded(itemID: String?) -> Bool {
        guard let player, player.state != .stopped else { return false }
        return player.item.id == itemID
    }

    // MARK: - Socket

    private func observe(socket: ServerSocketManager) {
        // Synchrone (les publishers du socket livrent déjà sur le main) : messages traités
        // dans l'ordre d'arrivée, et l'attente (`groupStatus`) notée avant que le lecteur ne
        // bouge, sinon on renverrait l'écho au serveur.
        socket.syncPlayGroupUpdates
            .sink { [weak self] update in
                MainActor.assumeIsolated { self?.onReceive(groupUpdate: update) }
            }
            .store(in: &cancellables)

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
                MainActor.assumeIsolated { self?.pendingInvite = invite }
            }
            .store(in: &cancellables)

        // Le serveur sort du groupe une session dont le socket tombe, et son `GroupLeft` part
        // dans le vide : à la reconnexion, on rejoint le groupe qu'on croyait avoir.
        socket.isConnected
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.rejoinAfterReconnect() }
            }
            .store(in: &cancellables)

        Container.shared.mediaPlayerManagerPublisher()
            .sink { [weak self] manager in
                Task { @MainActor in self?.observe(player: manager) }
            }
            .store(in: &cancellables)
    }

    private func rejoinAfterReconnect() {
        guard let groupID else { return }
        reset()
        send(Paths.syncPlayJoinGroup(.init(groupID: groupID)))
    }

    private func onReceive(groupUpdate: GroupUpdate) {
        switch groupUpdate {
        case let .syncPlayGroupJoinedUpdate(update):
            group = update.data
            startTimeSync()
        case .syncPlayUserJoinedUpdate, .syncPlayUserLeftUpdate:
            // Relu chez le serveur : un même compte peut être là sur deux appareils.
            refreshGroup()
        case .syncPlayGroupLeftUpdate, .syncPlayNotInGroupUpdate:
            reset()
        case let .syncPlayPlayQueueUpdate(update):
            guard let queue = update.data else { return }
            onReceive(queue: queue)
        default:
            // `GroupDoesNotExist`, `LibraryAccessDenied` : réponses à un `Join` raté, on
            // reste dans le groupe où l'on était.
            ()
        }
    }

    private func refreshGroup() {
        guard let userSession, let groupID else { return }

        Task {
            guard let group = try? await userSession.client.send(Paths.syncPlayGetGroup(id: groupID)).value,
                  group.groupID == self.groupID
            else { return }
            self.group = group
        }
    }

    private func onReceive(queue: PlayQueueUpdate) {
        itemID = queue.playingItem?.itemID
        playlistItemID = queue.playingItem?.playlistItemID
        guard queue.changesPlayingItem else { return }

        if let player, hasLoaded(itemID: itemID), hasPlaybackStarted {
            // Déjà dans le lecteur et VLC joue (c'est nous qui l'avons proposé) : pas de
            // rechargement, on se cale sur la position du groupe.
            let startPositionTicks = queue.startPositionTicks ?? 0
            seek(to: startPositionTicks)
            pauseThenReady(player, positionTicks: startPositionTicks)
        } else {
            startPhase = .awaitingPlayback
        }
    }

    private func onReceive(command: SendCommand) {
        scheduledUnpause?.cancel()
        expectedSeekTicks = nil

        let ticks = command.positionTicks
        // Les commandes du groupe ne touchent que son média : rejoindre un groupe (qui envoie
        // `stop`) ne ferme pas ce qu'on regardait, un seek ne vise pas le média précédent.
        let groupPlayer = player?.item.id == itemID ? player : nil

        // Le groupe nous a relancés (ou déplacés) : plus besoin de redire `Ready`. Pas sur
        // `pause` : c'est la réponse du serveur à un `Ready` quand d'autres ne sont pas prêts.
        if command.command != .pause {
            readyRetry?.cancel()
        }

        switch command.command {
        case .unpause:
            if let groupPlayer, let ticks, let when = command.when {
                lastUnpause = (ticks, when)
                scheduleUnpause(groupPlayer, positionTicks: ticks, when: when)
            } else {
                groupStatus = .playing
                groupPlayer?.setPlaybackRequestStatus(status: .playing)
            }
        case .pause, .seek:
            // Une pause recale tout le monde au même endroit. Pendant un seek, le groupe
            // attend : chacun reste en pause jusqu'à l'`unpause`.
            groupStatus = .paused
            stopDriftCorrection()
            groupPlayer?.setPlaybackRequestStatus(status: .paused)

            if groupPlayer != nil, let ticks {
                seek(to: ticks)
                if command.command == .seek {
                    sendReady(positionTicks: ticks)
                }
            }
        case .stop:
            groupStatus = nil
            startPhase = .idle
            stopDriftCorrection()
            groupPlayer?.stop()
        case .none: ()
        }
    }

    /// Comme jellyfin-web : play à l'heure `when` du serveur. Déjà passée (commande reçue en
    /// retard) : on repart tout de suite, là où le groupe doit en être.
    private func scheduleUnpause(_ player: MediaPlayerManager, positionTicks: Int, when: Date) {
        let delay = min(localDate(fromServer: when).timeIntervalSinceNow, Self.maxScheduledDelay)

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
        if abs(Double(player.seconds.ticks - positionTicks)) / Self.ticksPerSecond > Self.minDelaySkipToSync {
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

    // MARK: - Lecteur

    private func observe(player manager: MediaPlayerManager?) {
        player = manager
        playerCancellables = []

        // Plus de lecteur : un démarrage en cours est abandonné.
        guard let manager else {
            startPhase = .idle
            return
        }

        // Les sauts de fil (`Task`) sont voulus : `actions` émet *avant* que le manager
        // applique l'action. Sans eux, le `proxy.pause()` du démarrage serait écrasé par le
        // `proxy.play()` de `set(.playing)`.
        manager.$playbackItem
            .compactMap { $0 }
            .sink { [weak self] item in
                Task { @MainActor in self?.player(didLoad: item) }
            }
            .store(in: &playerCancellables)

        manager.actions
            .sink { [weak self, weak manager] action in
                guard case let .setPlaybackRequestStatus(status) = action, let manager else { return }
                Task { @MainActor in self?.player(manager, didReport: status) }
            }
            .store(in: &playerCancellables)

        // `@Published` renvoie sa valeur actuelle à l'abonnement : ce n'est pas un changement.
        manager.$playbackRequestStatus
            .dropFirst()
            .sink { [weak self, weak manager] status in
                guard let manager else { return }
                Task { @MainActor in self?.player(manager, didChangeTo: status) }
            }
            .store(in: &playerCancellables)

        manager.seeks
            .sink { [weak self, weak manager] seconds in
                guard let manager else { return }
                Task { @MainActor in self?.player(manager, didSeekTo: seconds) }
            }
            .store(in: &playerCancellables)

        // Chaque nouvelle position de VLC (~50 Hz) : l'heure est prise tout de suite, pas après
        // un saut de fil, pour ne pas fausser l'écart mesuré.
        manager.secondsBox.$value
            .sink { [weak self] position in
                let now = Date()
                MainActor.assumeIsolated { self?.checkDrift(position: position, at: now) }
            }
            .store(in: &playerCancellables)
    }

    /// VLC signale ses changements d'état par `setPlaybackRequestStatus`.
    private func player(_ manager: MediaPlayerManager, didReport status: MediaPlayerManager.PlaybackRequestStatus) {
        if status == .playing {
            hasPlaybackStarted = true
        }

        guard groupID != nil, manager.item.id == itemID else { return }

        switch (startPhase, status) {
        case (.awaitingPlayback, .playing):
            pauseThenReady(manager, positionTicks: nil)
        case let (.awaitingPause(positionTicks), .paused):
            startPhase = .idle
            sendReady(positionTicks: positionTicks ?? manager.seconds.ticks)
        default: ()
        }
    }

    /// Pause locale, puis `Ready` une fois la pause confirmée par VLC : sa pause est
    /// asynchrone, et l'`unpause` rapide du groupe se ferait écraser par elle.
    private func pauseThenReady(_ manager: MediaPlayerManager, positionTicks: Int?) {
        groupStatus = .paused

        if manager.playbackRequestStatus == .paused {
            startPhase = .idle
            sendReady(positionTicks: positionTicks ?? manager.seconds.ticks)
        } else {
            startPhase = .awaitingPause(positionTicks: positionTicks)
            manager.proxy?.pause()
        }
    }

    // Un média lancé ici, hors demande du groupe : on le propose au groupe. Le serveur
    // renvoie un `PlayQueue` à tous, qui l'ouvrent ; chez nous il est déjà chargé.
    private func player(didLoad item: MediaPlayerItem) {
        hasPlaybackStarted = false

        guard groupID != nil, let id = item.baseItem.id, id != itemID else { return }

        // Un démarrage demandé par le groupe qui n'a jamais abouti (`playItem` en échec)
        // est abandonné au profit de ce média.
        startPhase = .idle

        let request = PlayRequestDto(
            playingItemPosition: 0,
            playingQueue: [id],
            startPositionTicks: item.baseItem.startSeconds?.ticks ?? 0
        )
        send(Paths.syncPlaySetNewQueue(request))
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

        if let expectedSeekTicks, abs(Double(ticks - expectedSeekTicks)) / Self.ticksPerSecond < Self.seekEchoTolerance {
            self.expectedSeekTicks = nil
            return
        }

        guard startPhase == .idle, groupStatus != nil, manager.item.id == itemID else { return }
        send(Paths.syncPlaySeek(.init(positionTicks: ticks)))
    }

    // MARK: - Horloge (TimeSync de jellyfin-web)

    private func startTimeSync() {
        guard timeSyncTask == nil else { return }

        timeSyncTask = Task { [weak self] in
            var count = 0
            while !Task.isCancelled {
                guard let self else { return }
                await measureClockOffset()
                count += 1
                let interval = count < Self.greedyPingCount ? Self.greedyPingInterval : Self.pingInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Principe de NTP : l'aller-retour réseau s'annule dans la moyenne des deux écarts.
    /// On retient la mesure au plus court aller-retour, la moins perturbée par le réseau.
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

        clockMeasurements = Array((clockMeasurements + [(offset, delay)]).suffix(Self.trackedMeasurements))
        clockOffset = clockMeasurements.min { $0.delay < $1.delay }?.offset ?? 0
        logger.debug("SyncPlay : horloge", metadata: ["offsetMs": .stringConvertible(Int(clockOffset * 1000)), "rttMs": .stringConvertible(Int(delay * 1000))])
    }

    private func localDate(fromServer date: Date) -> Date {
        date.addingTimeInterval(-clockOffset)
    }

    private func serverDate(at date: Date = Date()) -> Date {
        date.addingTimeInterval(clockOffset)
    }

    /// Position du groupe à l'instant `date` : celle de la commande + le temps écoulé depuis.
    private func groupPositionTicks(from positionTicks: Int, since when: Date, at date: Date = Date()) -> Int {
        let elapsed = serverDate(at: date).timeIntervalSince(when)
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
        lastUnpause = nil
        restoreRate()
    }

    private func restoreRate() {
        guard rateReset != nil else { return }
        rateReset?.cancel()
        rateReset = nil

        if let player {
            player.proxy?.setRate(player.rate)
        }
    }

    /// Toutes les 1,5 s : écart de 20 ms à 3 s → vitesse `1 + écart / 1 s` pendant 1 s ;
    /// au-delà de 3 s → seek vers la position du groupe.
    private func checkDrift(position: Duration, at date: Date) {
        guard date >= driftCheckResumesAt,
              let player, let lastUnpause,
              groupStatus == .playing, startPhase == .idle,
              player.playbackRequestStatus == .playing,
              player.item.id == itemID
        else { return }

        let groupTicks = groupPositionTicks(from: lastUnpause.positionTicks, since: lastUnpause.when, at: date)
        let diff = Double(groupTicks - position.ticks) / Self.ticksPerSecond
        let absDiff = abs(diff)
        driftCheckResumesAt = date.addingTimeInterval(Self.driftCheckInterval)

        if absDiff >= Self.minDelaySpeedToSync, absDiff < Self.maxDelaySpeedToSync {
            // En forte avance, on allonge la correction plutôt que de descendre sous le plancher.
            let duration = max(Self.speedToSyncDuration, -diff / (1 - Self.minSpeedToSync))
            let rate = 1 + diff / duration
            logger.debug("SyncPlay : speed-to-sync", metadata: ["diffMs": .stringConvertible(Int(diff * 1000)), "rate": .stringConvertible(rate)])

            player.proxy?.setRate(Float(rate))
            driftCheckResumesAt = date.addingTimeInterval(max(duration, Self.driftCheckInterval))

            rateReset?.cancel()
            rateReset = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.restoreRate()
            }
        } else if absDiff >= Self.maxDelaySpeedToSync {
            logger.debug("SyncPlay : skip-to-sync", metadata: ["diffMs": .stringConvertible(Int(diff * 1000))])
            seek(to: groupTicks)
        }
    }

    // MARK: - Envoi

    /// `Ready`, redit tant que le groupe ne nous a pas relancés : un `unpause` perdu (vu sur
    /// iPhone, 2 démarrages sur 3) laissait le lecteur en pause. Comme jellyfin-web, qui redit
    /// `Ready` à chaque événement du lecteur : dans un groupe qui joue déjà, le serveur répond
    /// par un `unpause` à nous seuls ; s'il attend encore quelqu'un, par un `pause` sans effet.
    private func sendReady(positionTicks: Int) {
        readyRetry?.cancel()
        postReady(positionTicks: positionTicks)

        readyRetry = Task { [weak self] in
            for _ in 0 ..< Self.readyRetryCount {
                try? await Task.sleep(for: .seconds(Self.readyRetryInterval))
                guard !Task.isCancelled, let self else { return }
                postReady(positionTicks: positionTicks)
            }
        }
    }

    private func postReady(positionTicks: Int) {
        let state = PlaybackQueueStateInfo(
            isPlaying: false,
            playlistItemID: playlistItemID,
            positionTicks: positionTicks,
            when: serverDate()
        )
        send(Paths.syncPlayReady(state))
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

    /// Hors groupe : on oublie tout ce qui concerne le groupe.
    private func reset() {
        scheduledUnpause?.cancel()
        readyRetry?.cancel()
        stopDriftCorrection()
        timeSyncTask?.cancel()
        timeSyncTask = nil
        clockMeasurements = []
        group = nil
        itemID = nil
        playlistItemID = nil
        groupStatus = nil
        expectedSeekTicks = nil
        startPhase = .idle
    }
}

extension SyncPlayManager: UserSessionService {

    func didStart(userSession: UserSession) {
        self.userSession = userSession
        observe(socket: userSession.serverSocketManager)
    }

    func willStop(userSession: UserSession) {
        cancellables = []
        playerCancellables = []
        player = nil
        pendingInvite = nil
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
