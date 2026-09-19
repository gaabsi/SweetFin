//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: have see more at bottom trailing of view frame, instead of text width

struct SeeMoreText: View {

    @State
    private var fullTextSize: CGSize = .zero
    @State
    private var layoutTextSize: CGSize = .zero

    private let isTruncatedBinding: Binding<Bool>
    private let text: Text

    private var isTruncated: Bool {
        fullTextSize.height > layoutTextSize.height
    }

    init(
        _ text: String,
        isTruncated: Binding<Bool> = .constant(true)
    ) {
        self.text = Text(text)
        self.isTruncatedBinding = isTruncated
    }

    init(
        _ text: Text,
        isTruncated: Binding<Bool> = .constant(true)
    ) {
        self.text = text
        self.isTruncatedBinding = isTruncated
    }

    /// Un chevron plutôt que le mot « voir plus » : l'icône tient dans un coin de
    /// texte sans en manger trois mots, et se lit sans être traduite.
    ///
    /// Le libellé reste porté par l'accessibilité — un chevron seul ne dit rien à
    /// VoiceOver.
    @ViewBuilder
    private var seeMoreText: some View {
        Image(systemName: "chevron.down")
            .font(.caption)
            .fontWeight(.semibold)
            .accessibilityLabel(L10n.seeMore)
    }

    var body: some View {
        text
            .trackingSize($layoutTextSize)
            .inverseMask(alignment: .bottomTrailing) {
                seeMoreText
                    .padding(.leading, 20)
                    .background {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .black, location: 0.75),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 20)

                            Rectangle()
                                .fill(Color.black)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .isVisible(isTruncated)
            }
            .overlay(alignment: .bottomTrailing) {
                if isTruncated {
                    seeMoreText
                }
            }
            .background(alignment: .top) {
                text
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .trackingSize($fullTextSize)
                    .hidden()
            }
            .onChange(of: isTruncated) {
                isTruncatedBinding.wrappedValue = isTruncated
            }
    }
}
