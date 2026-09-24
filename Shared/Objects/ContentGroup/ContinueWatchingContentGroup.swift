//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Notifications.Key {

    /// EnhancedFin : un item vient d'être masqué de « Continuer de regarder ».
    ///
    /// Pas `didDeleteItem` : il retirerait l'item de **tous** les rails chargés.
    ///
    /// - Payload: la clé EnhancedFin masquée.
    static var didHideContinueWatchingItem: Key<String> {
        Key("didHideContinueWatchingItem")
    }
}

/// EnhancedFin : « Continuer de regarder », qui reste à l'écran même vide et se
/// recharge dès qu'un item est masqué.
///
/// Un `PosterGroup` vide s'efface de l'Accueil (`_shouldBeResolved`). Sur un compte
/// neuf, on croyait alors la section perdue. Quand elle est activée dans les réglages,
/// elle doit donc rester visible : des emplacements vides tiennent sa place.
///
/// Recharger après un masquage plutôt que retirer la tuile à la main : un autre item
/// vient combler le rail.
///
/// Enveloppe le `PosterGroup` plutôt que de le modifier : c'est un fichier upstream.
struct ContinueWatchingContentGroup: ContentGroup {

    /// Le nombre d'emplacements vides : une largeur d'écran de tuiles paysage
    /// `.small` sur iPhone, comme les colonnes de `PosterHStack`.
    private static let emptySlotCount = 2

    let id: String = "home-continue-watching"

    private let posterGroup = PosterGroup(
        library: ContinueWatchingLibrary(),
        posterDisplayType: .landscape,
        // `.medium` donne 1,5 tuile par écran — des vignettes énormes pour une
        // liste qu'on parcourt. `.small` en met deux, comme les autres rails.
        posterSize: .small,
        environment: .init(
            // Titres de l'Accueil non cliquables, voir `HomeContentGroupProvider`.
            isHeaderButtonEnabled: false,
            // `isInResume` : barre de progression et libellé « S1E4 » sur les tuiles.
            // `isInContinueWatching` : le menu d'appui long de ce rail.
            viewContext: [.isInResume, .isInContinueWatching]
        )
    )

    var viewModel: PagingLibraryViewModel<ContinueWatchingLibrary> {
        posterGroup.viewModel
    }

    @ViewBuilder
    func body(with viewModel: PagingLibraryViewModel<ContinueWatchingLibrary>) -> some View {
        _Body(viewModel: viewModel, posterGroup: posterGroup)
            .onReceive(Notifications[.didHideContinueWatchingItem].publisher) { _ in
                viewModel.refresh()
            }
    }

    /// Une vue à part pour observer le view model : sans `@ObservedObject`, le passage
    /// de « vide » à « rempli » ne redessinerait rien.
    private struct _Body: View {

        @ObservedObject
        var viewModel: PagingLibraryViewModel<ContinueWatchingLibrary>

        let posterGroup: PosterGroup<ContinueWatchingLibrary>

        var body: some View {
            if viewModel.elements.isNotEmpty {
                posterGroup.body(with: viewModel)
            } else {
                emptySlots
            }
        }

        private var emptySlots: some View {
            ContentGroupSection {
                HStack(spacing: PosterHStackMetrics.itemSpacing) {
                    ForEach(0 ..< ContinueWatchingContentGroup.emptySlotCount, id: \.self) { _ in
                        Color.secondarySystemFill
                            .posterStyle(.landscape)
                    }
                }
                .edgePadding(.horizontal)
            } header: {
                Text(HomeStrings.continueWatching)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}
