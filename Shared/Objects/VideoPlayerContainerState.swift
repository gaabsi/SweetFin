//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftUI

// TODO: turned into spaghetti to get out, clean up with a better state system
// TODO: verify timer states
// TODO: for tvOS, some kind of focus token system
//       - help with Menu
//       - may help with alternate overlays

@MainActor
class VideoPlayerContainerState: ObservableObject {

    @Published
    var isAspectFilled: Bool = false

    // TODO: rename isPresentingPlaybackButtons
    @Published
    var isPresentingPlaybackControls: Bool = false

    // TODO: replace with graph dependency package
    func setPlaybackControlsVisibility() {

        guard isPresentingOverlay else {
            isPresentingPlaybackControls = false
            return
        }

        if isPresentingOverlay && !isPresentingSupplement {
            isPresentingPlaybackControls = true
            return
        }

        if isCompact {
            if isPresentingSupplement {
                if !isPresentingPlaybackControls {
                    isPresentingPlaybackControls = true
                }
            } else {
                isPresentingPlaybackControls = false
            }
        } else {
            isPresentingPlaybackControls = false
        }
    }

    @Published
    var isCompact: Bool = false {
        didSet {
            setPlaybackControlsVisibility()
        }
    }

    @Published
    var isGuestSupplement: Bool = false

    // TODO: rename isPresentingPlaybackControls
    @Published
    var isPresentingOverlay: Bool = false {
        didSet {
            // SweetFin : rappeler l'overlay (tap, touche de la télécommande) ferme l'écran de pause.
            if isPresentingOverlay {
                isPresentingPauseScreen = false
            }
            setPlaybackControlsVisibility()
            presentationControllerShouldDismiss = isPresentingOverlay && !isPresentingSupplement

            if isPresentingOverlay, !isPresentingSupplement {
                timer.poke()
            }
        }
    }

    @Published
    private(set) var isPresentingSupplement: Bool = false {
        didSet {
            setPlaybackControlsVisibility()
            presentationControllerShouldDismiss = isPresentingOverlay && !isPresentingSupplement

            if isPresentingSupplement {
                timer.stop()
            } else {
                isGuestSupplement = false
                timer.poke()
            }
        }
    }

    @Published
    var isScrubbing: Bool = false {
        didSet {
            if isScrubbing {
                timer.stop()
            } else {
                timer.poke()
            }
        }
    }

    @Published
    var presentationControllerShouldDismiss: Bool = false

    @Published
    var selectedSupplement: (any MediaPlayerSupplement)? = nil {
        didSet {
            isPresentingSupplement = selectedSupplement != nil
        }
    }

    @Published
    var isProgressBarFocused: Bool = false

    /// SweetFin : l'écran de pause (`SweetFinPauseScreen`), présenté après un temps de pause.
    @Published
    var isPresentingPauseScreen: Bool = false

    /// SweetFin : « Passer l'intro » se cache pendant un scrub, sous l'écran de pause et
    /// sous un panneau (iPhone et tvOS).
    var isSkipSegmentShown: Bool {
        !isScrubbing && !isPresentingPauseScreen && !isPresentingSupplement
    }

    var originalPlaybackRate: Float?

    let centerOffsetBox: PublishedBox<CGFloat> = .init(initialValue: 0)
    let jumpProgressObserver: JumpProgressObserver = .init()
    let scrubbedSeconds: PublishedBox<Duration> = .init(initialValue: .zero)
    // SweetFin : 3 s partout (upstream : 10 s TV, 5 s iPhone ; 5 s jugé lent).
    let timer: PokeIntervalTimer = .init(defaultInterval: 3)
    let toastProxy: ToastProxy = .init()

    weak var containerView: VideoPlayer.UIVideoPlayerContainerViewController?
    weak var manager: MediaPlayerManager?

    #if os(iOS)
    var lastTapLocation: CGPoint?
    #endif

    #if os(tvOS)
    /// SweetFin : vrai pendant un segment passable (générique, résumé). Posé par
    /// `SkipSegmentButton`.
    @Published
    var hasSkippableSegment: Bool = false
    /// SweetFin : le clic de la télécommande demande à `SkipSegmentButton` de passer le
    /// segment. ❌ Une closure gardée ici retenait le bouton, et donc cet état (cycle).
    let skipSegmentRequest = PassthroughSubject<Void, Never>()

    /// SweetFin : étiquette affichée et barre masquée pendant un segment : le clic le
    /// passe. Sinon il rappelle la barre ou va au bouton qui a le focus.
    var isSkipSegmentClickable: Bool {
        hasSkippableSegment && isSkipSegmentShown && !isPresentingOverlay
    }

    @Published
    private(set) var presentedSupplementStyle: MediaPlayerSupplementPresentationStyle?

    @Published
    var isPresentingCloseConfirmation: Bool = false

    var scrubOriginSeconds: Duration?

    func commitScrub() {
        guard isScrubbing else { return }

        manager?.proxy?.setSeconds(scrubbedSeconds.value)
        manager?.setPlaybackRequestStatus(status: .playing)
        isScrubbing = false
        scrubOriginSeconds = nil
    }

    func cancelScrub() {
        guard isScrubbing else { return }

        if let manager {
            scrubbedSeconds.value = manager.seconds
        }

        isScrubbing = false
        scrubOriginSeconds = nil
    }

    func setPresentedSupplementStyle(_ style: MediaPlayerSupplementPresentationStyle?) {
        presentedSupplementStyle = style
    }
    #endif

    private var jumpProgressCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?

    init() {
        timerCancellable = timer.sink { [weak self] in
            guard let self else { return }

            if containerView?.presentedViewController != nil {
                timer.poke()
                return
            }

            guard !isScrubbing,
                  !isPresentingSupplement,
                  manager?.playbackRequestStatus != .paused else { return }

            withAnimation(.linear(duration: 0.25)) {
                self.isPresentingOverlay = false
            }
        }

        #if os(iOS)
        jumpProgressCancellable = jumpProgressObserver
            .timer
            .sink { [weak self] in
                self?.lastTapLocation = nil
            }
        #endif
    }

    func select(supplement: (any MediaPlayerSupplement)?, isGuest: Bool = false) {
        isGuestSupplement = isGuest

        if supplement?.id == selectedSupplement?.id {
            selectedSupplement = nil
            containerView?.presentSupplementContainer(false)
        } else {
            selectedSupplement = supplement
            containerView?.presentSupplementContainer(
                supplement != nil,
                presentationStyle: isGuest ? supplement?.presentationStyle : nil
            )
        }
    }
}
