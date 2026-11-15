//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer {

    struct PlaybackControls: View {

        @Default(.VideoPlayer.jumpBackwardInterval)
        var jumpBackwardInterval
        @Default(.VideoPlayer.jumpForwardInterval)
        var jumpForwardInterval

        @EnvironmentObject
        var containerState: VideoPlayerContainerState
        @EnvironmentObject
        var manager: MediaPlayerManager

        @Toaster
        var toaster: ToastProxy

        @FocusState
        private var isPlaybackProgressFocused: Bool
        /// SweetFin : le focus arrive sur Lecture/Pause quand la barre s'affiche.
        @FocusState
        var isPlayButtonFocused: Bool

        @State
        var speedBoostTimer: Timer?
        @State
        var isSpeedBoosting: Bool = false
        @State
        var pendingJumpWork: DispatchWorkItem?

        /// Rien en chargement, tant que le proxy n'existe pas encore.
        private static let notBuffering = PublishedBox(initialValue: false)

        var body: some View {
            // SweetFin : titre en haut, rangée de boutons, barre de progression (iso iPhone).
            VStack(spacing: 30) {

                titleBar
                    .isVisible(
                        containerState.isPresentingOverlay &&
                            !containerState.isScrubbing &&
                            !containerState.isPresentingSupplement
                    )

                Spacer()

                transportRow
                    .isVisible(
                        containerState.isPresentingOverlay &&
                            !containerState.isScrubbing &&
                            !containerState.isPresentingSupplement
                    )
                    // SweetFin : barre masquée, la rangée lâche le focus. ❌ Sinon ⏯, invisible,
                    // gardait le focus et prenait le clic du pavé : pause au lieu de passer
                    // l'intro (le clic doit arriver au conteneur, `handleSelectEnded`).
                    .disabled(containerState.isPresentingSupplement || !containerState.isPresentingOverlay)

                PlaybackProgress()
                    .focused($isPlaybackProgressFocused)
                    .fixedSize(horizontal: false, vertical: true)
                    .isVisible(
                        (containerState.isPresentingOverlay || containerState.isScrubbing) &&
                            !containerState.isPresentingSupplement
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .edgePadding(.horizontal)
            .focusSection()
            .defaultFocus($isPlayButtonFocused, true)
            // SweetFin : VLC qui charge (début, saut, coupure réseau), comme sur iPhone.
            .overlay {
                LoadingIndicator(
                    isBuffering: manager.proxy?.isBuffering ?? Self.notBuffering,
                    isLoadingItem: manager.state == .loadingItem
                )
            }
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingSupplement)
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingOverlay)
            .animation(.linear(duration: 0.1), value: containerState.isScrubbing)
            .alert(L10n.closePlayer, isPresented: $containerState.isPresentingCloseConfirmation) {
                Button(L10n.cancel, role: .cancel) {}

                Button(L10n.ok, role: .destructive) {
                    manager.stop()
                }
            } message: {
                Text(L10n.closePlayerWarning)
            }
            .onChange(of: containerState.isPresentingOverlay) {
                // Un tour plus tard : la rangée vient d'être réactivée, le focus ne s'y pose
                // pas dans la même mise à jour.
                if containerState.isPresentingOverlay {
                    DispatchQueue.main.async {
                        isPlayButtonFocused = true
                    }
                }
            }
            .onChange(of: manager.playbackRequestStatus) {
                if manager.playbackRequestStatus == .paused, !containerState.isPresentingOverlay {
                    containerState.isPresentingOverlay = true
                } else if manager.playbackRequestStatus == .playing {
                    // SweetFin : en pause, le minuteur renonce à masquer sans se relancer ;
                    // on le relance quand la lecture repart, sinon la barre reste affichée.
                    containerState.timer.poke()
                }
            }
            .onReceive(containerState.containerView?.onPressEvent ?? .init()) { press in
                handlePressEvent(press)
            }
            .onChange(of: containerState.isProgressBarFocused) {
                if !containerState.isProgressBarFocused {
                    containerState.cancelScrub()

                    if isSpeedBoosting {
                        stopSpeedBoost()
                    }
                }
            }
        }
    }
}
