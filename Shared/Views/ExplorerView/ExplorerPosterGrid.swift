//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Grille d'affiches EnhancedFin qui se réagence selon la largeur disponible.
///
/// Disposition reprise du `vertical-wrap` du front web, et partagée par toutes les
/// listes du fork : sections de l'Explorer, résultats de recherche, filmographie,
/// drill-down d'une catégorie de watchlist, « toutes mes notes ». Elles étaient
/// écrites à l'identique à plusieurs endroits.
///
/// ⚠️ `LazyVGrid` et non `CollectionVGrid` : cette dernière porte son propre
/// défilement, et deux zones scrollables imbriquées se disputent le geste. Même
/// raison que pour `PagingLibraryView`.
struct ExplorerPosterGrid<Item: EnhancedFinPosterItem>: View {

    @Router
    private var router

    /// Titre de l'écran. `nil` quand la grille est posée dans une section qui porte
    /// déjà son titre — elle n'est alors pas un écran à elle seule.
    var title: String? = nil

    let items: [Item]

    var body: some View {
        if let title {
            ScrollView {
                grid
                    .padding(.vertical)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            grid
        }
    }

    /// iPhone et iPad : autant de colonnes de 110 pt que la largeur en permet. tvOS :
    /// 6 colonnes, comme les rails d'affiches de l'Accueil.
    #if os(tvOS)
    private static var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 40), count: 6) }
    private static var spacing: CGFloat { 60 }
    #else
    private static var columns: [GridItem] { [GridItem(.adaptive(minimum: 110), spacing: 12)] }
    private static var spacing: CGFloat { 16 }
    #endif

    @ViewBuilder
    private var grid: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.spacing) {
            ForEach(items, id: \.mediaKey) { item in
                PosterButton(
                    item: item,
                    displayType: .portrait,
                    size: .small
                ) { namespace in
                    router.openEnhancedFin(item, in: namespace)
                }
                #if os(tvOS)
                // Sur tvOS, l'affiche n'a pas de taille propre (le libellé est à côté
                // d'elle dans le bouton, pas dessous) : format imposé.
                .aspectRatio(2 / 3, contentMode: .fit)
                #endif
            }
        }
        .edgePadding(.horizontal)
    }
}
