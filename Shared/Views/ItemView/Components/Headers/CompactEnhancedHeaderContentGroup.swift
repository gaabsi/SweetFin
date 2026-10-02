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

extension ItemView {

    struct CompactEnhancedHeaderContentGroup: ContentGroup {

        let id: String = ItemView.Component.header
        let provider: ItemContentGroupProvider

        func body(with viewModel: Empty) -> Body {
            Body(provider: provider)
        }

        struct Body: View {

            @ObservedObject
            var provider: ItemContentGroupProvider

            private let headerAspectRatio = 1.6

            // SweetFin : cet en-tête sert aussi sur iPad (`ItemView.isCompact`), où
            // 70 pt donnaient un logo minuscule sous un fond pleine largeur.
            @Environment(\.horizontalSizeClass)
            private var horizontalSizeClass

            private var logoHeight: CGFloat {
                horizontalSizeClass == .regular ? 140 : 70
            }

            @ViewBuilder
            private var logo: some View {
                ImageView(
                    provider.item.imageSource(
                        .logo,
                        environment: ImageSourceOptions(maxHeight: logoHeight)
                    )
                )
                .placeholder { _ in
                    EmptyView()
                }
                .failure {
                    Text(provider.item.displayTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                .aspectRatio(contentMode: .fit)
                .frame(height: logoHeight, alignment: .bottom)
                .accessibilityLabel(provider.item.displayTitle)
                .accessibilityRemoveTraits(.isImage)
            }

            @ViewBuilder
            private var overlay: some View {
                VStack(alignment: .center, spacing: 10) {
                    AlternateLayoutView(alignment: .bottom) {
                        Color.clear
                            .aspectRatio(headerAspectRatio, contentMode: .fit)
                    } content: {
                        logo
                    }
                    .zIndex(10)

                    VStack(alignment: .center, spacing: 10) {
                        MetadataHStack(item: provider.item)

                        ItemView.ActionBar(provider: provider)
                            .frame(maxWidth: 300)

                        ItemView.Description(item: provider.item)
                    }
                    .edgePadding(.bottom)
                    .zIndex(9)
                }
            }

            var body: some View {
                overlay
                    .edgePadding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .colorScheme(.dark)
                    .backgroundParallaxHeader(multiplier: 0.3) {
                        // SweetFin : le backdrop s'efface vers le bas sur le fond de la page
                        // (flouté, voir `pageBackground`), au lieu d'un aplat de couleur
                        // extraite qui coupait la fiche à la fin du synopsis.
                        MirrorExtensionView(edges: .top) {
                            AlternateLayoutView {
                                Color.clear
                            } content: {
                                ImageView(provider.item.imageSource(
                                    .backdrop,
                                    environment: ImageSourceOptions(maxWidth: 1320)
                                ))
                                .aspectRatio(contentMode: .fill)
                            }
                            .aspectRatio(headerAspectRatio, contentMode: .fit)
                            .mask(gradient: .eased(.easeOut)) {
                                (location: 0.5, opacity: 1)
                                (location: 1, opacity: 0)
                            }
                            .accessibilityHidden(true)
                        }
                    }
            }
        }
    }
}
