//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// SweetFin : sélecteur de lettres imposé, toujours affiché sur le bord droit.
struct LetterPickerBarModifier: ViewModifier {

    let viewModel: FilterViewModel?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let viewModel {
            content
                .focusSection()
                .ignoresSafeArea(.all, edges: .leading)
                .safeAreaInset(edge: .trailing, alignment: .center, spacing: 0) {
                    LetterPickerBar(viewModel: viewModel)
                }
                .overlayPreferenceValue(LetterPickerActiveLetterKey.self) { letter in
                    ZStack {
                        if let letter {
                            LetterPickerBar.LetterPickerCallout(letter: letter)
                                .font(.system(size: UIDevice.isTV ? 128 : 64, design: .rounded).weight(.bold))
                        }
                    }
                }
        } else {
            content
                .ignoresSafeArea(.all, edges: .horizontal)
        }
    }
}
