//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UIKit

extension VideoPlayer.UIVideoPlayerContainerViewController {

    /// EnhancedFin : le glisser ne sert qu'à ouvrir / fermer le panneau des épisodes.
    /// Luminosité, volume, scrub et balayages sont coupés.
    func handlePanGesture(
        translation: CGPoint,
        velocity: CGPoint,
        location: CGPoint,
        unitPoint: UnitPoint,
        state: UIGestureRecognizer.State
    ) {
        guard checkGestureLock() else { return }

        if state == .began {
            containerState.timer.stop()
        }

        if state == .ended || state == .cancelled || state == .failed {
            containerState.timer.poke()
        }

        handleSupplementPanAction(
            translation: translation,
            velocity: velocity.y,
            location: location,
            state: state
        )
    }
}
