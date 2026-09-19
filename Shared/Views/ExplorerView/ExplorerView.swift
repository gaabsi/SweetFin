//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Onglet Explorer — miroir natif de l'onglet Explorer du front web.
///
/// Ordre des sections repris tel quel : recherche, « à noter », watchlist, puis
/// mes notes. Les tendances viendront quand le plugin exposera un endpoint de
/// découverte.
///
/// Dispositions alignées sur le web : grille qui se réagence pour « à noter »,
/// « mes notes » et les résultats de recherche (`vertical-wrap`), rail horizontal
/// pour la watchlist (`jr-hscroll`).
///
/// Remplace entièrement l'ancien onglet « Médias ».
struct ExplorerView: View {

    @Router
    private var router

    @StateObject
    private var viewModel = ExplorerViewModel()

    @State
    private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if searchText.isNotEmpty {
                    searchResults
                } else {
                    sections
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(ExplorerStrings.explore)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.search
        )
        .onChange(of: searchText) { _, newValue in
            viewModel.search(newValue)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Recherche

    /// Pas de sélecteur films / séries : le serveur cherche les deux quand le type
    /// est omis, comme le fait la recherche du front web.
    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if let error = viewModel.searchError {
            // Un échec réseau n'est pas une absence de résultat : afficher
            // « Aucun résultat » ferait croire que le titre n'existe pas.
            unavailable(error)
        } else if viewModel.searchResults.isEmpty {
            Text(L10n.noResults)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            grid(viewModel.searchResults)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        if let error = viewModel.error {
            unavailable(error)
        } else if !viewModel.isLoading, isEmpty {
            ContentUnavailableView(
                ExplorerStrings.emptyTitle,
                systemImage: "safari",
                description: Text(ExplorerStrings.emptyMessage)
            )
            .padding(.top, 60)
        }

        if viewModel.pending.isNotEmpty {
            section(ExplorerStrings.toRate) {
                grid(viewModel.pending)
            }
        }

        if viewModel.watchlist.isNotEmpty {
            section(ExplorerStrings.watchlistSection) {
                PosterHStack(
                    elements: viewModel.watchlist,
                    displayType: .landscape,
                    size: .medium
                ) { item, namespace in
                    open(item, in: namespace)
                }
            }
        }

        // Tendances : en attente de l'endpoint de découverte côté plugin.

        if viewModel.ratings.isNotEmpty {
            section(ExplorerStrings.myRatings) {
                grid(viewModel.ratings)
            }
        }
    }

    // MARK: - Dispositions

    /// Grille qui se réagence selon la largeur disponible.
    ///
    /// `LazyVGrid` et non `CollectionVGrid` : cette dernière porte son propre
    /// défilement, et deux zones scrollables imbriquées se disputent le geste.
    @ViewBuilder
    private func grid(_ items: [some EnhancedFinPosterItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
            spacing: 16
        ) {
            ForEach(items, id: \.mediaKey) { item in
                PosterButton(
                    item: item,
                    displayType: .portrait,
                    size: .small
                ) { namespace in
                    open(item, in: namespace)
                }
            }
        }
        .edgePadding(.horizontal)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .edgePadding(.horizontal)

            content()
        }
        .padding(.bottom, 24)
    }

    // MARK: - États

    /// Aucune section n'a de contenu — soit le compte est neuf, soit rien n'est
    /// encore noté ni en watchlist.
    private var isEmpty: Bool {
        viewModel.pending.isEmpty && viewModel.watchlist.isEmpty && viewModel.ratings.isEmpty
    }

    /// Le plugin n'a pas répondu. Le cas le plus courant n'est pas une panne mais
    /// un serveur sur lequel EnhancedFin n'est pas installé — le dire évite de
    /// chercher un bug dans l'app.
    @ViewBuilder
    private func unavailable(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(ExplorerStrings.unavailableTitle, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 8) {
                Text(ExplorerStrings.unavailableMessage)
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Navigation

    /// Ouvre une fiche, sur le serveur ou non.
    ///
    /// Média en bibliothèque : la fiche native, avec lecture et épisodes. Sinon la
    /// même vue, nourrie par TMDB, bouton Lire grisé.
    private func open(_ item: some EnhancedFinLibraryLinkable, in namespace: Namespace.ID) {
        if let jellyfinItem = item.jellyfinItem {
            router.route(to: .item(item: jellyfinItem), in: namespace)
        } else {
            router.route(
                to: .explorerItem(mediaKey: item.mediaKey, item: item.syntheticItem),
                in: namespace
            )
        }
    }
}
