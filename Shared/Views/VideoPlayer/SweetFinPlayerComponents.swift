//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

// SweetFin : briques communes aux lecteurs iPhone (`SweetFinPlaybackControls`) et tvOS
// (`VideoPlayer.PlaybackControls`).

enum SweetFinPlayer {

    /// Le titre, comme sur le web : « Série - S1:E1 - Titre (année) » pour un épisode,
    /// « Titre (année) » sinon.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item en lecture
    ///
    /// Output :
    /// - title (String) : le titre à afficher
    static func title(of item: BaseItemDto) -> String {
        let parts = [item.seriesName, item.seasonEpisodeLabel, item.displayTitle].compactMap(\.self)
        let title = parts.joined(separator: " - ")

        guard let year = item.productionYear else { return title }

        return "\(title) (\(year))"
    }
}

/// Précédent / suivant dans la file d'attente, au style de la rangée (iPhone et tvOS).
///
/// Réécrit plutôt que réutilisé : `PlayPreviousItem` / `PlayNextItem` d'upstream sont
/// pensés pour les menus de la barre ; ici ils prennent le style de la rangée. Même
/// logique qu'eux : grisé s'il n'y a rien.
struct QueueButton: View {

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

/// Recul / avance de l'intervalle choisi dans les réglages. Absent pour un direct.
struct JumpButton: View {

    enum Direction {
        case backward
        case forward
    }

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardInterval
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardInterval

    @EnvironmentObject
    private var manager: MediaPlayerManager

    let direction: Direction

    var body: some View {
        if !manager.item.isLiveStream {
            switch direction {
            case .backward:
                Button(PlayerStrings.jumpBackward, systemImage: "backward.fill") {
                    manager.proxy?.jumpBackward(jumpBackwardInterval.rawValue)
                }
            case .forward:
                Button(PlayerStrings.jumpForward, systemImage: "forward.fill") {
                    manager.proxy?.jumpForward(jumpForwardInterval.rawValue)
                }
            }
        }
    }
}

/// Lecture / Pause, l'icône suit l'état demandé.
struct PlayPauseButton: View {

    @EnvironmentObject
    private var manager: MediaPlayerManager

    var body: some View {
        Button {
            manager.togglePlayPause()
        } label: {
            switch manager.playbackRequestStatus {
            case .playing:
                Label(L10n.pause, systemImage: "pause.fill")
            case .paused:
                Label(L10n.play, systemImage: "play.fill")
            }
        }
    }
}

/// La pile : ouvre le panneau des épisodes. Absente sans file d'attente (un film).
struct EpisodesButton: View {

    @EnvironmentObject
    private var containerState: VideoPlayerContainerState
    @EnvironmentObject
    private var manager: MediaPlayerManager

    var body: some View {
        if let queue = manager.queue {
            Button(PlayerStrings.episodes, systemImage: "rectangle.stack") {
                containerState.select(supplement: queue)
            }
        }
    }
}

/// L'engrenage : un seul menu pour tous les réglages de lecture (iPhone et tvOS).
///
/// - qualité : **affichée, pas modifiable**, c'est l'admin qui décide ;
/// - vitesse ;
/// - langue : grisée quand il n'y a qu'une piste, rien à choisir ;
/// - sous-titres : grisés seulement sans aucune piste (« Aucun » reste un choix).
///
/// Un menu du fork plutôt que les boutons d'upstream (`Audio`, `Subtitles`,
/// `PlaybackRateMenu`) : pensés pour la barre, ils ouvrent chacun leur propre menu.
struct SettingsMenu: View {

    private let rates = SweetFinPlayerPolicy.playbackRates

    @Default(.VideoPlayer.Subtitles.extraLanguages)
    private var extraSubtitleLanguages
    @Default(.VideoPlayer.Subtitles.showSDH)
    private var showSDH
    @Default(.VideoPlayer.Audio.showAudioDescription)
    private var showAudioDescription

    @EnvironmentObject
    private var manager: MediaPlayerManager

    /// Observé pour que le libellé des pistes suive le choix fait.
    @ObservedObject
    var playbackItem: MediaPlayerItem

    /// La définition de la vidéo : résolution · codec · plage (« 1080p · H264 · SDR »), tirées
    /// des propriétés de la piste. ❌ `displayTitle` de Jellyfin : il y ajoute le titre de
    /// piste écrit dans le fichier, parfois long et sans intérêt. Résolution lue sur la
    /// largeur : un 1080p recadré fait 1920 × 960.
    private var quality: String {
        guard let video = playbackItem.videoStreams.first else { return L10n.unknown }

        let width = video.width ?? 0
        let resolution: String? = switch width {
        case 3200...: "4K"
        case 1800...: "1080p"
        case 1200...: "720p"
        default: video.height.map { "\($0)p" }
        }
        let range: String? = switch video.videoRangeType?.rawValue ?? video.videoRange?.rawValue {
        case let raw? where raw.hasPrefix("DOVI"): "Dolby Vision"
        case "HDR10Plus": "HDR10+"
        case let raw: raw
        }

        let parts = [resolution, video.codec?.uppercased(), range].compactMap(\.self)
        return parts.isEmpty ? L10n.unknown : parts.joined(separator: " · ")
    }

    private var audioTitle: String {
        title(of: playbackItem.selectedAudioStreamIndex, among: playbackItem.audioStreams)
    }

    private var subtitleTitle: String {
        title(of: playbackItem.selectedSubtitleStreamIndex, among: playbackItem.subtitleStreams)
    }

    /// Les pistes audio retenues par `MediaTrackFilter`.
    private var visibleAudioStreams: [MediaStream] {
        MediaTrackFilter.visibleAudio(
            playbackItem.audioStreams,
            showAudioDescription: showAudioDescription,
            selectedIndex: playbackItem.selectedAudioStreamIndex
        )
    }

    /// Les sous-titres retenus par `MediaTrackFilter`, selon les réglages de l'utilisateur.
    private var visibleSubtitleStreams: [MediaStream] {
        let preferences = MediaTrackFilter.SubtitlePreferences(
            preferredLanguage: Container.shared.currentUserSession()?.user.data.configuration?.subtitleLanguagePreference,
            extraLanguages: extraSubtitleLanguages,
            showSDH: showSDH
        )

        return MediaTrackFilter.visibleSubtitles(
            playbackItem.subtitleStreams,
            preferences: preferences,
            selectedIndex: playbackItem.selectedSubtitleStreamIndex
        )
    }

    /// Le libellé de la piste en cours, « Aucun » s'il n'y en a pas.
    ///
    /// Parametres :
    /// - index (Int?) : index de la piste en cours
    /// - streams ([MediaStream]) : les pistes du même type
    ///
    /// Output :
    /// - title (String) : le libellé
    private func title(of index: Int?, among streams: [MediaStream]) -> String {
        guard let stream = streams.first(where: { $0.index == index }) else { return L10n.none }

        return MediaTrackFilter.label(of: stream, among: streams)
    }

    var body: some View {
        Menu {
            // Plusieurs versions (un film en plusieurs fichiers, plusieurs qualités) : on
            // choisit, la lecture reprend au même endroit.
            if let versions = playbackItem.baseItem.mediaSources, versions.count > 1 {
                Picker(selection: Binding(
                    get: { playbackItem.mediaSource.id },
                    set: { id in
                        guard let version = versions.first(where: { $0.id == id }) else { return }
                        manager.switchVersion(to: version)
                    }
                )) {
                    ForEach(versions, id: \.id) { version in
                        Text(version.displayTitle)
                            .tag(version.id)
                    }
                } label: {
                    Text(L10n.playbackQuality)
                    Text(playbackItem.mediaSource.displayTitle)
                }
                .pickerStyle(.menu)
            } else {
                Section(L10n.playbackQuality) {
                    Text(quality)
                }
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
                ForEach(visibleAudioStreams, id: \.index) { stream in
                    Text(MediaTrackFilter.label(of: stream, among: playbackItem.audioStreams))
                        .tag(stream.index as Int?)
                }
            } label: {
                Text(PlayerStrings.language)
                Text(audioTitle)
            }
            .pickerStyle(.menu)
            .disabled(visibleAudioStreams.count <= 1)

            Picker(selection: $playbackItem.selectedSubtitleStreamIndex) {
                Text(L10n.none)
                    .tag(MediaStream.none.index as Int?)

                ForEach(visibleSubtitleStreams, id: \.index) { stream in
                    Text(MediaTrackFilter.label(of: stream, among: playbackItem.subtitleStreams))
                        .tag(stream.index as Int?)
                }
            } label: {
                Text(L10n.subtitles)
                Text(subtitleTitle)
            }
            .pickerStyle(.menu)
            // Grisé seulement sans aucune piste proposée : avec une seule, « Aucun » reste
            // un choix (activer ou couper les sous-titres).
            .disabled(visibleSubtitleStreams.isEmpty)
        } label: {
            #if os(tvOS)
            // La taille vient de la rangée tvOS (bouton rond, style d'upstream).
            Label(PlayerStrings.settings, systemImage: "gearshape")
            #else
            // Un `Menu` ne prend pas `PlayerRowButtonStyle` : même zone de tap, posée ici.
            Label(PlayerStrings.settings, systemImage: "gearshape")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            #endif
        }
    }
}

/// Roue de chargement au centre du lecteur. Observe le chargement de VLC (`isBuffering`
/// du proxy) : ❌ avant, seule la résolution de l'item l'affichait, une coupure réseau
/// laissait l'image figée sans rien (vécu le 2026-11-15).
struct LoadingIndicator: View {

    @ObservedObject
    var isBuffering: PublishedBox<Bool>

    let isLoadingItem: Bool

    var body: some View {
        if isLoadingItem || isBuffering.value {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.white)
                .allowsHitTesting(false)
        }
    }
}

// SweetFin : changer de version en reprenant à la position courante (engrenage,
// `SettingsMenu`).
extension MediaPlayerManager {

    /// Passe sur une autre version de l'item en lecture, reprise à la position courante.
    /// Sans effet si c'est déjà elle.
    ///
    /// Parametres :
    /// - mediaSource (MediaSourceInfo) : la version voulue
    func switchVersion(to mediaSource: MediaSourceInfo) {
        guard let playbackItem, mediaSource.id != playbackItem.mediaSource.id else { return }

        var adjustedBaseItem = playbackItem.baseItem
        adjustedBaseItem.userData?.playbackPositionTicks = seconds.ticks
        let provider = MediaPlayerItemProvider(item: adjustedBaseItem, mediaSource: mediaSource) { baseItem, modifyItem in
            try await MediaPlayerItem.build(
                for: baseItem,
                mediaSource: mediaSource,
                modifyItem: modifyItem
            )
        }
        playNewItem(provider: provider)
    }
}
