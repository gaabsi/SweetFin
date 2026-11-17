//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// SweetFin : l'overlay du lecteur iOS, sur le modèle du web Jellyfin (ElegantFin).
///
/// Remplace `VideoPlayer.PlaybackControls` d'upstream dans `VideoPlayer.swift`, dont il
/// réutilise la barre de progression.
///
/// - haut : `‹` et « Série - S1:E1 - Titre (année) » ;
/// - bas : précédent · recul · lecture · avance · suivant, et à droite la pile
///   (épisodes) et l'engrenage ; dessous, la barre de progression
///   (`PlaybackProgress`, réutilisée telle quelle) ;
/// - rien au centre de l'image.
struct SweetFinPlaybackControls: View {

    // Cette vue ignore la zone de sécurité : elle la lit depuis ses parents.
    @Environment(\.safeAreaInsets)
    private var safeAreaInsets

    @EnvironmentObject
    private var containerState: VideoPlayerContainerState
    @EnvironmentObject
    private var manager: MediaPlayerManager

    @Router
    private var router

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

            // Hors de `controls` : visible pendant tout le segment, commandes masquées ou non.
            SkipSegmentButton()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, safeAreaInsets.trailing)
                .padding(.bottom, isPresentingOverlay ? Self.skipButtonOverlayOffset : safeAreaInsets.bottom)
                .edgePadding()
                .isVisible(containerState.isSkipSegmentShown)

            // Item pas encore résolu (lecture depuis une tuile), ou VLC qui charge (après un
            // saut, ou coupure réseau en attendant la reprise) : on montre qu'il charge.
            LoadingIndicator(
                isBuffering: manager.proxy?.isBuffering ?? Self.notBuffering,
                isLoadingItem: manager.state == .loadingItem
            )
        }
        .modifier(VideoPlayer.KeyCommandsModifier())
        .animation(.linear(duration: 0.1), value: isScrubbing)
        .animation(.bouncy(duration: 0.4), value: containerState.isPresentingSupplement)
        .animation(.bouncy(duration: 0.25), value: isPresentingOverlay)
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

    /// Hauteur de la rangée de boutons et de la barre de progression : le bouton « Passer »
    /// se pose au-dessus quand les commandes sont affichées.
    private static let skipButtonOverlayOffset: CGFloat = 90
    /// Rien en chargement, tant que le proxy n'existe pas encore.
    private static let notBuffering = PublishedBox(initialValue: false)

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

            Text(SweetFinPlayer.title(of: manager.item))
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
        HStack(spacing: 8) {
            transportButtons

            Spacer()

            EpisodesButton()

            if let playbackItem = manager.playbackItem {
                SettingsMenu(playbackItem: playbackItem)
            }
        }
        .labelStyle(.iconOnly)
        // Symboles pleins : ❌ contours (`backward`, `play`…), ils sonnent faux.
        .font(.body)
        .foregroundStyle(.white)
        .buttonStyle(PlayerRowButtonStyle())
        .edgePadding(.horizontal)
        .background {
            EmptyHitTestView()
        }
    }

    /// Précédent · recul · lecture · avance · suivant, sur le modèle du web Jellyfin : petites
    /// icônes fines, la pause seule marquée. ❌ `.body` partout et pause en `.title` : icônes
    /// massives, ⏪ ⏩ deux fois plus larges que sur le web.
    private var transportButtons: some View {
        HStack(spacing: 6) {
            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .previous)
            }

            JumpButton(direction: .backward)

            // Le repère de la rangée, et un carré plus large : plus d'air autour, comme le web.
            PlayPauseButton()
                .font(.system(size: 24))
                .frame(width: 60)

            JumpButton(direction: .forward)

            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .next)
            }
        }
        .font(.system(size: 14))
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
}

/// Zone de tap de 44 × 44 pt (minimum d'Apple) autour d'une icône de la rangée, sans
/// changer son dessin. ❌ `.plain` seul : la zone = l'icône (~14 pt), un tap à côté passait au
/// geste du conteneur (double tap ±15 s) — d'où les flèches « qui ne marchent pas toujours ».
private struct PlayerRowButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
