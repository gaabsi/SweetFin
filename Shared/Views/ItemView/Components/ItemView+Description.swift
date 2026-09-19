//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {

    struct Description: View {

        /// Le synopsis se déplie **sur place** au lieu d'ouvrir une page dédiée :
        /// lire trois lignes de plus ne justifie pas de quitter la fiche, ni le
        /// retour qu'il faut ensuite faire.
        @State
        private var isExpanded = false

        let item: BaseItemDto

        private var isPresented: Bool {
            item.taglines?.contains(where: \.isNotEmpty) == true ||
                item.overview?.isNotEmpty == true
        }

        /// - Important: `SeeMoreText` est conservé dans les deux états, avec pour
        ///   seule variation son `lineLimit`. Le remplacer par une autre vue au
        ///   dépliage lui donnerait une nouvelle identité : ses mesures internes
        ///   repartiraient de zéro, et la hauteur sauterait le temps d'une image
        ///   avant de se stabiliser.
        ///
        ///   Déplié, il n'y a plus rien à tronquer : `SeeMoreText` retire son propre
        ///   chevron de lui-même, et celui du repli prend sa place en dessous.
        @ViewBuilder
        private func overview(_ text: String) -> some View {
            Button {
                // Sans animation, à dessein. Le synopsis est à l'intérieur de
                // l'en-tête, dont l'image est posée en parallaxe sur un ratio fixe :
                // animer la hauteur fait recalculer ce décalage à chaque image, et
                // le fond oscille. Un seul recalcul vaut mieux qu'une oscillation.
                isExpanded.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    SeeMoreText(text)
                        .font(.footnote)
                        .lineLimit(isExpanded ? nil : 3)

                    if isExpanded {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel(ExplorerStrings.seeLess)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        var body: some View {
            if isPresented {
                VStack(alignment: .leading, spacing: 5) {
                    if let firstTagline = item.taglines?.first(where: \.isNotEmpty) {
                        Text(firstTagline)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    if let itemOverview = item.overview, itemOverview.isNotEmpty {
                        InlinePlatformView {
                            overview(itemOverview)
                        } tvOSView: {
                            Text(itemOverview)
                                .font(.footnote)
                                .lineLimit(3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
