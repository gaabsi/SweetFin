//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

/// SweetFin : l'overlay du lecteur iOS, sur le modèle du web Jellyfin (ElegantFin).
///
/// Remplace `VideoPlayer.PlaybackControls` (upstream, gardé intact) dans
/// `VideoPlayer.swift`. Seule l'interface change : moteur, `MediaPlayerManager`, gestes
/// et sous-titres sont ceux d'upstream.
///
/// - haut : `‹` et « Série - S1:E1 - Titre (année) » ;
/// - bas : précédent · recul · lecture · avance · suivant, et à droite la pile
///   (épisodes) et l'engrenage ; dessous, la barre de progression
///   (`PlaybackProgress`, réutilisée telle quelle) ;
/// - rien au centre de l'image.
struct SweetFinPlaybackControls: View {

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardInterval
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardInterval

    // Cette vue ignore la zone de sécurité : elle la lit depuis ses parents.
    @Environment(\.safeAreaInsets)
    private var safeAreaInsets

    @EnvironmentObject
    private var containerState: VideoPlayerContainerState
    @EnvironmentObject
    private var manager: MediaPlayerManager

    @Router
    private var router

    @State
    private var isPresentingPauseScreen = false

    private var isPresentingOverlay: Bool {
        containerState.isPresentingOverlay
    }

    private var isScrubbing: Bool {
        containerState.isScrubbing
    }

    private var isPresentingFullScreenSupplement: Bool {
        !containerState.isCompact &&
            containerState.selectedSupplement?.presentationStyle == .expanded
    }

    var body: some View {
        ZStack {
            controls

            if isPresentingPauseScreen {
                SweetFinPauseScreen(onClose: closePauseScreen)
                    .transition(.opacity)
            }
        }
        .modifier(VideoPlayer.KeyCommandsModifier())
        .task(id: manager.playbackRequestStatus) {
            await presentPauseScreenAfterDelay()
        }
        .animation(.linear(duration: 0.1), value: isScrubbing)
        .animation(.bouncy(duration: 0.4), value: containerState.isPresentingSupplement)
        .animation(.bouncy(duration: 0.25), value: isPresentingOverlay)
        .animation(.easeInOut(duration: 0.4), value: isPresentingPauseScreen)
        .disabled(manager.error != nil)
    }

    private var controls: some View {
        VStack {
            topBar
                .isVisible(!isScrubbing && isPresentingOverlay && !isPresentingFullScreenSupplement)
                .padding(.top, safeAreaInsets.top)
                .padding(.leading, safeAreaInsets.leading)
                .padding(.trailing, safeAreaInsets.trailing)
                .offset(y: isPresentingOverlay ? 0 : -20)

            Spacer()
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                buttonRow
                    .isVisible(!isScrubbing)

                VideoPlayer.PlaybackControls.PlaybackProgress()
            }
            .isVisible(isPresentingOverlay && !containerState.isPresentingSupplement)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
            .background {
                if isPresentingOverlay && !containerState.isPresentingSupplement {
                    EmptyHitTestView()
                }
            }
        }
    }

    // MARK: - Écran de pause

    /// Délai avant l'écran de pause, comme sur le web : une pause courte ne le déclenche
    /// pas.
    private static let pauseScreenDelay: Duration = .seconds(5)

    /// Présente l'écran de pause après `pauseScreenDelay` de pause, et le retire dès
    /// que la lecture reprend.
    ///
    /// Relancé à chaque changement d'état (`task(id:)`) : reprendre avant la fin du
    /// délai annule la tâche, donc rien ne s'affiche.
    private func presentPauseScreenAfterDelay() async {
        guard manager.playbackRequestStatus == .paused else {
            isPresentingPauseScreen = false
            return
        }

        try? await Task.sleep(for: Self.pauseScreenDelay)

        guard !Task.isCancelled,
              manager.playbackRequestStatus == .paused,
              !containerState.isPresentingSupplement,
              !isScrubbing
        else { return }

        isPresentingPauseScreen = true
        containerState.isPresentingOverlay = false
    }

    /// Ferme l'écran de pause et rend la main à l'overlay, toujours en pause.
    private func closePauseScreen() {
        isPresentingPauseScreen = false
        containerState.isPresentingOverlay = true
    }

    // MARK: - Haut

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: close) {
                Image(systemName: containerState.isPresentingSupplement ? "chevron.down" : "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(L10n.close)

            Text(Self.title(of: manager.item))
                .font(.title3)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .edgePadding(.horizontal)
        .background {
            EmptyHitTestView()
        }
    }

    // MARK: - Bas

    private var buttonRow: some View {
        HStack(spacing: 28) {
            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .previous)
            }

            if !manager.item.isLiveStream {
                Button(PlayerStrings.jumpBackward, systemImage: "backward.fill") {
                    manager.proxy?.jumpBackward(jumpBackwardInterval.rawValue)
                }
            }

            playButton

            if !manager.item.isLiveStream {
                Button(PlayerStrings.jumpForward, systemImage: "forward.fill") {
                    manager.proxy?.jumpForward(jumpForwardInterval.rawValue)
                }
            }

            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .next)
            }

            Spacer()

            episodesButton

            if let playbackItem = manager.playbackItem {
                SettingsMenu(playbackItem: playbackItem)
            }
        }
        .labelStyle(.iconOnly)
        // Symboles pleins, comme le lecteur natif, mais petits : en `.title2` ils
        // étaient massifs, et leurs contours (`backward`, `play`…) sonnent faux.
        .font(.title3)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .edgePadding(.horizontal)
        .background {
            EmptyHitTestView()
        }
    }

    private var playButton: some View {
        Button {
            switch manager.playbackRequestStatus {
            case .playing:
                manager.setPlaybackRequestStatus(status: .paused)
            case .paused:
                manager.setPlaybackRequestStatus(status: .playing)
            }
        } label: {
            switch manager.playbackRequestStatus {
            case .playing:
                Label(L10n.pause, systemImage: "pause.fill")
            case .paused:
                Label(L10n.play, systemImage: "play.fill")
            }
        }
        // Un cran au-dessus des autres : c'est le repère de la rangée.
        .font(.title2)
        .frame(width: 44)
    }

    /// La pile : ouvre les épisodes, seul panneau du lecteur iOS (voir
    /// `MediaPlayerManager.setSupplements`). Absente sans file d'attente (un film).
    @ViewBuilder
    private var episodesButton: some View {
        if let queue = manager.queue {
            Button(PlayerStrings.episodes, systemImage: "rectangle.stack") {
                containerState.select(supplement: queue)
            }
        }
    }

    /// Replie le panneau ouvert s'il y en a un, sinon ferme le lecteur — même règle que
    /// le bouton fermer d'upstream.
    private func close() {
        if containerState.isPresentingSupplement {
            containerState.select(supplement: nil)
        } else {
            manager.stop()
            router.dismiss()
        }
    }

    /// Le titre, comme sur le web : « Série - S1:E1 - Titre (année) » pour un épisode,
    /// « Titre (année) » sinon.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item en lecture
    ///
    /// Output :
    /// - title (String) : le titre à afficher
    private static func title(of item: BaseItemDto) -> String {
        let parts = [item.seriesName, item.seasonEpisodeLabel, item.displayTitle].compactMap(\.self)
        let title = parts.joined(separator: " - ")

        guard let year = item.productionYear else { return title }

        return "\(title) (\(year))"
    }
}

/// Précédent / suivant dans la file d'attente, au style de la rangée.
///
/// Réécrit plutôt que réutilisé : `PlayPreviousItem` / `PlayNextItem` d'upstream sont
/// pensés pour les menus de la barre ; ici ils prennent le style de la rangée. Même
/// logique qu'eux : grisé s'il n'y a rien.
private struct QueueButton: View {

    enum Direction {
        case previous
        case next
    }

    @EnvironmentObject
    private var manager: MediaPlayerManager

    @ObservedObject
    var queue: AnyMediaPlayerQueue

    let direction: Direction

    private var provider: MediaPlayerItemProvider? {
        direction == .previous ? queue.previousItem : queue.nextItem
    }

    var body: some View {
        Button(
            direction == .previous ? L10n.playPreviousItem : L10n.playNextItem,
            systemImage: direction == .previous ? "backward.end.fill" : "forward.end.fill"
        ) {
            guard let provider else { return }
            manager.playNewItem(provider: provider)
        }
        .disabled(provider == nil)
    }
}

/// L'engrenage : un seul menu pour tous les réglages de lecture.
///
/// - qualité : **affichée, pas modifiable**, c'est l'admin qui décide ;
/// - vitesse ;
/// - langue : grisée quand il n'y a qu'une piste, rien à choisir ;
/// - sous-titres : grisés seulement sans aucune piste (« Aucun » reste un choix).
///
/// Un menu du fork plutôt que les boutons d'upstream (`Audio`, `Subtitles`,
/// `PlaybackRateMenu`) : pensés pour la barre, ils ouvrent chacun leur propre menu.
private struct SettingsMenu: View {

    private let rates = SweetFinPlayerPolicy.playbackRates

    @EnvironmentObject
    private var manager: MediaPlayerManager

    /// Observé pour que le libellé des pistes suive le choix fait.
    @ObservedObject
    var playbackItem: MediaPlayerItem

    /// La définition de la vidéo telle que Jellyfin la décrit (« 1080p H264 SDR »).
    private var quality: String {
        playbackItem.videoStreams.first?.displayTitle ?? L10n.unknown
    }

    private var audioTitle: String {
        playbackItem.audioStreams
            .first { $0.index == playbackItem.selectedAudioStreamIndex }?
            .displayTitle ?? L10n.none
    }

    private var subtitleTitle: String {
        playbackItem.subtitleStreams
            .first { $0.index == playbackItem.selectedSubtitleStreamIndex }?
            .displayTitle ?? L10n.none
    }

    var body: some View {
        Menu {
            Section(L10n.playbackQuality) {
                Text(quality)
            }

            Picker(selection: $manager.rate) {
                ForEach(rates, id: \.self) { rate in
                    Text(rate, format: .playbackRate)
                        .tag(rate)
                }
            } label: {
                Text(L10n.playbackSpeed)
                Text(manager.rate, format: .playbackRate)
            }
            .pickerStyle(.menu)

            Picker(selection: $playbackItem.selectedAudioStreamIndex) {
                ForEach(playbackItem.audioStreams, id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            } label: {
                Text(PlayerStrings.language)
                Text(audioTitle)
            }
            .pickerStyle(.menu)
            .disabled(playbackItem.audioStreams.count <= 1)

            Picker(selection: $playbackItem.selectedSubtitleStreamIndex) {
                ForEach(playbackItem.subtitleStreams.prepending(.none), id: \.index) { stream in
                    Text(stream.displayTitle ?? L10n.unknown)
                        .tag(stream.index as Int?)
                }
            } label: {
                Text(L10n.subtitles)
                Text(subtitleTitle)
            }
            .pickerStyle(.menu)
            // Grisé seulement sans aucune piste : avec une seule, « Aucun » reste un choix
            // (activer ou couper les sous-titres).
            .disabled(playbackItem.subtitleStreams.isEmpty)
        } label: {
            Label(PlayerStrings.settings, systemImage: "gearshape.fill")
        }
    }
}
