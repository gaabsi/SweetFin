//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

enum PosterHStackMetrics {

    static let itemSpacing: CGFloat = {
        #if os(tvOS)
        40
        #else
        EdgeInsets.edgePadding / 2
        #endif
    }()
}

struct PosterHStack<
    Data: Collection
>: View where Data.Element: Poster, Data.Index == Int {

    let elements: Data
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size

    // SweetFin : défilement infini du rail de tendances. `CollectionHStack` sait
    // déjà signaler qu'on approche de la fin, `PosterHStack` ne le relayait pas.
    // Optionnel et nul par défaut : aucun appelant existant n'est touché.
    var onReachedTrailingEdge: (() -> Void)? = nil

    let action: (Data.Element, Namespace.ID) -> Void

    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(
            columns: displayType == .landscape ? 5 : 7,
            rows: 1,
            columnTrailingInset: 0
        )
        #else
        if UIDevice.isPad {
            let minWidth: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    220
                case (.landscape, .medium):
                    300
                case (_, .small):
                    140
//                case (_, .medium):
                default:
                    200
                }
            }()

            // SweetFin : réglé sur un 11", agrandi sur les plus grands iPad.
            return .minimumWidth(
                columnWidth: minWidth * UIDevice.padScale,
                rows: 1
            )
        } else {
            let columnCount: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    2
                case (.landscape, .medium):
                    1.5
                case (_, .small):
                    3
//                case (_, .medium):
                default:
                    2
                }
            }()

            return .grid(
                columns: columnCount,
                rows: 1,
                columnTrailingInset: 0
            )
        }
        #endif
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        EdgeInsets.edgePadding
        #endif
    }

    var body: some View {
        CollectionHStack(
            uniqueElements: elements,
            layout: layout
        ) { item in
            PosterButton(
                item: item,
                displayType: displayType,
                size: size
            ) { namespace in
                action(item, namespace)
            }
        }
        .clipsToBounds(false)
        .insets(horizontal: horizontalInset)
        .itemSpacing(PosterHStackMetrics.itemSpacing)
        .scrollBehavior(.continuousLeadingEdge)
        // SweetFin : 300 pt d'avance, la même marge que `PagingLibraryView`.
        .onReachedTrailingEdge(offset: .offset(300)) {
            onReachedTrailingEdge?()
        }
        .withViewContext(.isThumb)
    }
}
