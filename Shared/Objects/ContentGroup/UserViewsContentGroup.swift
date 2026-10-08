//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

/// « Mes médias » : les bibliothèques du serveur, en rail.
///
/// Rebranche ``UserViewLibrary``, resté **intact mais orphelin** depuis que l'onglet
/// Médias est devenu Explorer. Il gère déjà les exclusions `myMediaExcludes`, les
/// vignettes à image aléatoire et la navigation vers chaque bibliothèque :
/// il n'y avait rien à réécrire, seulement un appelant à lui rendre.
///
/// ⚠️ **``UserViewLibraryElement`` ne conforme pas à `Poster`**, donc ni `PosterGroup`
/// ni `PosterHStack` ne l'acceptent. On descend d'un cran, sur le `CollectionHStack`
/// que `PosterHStack` utilise lui-même — c'est lui qui porte le dimensionnement. Le
/// refaire à la main donnerait un rail écrasé aux vignettes rognées, déjà constaté sur
/// les rails de l'Explorer.
struct UserViewsContentGroup: ContentGroup {

    let id: String = "user-views"
    let viewModel: PagingLibraryViewModel<UserViewLibrary>

    init() {
        self.viewModel = .init(library: UserViewLibrary(), pageSize: 100)
    }

    /// Un serveur sans bibliothèque visible n'a pas de section. Le groupe disparaît
    /// alors, il ne laisse pas un titre au-dessus du vide.
    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    func body(with viewModel: PagingLibraryViewModel<UserViewLibrary>) -> some View {
        UserViewsRail(viewModel: viewModel)
    }
}

private struct UserViewsRail: View {

    @Router
    private var router

    @ObservedObject
    var viewModel: PagingLibraryViewModel<UserViewLibrary>

    /// Les vignettes de bibliothèque sont en paysage, **de la même taille que Continuer de
    /// regarder** : deux par écran sur iPhone, 220 pt minimum sur iPad (agrandis sur les
    /// grands iPad, `UIDevice.padScale`), comme les petits rails paysage de `PosterHStack`.
    /// Mêmes colonnes, donc bords alignés d'un rail à l'autre (choix du 2026-10-08).
    /// ❌ 180 pt (plus petites que la reprise) : sur un 13", 4 colonnes au-dessus de 3,
    /// décalées. ❌ Deux par écran sur iPad : plus grandes que les tuiles du dessous.
    ///
    /// tvOS : 5 par écran, la grille des rails paysage de `PosterHStack` là-bas.
    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(columns: 5, rows: 1, columnTrailingInset: 0)
        #else
        UIDevice.isPad
            ? .minimumWidth(columnWidth: 220 * UIDevice.padScale, rows: 1)
            : .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        #endif
    }

    /// Les bibliothèques réelles du serveur.
    private var libraries: [UserViewLibraryElement] {
        viewModel.elements.elements
    }

    var body: some View {
        ContentGroupSection {
            CollectionHStack(
                uniqueElements: libraries,
                layout: layout
            ) { element in
                UserViewsRailCell(element: element)
            }
            .clipsToBounds(false)
            .insets(horizontal: EdgeInsets.edgePadding)
            .itemSpacing(PosterHStackMetrics.itemSpacing)
            .scrollBehavior(.continuousLeadingEdge)
        } header: {
            // Pas de chevron : il n'y a pas d'écran « toutes les bibliothèques » à
            // ouvrir, chaque vignette mène déjà à la sienne. Un chevron inerte
            // promettrait une suite qui n'existe pas.
            Text(HomeStrings.myMedia)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .edgePadding(.horizontal)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HomeStrings.myMedia)
    }
}

/// Une vignette du rail.
///
/// `makeBody(libraryStyle:action:)` construit la vue — la vignette elle-même est
/// `private` dans `UserViewLibrary.swift`, et c'est ce point d'entrée qui la rend
/// accessible.
private struct UserViewsRailCell: View {

    let element: UserViewLibraryElement

    var body: some View {
        element.makeBody(
            libraryStyle: .init(
                displayType: .grid,
                posterDisplayType: .landscape,
                listColumnCount: 1
            ),
            action: nil
        )
    }
}
