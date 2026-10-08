//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Notifications.Key {

    /// SweetFin : un item vient d'être masqué de « Continuer de regarder ».
    ///
    /// Pas `didDeleteItem` : il retirerait l'item de **tous** les rails chargés.
    ///
    /// - Payload: la clé EnhancedFin masquée.
    static var didHideContinueWatchingItem: Key<String> {
        Key("didHideContinueWatchingItem")
    }
}

/// SweetFin : « Continuer de regarder ».
///
/// Trois écarts avec un `PosterGroup` d'upstream, d'où un groupe à part :
/// - **un tap lance la lecture** (`Router.play`) au lieu d'ouvrir la fiche : c'est une
///   liste de choses en cours. Une reprise hors médiathèque passe par `playable` ;
///   rien de lisible, le lecteur l'indique ;
/// - **toujours affiché**, même vide : un `PosterGroup` vide s'efface de l'Accueil
///   (`_shouldBeResolved`), et sur un compte neuf on croyait la section perdue. Des
///   emplacements vides tiennent sa place ;
/// - **rechargé** dès qu'un item est masqué : un autre vient combler le rail.
struct ContinueWatchingContentGroup: ContentGroup {

    /// Le nombre d'emplacements vides : une largeur d'écran de tuiles paysage
    /// `.small` sur iPhone, comme les colonnes de `PosterHStack`.
    private static let emptySlotCount = 2

    let id: String = "home-continue-watching"

    let viewModel = PagingLibraryViewModel(library: ContinueWatchingLibrary(), pageSize: 20)

    @ViewBuilder
    func body(with viewModel: PagingLibraryViewModel<ContinueWatchingLibrary>) -> some View {
        _Body(viewModel: viewModel)
            .onReceive(Notifications[.didHideContinueWatchingItem].publisher) { _ in
                viewModel.refresh()
            }
    }

    /// Une vue à part pour observer le view model : sans `@ObservedObject`, le passage
    /// de « vide » à « rempli » ne redessinerait rien.
    private struct _Body: View {

        @Router
        private var router

        @ObservedObject
        var viewModel: PagingLibraryViewModel<ContinueWatchingLibrary>

        var body: some View {
            ContentGroupSection {
                if viewModel.elements.isNotEmpty {
                    rail
                } else {
                    emptySlots
                }
            } header: {
                // Titre non cliquable, comme toutes les sections de l'Accueil.
                Text(HomeStrings.continueWatching)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        private var rail: some View {
            PosterHStack(
                elements: viewModel.elements.elements,
                // `.small` : deux tuiles par écran. `.medium` en donnait 1,5, énormes
                // pour une liste qu'on parcourt.
                displayType: .landscape,
                size: .small
            ) { item, _ in
                router.play(item)
            }
            // `isInResume` : barre de progression et libellé « S1E4 » sur les tuiles.
            // `isInContinueWatching` : le menu d'appui long de ce rail.
            .withViewContext([.isInResume, .isInContinueWatching])
        }

        private var emptySlots: some View {
            HStack(spacing: PosterHStackMetrics.itemSpacing) {
                ForEach(0 ..< ContinueWatchingContentGroup.emptySlotCount, id: \.self) { _ in
                    Color.secondarySystemFill
                        .posterStyle(.landscape)
                }
            }
            .edgePadding(.horizontal)
        }
    }
}
