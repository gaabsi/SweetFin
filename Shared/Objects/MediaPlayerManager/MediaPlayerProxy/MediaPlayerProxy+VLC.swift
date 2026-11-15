//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import Network
import SwiftUI
import SwiftVLC

@MainActor
class VLCMediaPlayerProxy: VideoMediaPlayerProxy,
    MediaPlayerOffsetConfigurable,
    MediaPlayerSubtitleConfigurable
{

    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)
    let droppedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let corruptedFrames: PublishedBox<Int> = .init(initialValue: 0)
    let player = Player()

    private var pendingStartTime: Duration?

    // SweetFin : reprise après une coupure réseau. libVLC ne retente qu'une fois, au moment
    // où la connexion casse ; réseau encore absent, la lecture gèle et ne repart plus, même
    // réseau revenu (vécu le 2026-11-15, mode avion 72 s). Le lecteur attend alors le retour
    // du réseau, puis rouvre le flux à la position du gel (`watchForStall`).
    /// Dernière avance de la position (ou dernière action qui l'explique : pause, saut).
    private var lastAdvance: ContinuousClock.Instant = .now
    /// La position a avancé au moins une fois pour cet item.
    private var hasAdvanced = false
    /// Position du gel : non nulle tant que la lecture attend de repartir.
    private var stalledAt: Duration?
    /// Cible du dernier saut, tant que la lecture ne l'a pas atteinte : un gel pendant le
    /// saut reprend là, pas à l'ancienne position.
    private var seekTarget: Duration?
    /// Le système annonce un réseau (signal de reprise).
    private var isOnline = true
    private let pathMonitor = NWPathMonitor()
    /// Une réouverture vient d'être lancée : l'horloge remise à zéro par VLC n'est pas
    /// une avance, et une erreur (serveur encore muet) ne ferme pas le lecteur.
    private var isReopening = false

    /// Position immobile depuis ce temps alors que la lecture est demandée = gel.
    private static let stallDelay: Duration = .seconds(8)
    /// Attentes entre deux réouvertures quand le réseau est annoncé mais que rien ne
    /// repart (serveur muet, Wi-Fi sans internet) : de plus en plus longues, puis 30 s.
    private static let retryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    /// Lecture demandée, réseau présent, et rien ne repart depuis ce temps : vraie erreur.
    private static let giveUpAfter: Duration = .seconds(5 * 60)

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        pathMonitor.start(queue: .main)
    }

    deinit {
        pathMonitor.cancel()
    }

    weak var manager: MediaPlayerManager? {
        didSet {
            for var o in observers {
                o.manager = manager
            }
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    func play() {
        // SweetFin : pendant une coupure, c'est le chien de garde qui rouvre le flux, à la
        // position du gel ; VLC (figé, arrêté ou en erreur) relancerait le média au début.
        guard stalledAt == nil else { return }
        if player.state == .paused {
            player.resume()
        } else {
            do {
                try player.play()
            } catch {
                failPlayback(error)
            }
        }
    }

    func pause() {
        lastAdvance = .now
        player.pause()
    }

    func stop() {
        pendingStartTime = nil
        isBuffering.value = false
        player.stop()
    }

    func jumpForward(_ seconds: Duration) {
        let target: Duration

        if let runtime = manager?.item.runtime, let current = manager?.seconds {
            let remaining = max(.zero, runtime - current)
            target = min(seconds, remaining)
        } else {
            target = seconds
        }

        guard target > .zero else { return }

        noteSeek(to: (manager?.seconds ?? .zero) + target)
        player.jump(by: target)
        // SweetFin : SyncPlay
        manager?.seeks.send((manager?.seconds ?? .zero) + target)
    }

    func jumpBackward(_ seconds: Duration) {
        noteSeek(to: max(.zero, (manager?.seconds ?? .zero) - seconds))
        player.jump(by: .zero - seconds)
        // SweetFin : SyncPlay
        manager?.seeks.send(max(.zero, (manager?.seconds ?? .zero) - seconds))
    }

    func setRate(_ rate: Float) {
        do {
            try player.setPlaybackRate(PlaybackRate(rate))
        } catch {
            log(error)
        }
    }

    func setSeconds(_ seconds: Duration) {
        guard player.isSeekable else { return }

        pendingStartTime = nil

        do {
            noteSeek(to: seconds)
            try player.seek(to: seconds)
            // SweetFin : SyncPlay
            manager?.seeks.send(seconds)
        } catch {
            log(error)
        }
    }

    func setAudioStream(_ stream: MediaStream) {
        guard let index = stream.index, player.audioTracks.indices.contains(index) else {
            player.selectedAudioTrack = nil
            return
        }

        let track = player.audioTracks[index]
        guard player.selectedAudioTrack != track else { return }
        player.selectedAudioTrack = track
    }

    func setSubtitleStream(_ stream: MediaStream) {
        guard let index = stream.index, player.subtitleTracks.indices.contains(index) else {
            player.selectedSubtitleTrack = nil
            return
        }

        let track = player.subtitleTracks[index]
        guard player.selectedSubtitleTrack != track else { return }
        player.selectedSubtitleTrack = track
    }

    func setAspectFill(_ aspectFill: Bool) {
        player.aspectRatio = aspectFill ? .fill : .default
    }

    func setAudioOffset(_ seconds: Duration) {
        do {
            try player.setAudioDelay(seconds)
        } catch {
            log(error)
        }
    }

    func setSubtitleOffset(_ seconds: Duration) {
        do {
            try player.setSubtitleDelay(seconds)
        } catch {
            log(error)
        }
    }

    func setSubtitleConfiguration(_ configuration: SubtitleConfiguration) {
        player.setSubtitleScale(.init(approximatePoints: Double(25 - configuration.size)))
    }

    @ViewBuilder
    var videoPlayerBody: some View {
        VLCPlayerView(proxy: self)
    }

    private func log(_ error: Error) {
        manager?.logger.warning("SwiftVLC operation rejected: \(error)")
    }

    private func failPlayback(_ error: Error) {
        manager?.logger.error("SwiftVLC error: \(error)")
        manager?.error(ErrorMessage("VLC player error: \(error.localizedDescription)"))
    }

    /// Applies the resume position as an absolute seek once libVLC has
    /// established the media timeline. Using `:start-time` rebases some
    /// inputs and makes the player's reported time relative to that offset.
    @discardableResult
    private func applyPendingStartTimeIfPossible() -> Bool {
        guard let pendingStartTime else { return false }
        guard player.isSeekable else { return false }

        self.pendingStartTime = nil

        do {
            try player.seek(to: pendingStartTime)
            manager?.seconds = pendingStartTime
        } catch {
            log(error)
        }

        return true
    }

    /// SweetFin : la position avance en lecture. Une reprise est réussie quand la position
    /// est revenue près de celle du gel (pas l'horloge de VLC remise à zéro).
    ///
    /// Parametres :
    /// - position (Duration) : position lue
    ///
    /// Output :
    /// - counts (Bool) : faux si c'est un reste de la réouverture, à ignorer
    func noteAdvance(to position: Duration) -> Bool {
        if let stalledAt, position < stalledAt - .seconds(5) { return false }
        lastAdvance = .now
        hasAdvanced = true
        stalledAt = nil
        seekTarget = nil
        isReopening = false
        return true
    }

    /// SweetFin : un saut repart l'horloge du gel (le temps de charger la nouvelle position
    /// n'est pas un gel) et retient sa cible.
    private func noteSeek(to target: Duration) {
        lastAdvance = .now
        seekTarget = target
    }

    /// SweetFin : la lecture est gelée (flux tari) : la roue s'affiche et on attend le
    /// réseau. La position du gel est gardée une fois pour toutes.
    ///
    /// Parametres :
    /// - position (Duration) : dernière position lue
    func beginStall(at position: Duration) {
        guard stalledAt == nil else { return }
        let at = seekTarget ?? position
        manager?.logger.info("Lecture gelée à \(at) : attente du réseau")
        stalledAt = at
        isBuffering.value = true
    }

    /// SweetFin : une erreur de VLC pendant une reprise ou après un démarrage réussi est
    /// une coupure, pas une fin : on attend le réseau au lieu de fermer le lecteur.
    ///
    /// Parametres :
    /// - position (Duration) : dernière position lue
    ///
    /// Output :
    /// - absorbed (Bool) : vrai si l'erreur est gérée comme une coupure
    func absorbsError(at position: Duration) -> Bool {
        guard isReopening || hasAdvanced else { return false }
        beginStall(at: position)
        return true
    }

    /// SweetFin : une fin annoncée par VLC à plus d'une minute de la fin **du fichier** est
    /// une coupure (flux tari), pas la fin : sinon film fermé et marqué vu. Juste après une
    /// réouverture, c'est la vraie fin (le fichier s'arrête là) : acceptée.
    ///
    /// Parametres :
    /// - position (Duration) : dernière position lue
    /// - runtime (Duration?) : durée annoncée par la fiche, à défaut de celle du fichier
    ///
    /// Output :
    /// - isStall (Bool) : vrai si la fin est traitée comme un gel
    func endIsStall(at position: Duration, runtime: Duration?) -> Bool {
        guard !isReopening, let duration = player.duration ?? runtime, duration - position > .seconds(60) else { return false }
        beginStall(at: position)
        return true
    }

    /// SweetFin : rouvre le même flux à la position du gel (sans nouvel appel au serveur).
    /// VLC est d'abord arrêté : son horloge repasse à zéro pendant l'arrêt, ce que le suivi
    /// de position ignore.
    private func reopen(_ item: MediaPlayerItem, subtitleConfiguration: SubtitleConfiguration) {
        guard let stalledAt else { return }
        manager?.logger.info("Réouverture du flux à \(stalledAt)")
        isReopening = true
        player.stop()
        play(item, subtitleConfiguration: subtitleConfiguration, from: stalledAt)
    }

    /// SweetFin : lecture demandée et réseau présent depuis `giveUpAfter` sans que rien ne
    /// reparte (vraie erreur : fichier abîmé, source disparue) : on arrête d'attendre et on
    /// affiche l'erreur, comme avant.
    private func giveUp() {
        manager?.logger.info("Reprise abandonnée à \(stalledAt ?? .zero) : réseau présent, rien ne repart")
        stalledAt = nil
        isReopening = false
        isBuffering.value = false
        manager?.error(ErrorMessage("VLC player is unable to perform playback"))
    }

    /// SweetFin : chien de garde, le temps de la lecture d'un item. Gel (position immobile
    /// `stallDelay`, lecture demandée) → attente avec la roue ; **sans réseau, aucune
    /// tentative**. Retour du réseau → réouverture immédiate à la position du gel ; échec →
    /// nouvelle tentative après une attente croissante (`retryDelays`), remise à zéro à
    /// chaque retour du réseau, jamais pendant que VLC ouvre ou charge encore, ni dans les
    /// `stallDelay` après qu'il est reparti (la position met un moment à revenir ; vécu : 2ᵉ
    /// réouverture inutile 2 s après la 1ʳᵉ). En pause, rien ne compte. Rien avant que la
    /// lecture ait démarré une fois.
    ///
    /// Parametres :
    /// - item (MediaPlayerItem) : l'item en lecture
    /// - subtitleConfiguration (SubtitleConfiguration) : style des sous-titres
    /// - isScrubbing (() -> Bool) : l'utilisateur glisse sur la barre
    func watchForStall(of item: MediaPlayerItem, subtitleConfiguration: SubtitleConfiguration, isScrubbing: () -> Bool) async {
        var attempt = 0
        var nextTry: ContinuousClock.Instant?
        var wasOnline = isOnline
        // Temps passé à attendre avec réseau et lecture demandée.
        var waited: Duration = .zero
        var state = player.state
        var stateSince: ContinuousClock.Instant = .now

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let online = isOnline
            defer { wasOnline = online }
            if player.state != state {
                state = player.state
                stateSince = .now
            }
            let requested = manager?.playbackRequestStatus == .playing && !isScrubbing()

            // En pause ou en train de glisser : le temps ne compte pas.
            guard requested else {
                lastAdvance = .now
                nextTry = nil
                continue
            }

            if stalledAt == nil {
                guard hasAdvanced, ContinuousClock.now - lastAdvance > Self.stallDelay else {
                    attempt = 0
                    nextTry = nil
                    waited = .zero
                    continue
                }
                beginStall(at: manager?.seconds ?? .zero)
            }

            guard online else { continue }
            waited += .seconds(1)
            if waited > Self.giveUpAfter {
                giveUp()
                return
            }
            if !wasOnline || nextTry == nil {
                attempt = 0
                nextTry = .now
            }
            let isStarting = state == .opening || state == .buffering
                || (state == .playing && ContinuousClock.now - stateSince < Self.stallDelay)
            guard let due = nextTry, ContinuousClock.now >= due, !isStarting else { continue }

            reopen(item, subtitleConfiguration: subtitleConfiguration)
            nextTry = .now + Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
            attempt += 1
        }
    }

    private func play(_ item: MediaPlayerItem, subtitleConfiguration: SubtitleConfiguration, from start: Duration? = nil) {
        do {
            let media = try Media(url: item.url)

            let startSeconds = max(.zero, start ?? item.baseItem.startSeconds ?? .zero)
            // Nouvel item (pas une réouverture) : rien à surveiller avant qu'il démarre.
            if start == nil {
                hasAdvanced = false
                stalledAt = nil
                seekTarget = nil
                isReopening = false
            }

            pendingStartTime = !item.baseItem.isLiveStream && startSeconds > .zero ? startSeconds : nil

            if let client = manager?.userSession?.client {
                for subtitle in item.subtitleStreams.sidecarSubtitles {
                    guard let url = subtitle.url(with: client) else { continue }
                    try media.addSlave(from: url, type: .subtitle)
                }
            }

            // libVLC 4 applies font and color options when opening media.
            // Size remains adjustable during playback through SubtitleScale.
            // SweetFin : lecture anticipée portée de 16 Mo (défaut) à 64 Mo : ~3 min d'avance
            // en 1080p, ~48 s en 4K lourde (11 Mb/s) au lieu de ~12 s ; sans effet sur le démarrage.
            media.addOption(":prefetch-buffer-size=65536")
            media.addOption(":freetype-font=\(subtitleConfiguration.fontName)")
            if let color = Int(subtitleConfiguration.color.hexString.prefix(6), radix: 16) {
                media.addOption(":freetype-color=\(color)")
            }

            try player.play(media)
            setSubtitleConfiguration(subtitleConfiguration)
        } catch {
            pendingStartTime = nil
            if isReopening {
                manager?.logger.info("Réouverture impossible : \(type(of: error))")
                return
            }
            failPlayback(error)
        }
    }
}

extension VLCMediaPlayerProxy {

    struct VLCPlayerView: View {

        @ObservedObject
        var proxy: VLCMediaPlayerProxy

        // SweetFin : style des sous-titres imposé.
        private let subtitleConfiguration = SubtitleConfiguration.default

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        private var isScrubbing: Bool {
            containerState.isScrubbing
        }

        var body: some View {
            if let playbackItem = manager.playbackItem, manager.state != .stopped {
                VideoView(proxy.player)
                    .task(id: ObjectIdentifier(playbackItem)) {
                        proxy.play(playbackItem, subtitleConfiguration: subtitleConfiguration)
                    }
                    .task(id: ObjectIdentifier(playbackItem)) {
                        await proxy.watchForStall(of: playbackItem, subtitleConfiguration: subtitleConfiguration) { isScrubbing }
                    }
                    .onChange(of: proxy.player.currentTime) { _, newSeconds in
                        // Ignore an initial or already superseded timestamp while
                        // the absolute resume seek is being established.
                        guard proxy.player.state == .playing || proxy.player.state == .paused,
                              !proxy.applyPendingStartTimeIfPossible(),
                              newSeconds == proxy.player.currentTime
                        else { return }

                        // SweetFin : reste d'une réouverture (horloge de VLC) : ignoré.
                        guard proxy.noteAdvance(to: newSeconds) else { return }

                        if !isScrubbing {
                            containerState.scrubbedSeconds.value = newSeconds
                        }

                        manager.seconds = newSeconds
                        if proxy.player.state == .playing {
                            proxy.isBuffering.value = false
                        }

                        proxy.videoSize.value = proxy.player.videoSize ?? .zero
                        if let statistics = proxy.player.statistics {
                            proxy.droppedFrames.value = Int(clamping: statistics.lostPictures)
                            proxy.corruptedFrames.value = Int(clamping: statistics.demuxCorrupted)
                        }
                    }
                    .onChange(of: proxy.player.state) { _, state in
                        manager.logger.trace("SwiftVLC state updated: \(state)")

                        switch state {
                        case .buffering, .opening:
                            proxy.isBuffering.value = true
                        case .error:
                            // SweetFin : coupure en pleine lecture ou pendant une reprise : on
                            // attend le réseau au lieu de fermer le lecteur.
                            guard !proxy.absorbsError(at: manager.seconds) else { return }
                            proxy.isBuffering.value = false
                            manager.error(ErrorMessage("VLC player is unable to perform playback"))
                        case .playing:
                            proxy.applyPendingStartTimeIfPossible()
                            proxy.isBuffering.value = false
                            manager.setPlaybackRequestStatus(status: .playing)
                            proxy.setRate(manager.rate)
                            playbackItem.switchTrack(type: .audio, index: playbackItem.selectedAudioStreamIndex)
                            playbackItem.switchTrack(type: .subtitle, index: playbackItem.selectedSubtitleStreamIndex)
                        case .paused:
                            proxy.isBuffering.value = false
                            manager.setPlaybackRequestStatus(status: .paused)
                        case .idle, .stopped, .stopping: ()
                        }

                        proxy.videoSize.value = proxy.player.videoSize ?? .zero
                    }
                    .onChange(of: proxy.player.bufferFill) { _, fill in
                        guard proxy.player.state == .playing else { return }
                        if fill < 0.9 {
                            proxy.isBuffering.value = true
                        } else if fill >= 1 {
                            proxy.isBuffering.value = false
                        }
                    }
                    .onChange(of: proxy.player.isSeekable) { _, isSeekable in
                        guard isSeekable else { return }
                        proxy.applyPendingStartTimeIfPossible()
                    }
                    .onChange(of: proxy.player.didReachEnd) { _, didReachEnd in
                        guard didReachEnd, manager.playbackItem?.baseItem.isLiveStream == false else { return }
                        // SweetFin : fausse fin (flux tari) : attente du réseau, pas de fermeture.
                        guard !proxy.endIsStall(at: manager.seconds, runtime: playbackItem.baseItem.runtime) else { return }
                        // libVLC resets its clock on stop. Report the completed
                        // timeline before the manager decides whether to advance.
                        if let runtime = playbackItem.baseItem.runtime {
                            manager.seconds = runtime
                        }
                        proxy.isBuffering.value = false
                        manager.ended()
                    }
                    .onChange(of: proxy.player.audioTracks) {
                        playbackItem.switchTrack(type: .audio, index: playbackItem.selectedAudioStreamIndex)
                    }
                    .onChange(of: proxy.player.subtitleTracks) {
                        let subtitleTracks = proxy.player.subtitleTracks.enumerated().map {
                            (playerIndex: $0.offset, id: $0.element.id)
                        }
                        playbackItem.updateSubtitleTrackMapping(subtitleTracks: subtitleTracks)
                    }
                    .onChange(of: manager.rate) {
                        proxy.setRate(manager.rate)
                    }
            }
        }
    }
}
