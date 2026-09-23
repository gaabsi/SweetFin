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
/// Ordre des sections repris tel quel : recherche, « à noter », watchlist,
/// tendances, mes notes.
///
/// Dispositions alignées sur le web : grille qui se réagence pour « à noter » et les
/// résultats de recherche (`vertical-wrap`), rails horizontaux pour la watchlist,
/// les tendances et l'aperçu des notes (`jr-hscroll`).
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
        .hidesNavigationTitle()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.search
        )
        .onChange(of: searchText) { _, newValue in
            viewModel.search(newValue)
        }
        .refreshable {
            // ⚠️ Tâche détachée à dessein : SwiftUI annule celle de `.refreshable`
            // quand la vue se redessine pendant le geste — ce que fait `isLoading`.
            // Attendue directement, la requête mourait en « annulé » et le
            // rafraîchissement n'aboutissait jamais.
            await Task { await viewModel.refresh() }.value
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
            ExplorerPosterGrid(items: viewModel.searchResults)
        }
    }

    // MARK: - Sections

    /// ⚠️ **C'est ce `spacing` qui sépare les sections**, et rien d'autre : ni trait
    /// ni fond, l'app n'en utilise nulle part. Il ne tient que parce que les sections
    /// ont désormais toutes la même forme — en-tête · [sélecteur] · rail. Tant que
    /// l'une d'elles était une grille, aucun espacement n'aurait suffi à créer du
    /// rythme.
    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let error = viewModel.error {
                unavailable(error)
            } else if !viewModel.isLoading, isEmpty {
                ContentUnavailableView(
                    ExplorerStrings.emptyTitle,
                    systemImage: "sparkle.magnifyingglass",
                    description: Text(ExplorerStrings.emptyMessage)
                )
                .padding(.top, 60)
            }

            if viewModel.pending.isNotEmpty {
                pendingSection
            }

            if viewModel.watchlist.isNotEmpty {
                watchlistSection
            }

            trendingSection

            if viewModel.ratings.isNotEmpty {
                ratingsSection
            }
        }
    }

    // MARK: - À noter

    /// La seule section qui appelle une action, et la seule en tuiles `.medium`.
    ///
    /// Sa saillance passe par la **taille** et par le compteur, pas par une couleur
    /// ni un cadre : l'app n'a pas ce vocabulaire, et un accent de couleur sur une
    /// section parmi quatre se lirait comme une alerte.
    @ViewBuilder
    private var pendingSection: some View {
        ContentGroupSection {
            PosterHStack(
                elements: viewModel.pending,
                displayType: .portrait,
                size: .medium
            ) { item, namespace in
                router.openEnhancedFin(item, in: namespace)
            }
        } header: {
            ExplorerSectionHeader(
                title: ExplorerStrings.toRate,
                count: viewModel.pending.count
            ) {
                router.route(to: .explorerPending(items: viewModel.pending))
            }
        }
    }

    // MARK: - Watchlist

    /// Un sélecteur de rayon et un rail, plutôt que trois tuiles à ouvrir.
    ///
    /// Les tuiles « éventail » du front web ne se transposent pas ici : ramenées au
    /// tiers d'un écran mobile, leurs affiches tombaient à 34 pt — assez pour un
    /// ornement, pas pour reconnaître un titre. On payait donc **deux** taps pour
    /// atteindre un média, contre un seul ici.
    ///
    /// Mêmes quatre filtres que les tendances, dans le même ordre : les deux
    /// sélecteurs se suivent à l'écran et s'apprennent alors une seule fois. « Tout »
    /// par défaut y montre les derniers ajouts, tous types confondus ; la liste
    /// complète reste à un tap, par « Voir plus ».
    @ViewBuilder
    private var watchlistSection: some View {
        ContentGroupSection {
            VStack(alignment: .leading, spacing: 12) {
                ExplorerFilterPicker(
                    title: ExplorerStrings.watchlistSection,
                    selection: Binding(
                        get: { viewModel.watchlistFilter },
                        set: { viewModel.selectWatchlistFilter($0) }
                    )
                )

                PosterHStack(
                    elements: viewModel.watchlistItems,
                    displayType: .portrait,
                    size: .small
                ) { item, namespace in
                    router.openEnhancedFin(item, in: namespace)
                }
            }
        } header: {
            ExplorerSectionHeader(title: ExplorerStrings.watchlistSection) {
                router.route(
                    to: .explorerWatchlist(
                        filter: viewModel.watchlistFilter,
                        items: viewModel.watchlistItems
                    )
                )
            }
        }
    }

    // MARK: - Tendances

    /// La seule section qui a du contenu sur un compte neuf.
    ///
    /// Elle est donc affichée même quand tout le reste est vide — et `isEmpty` la
    /// prend en compte, sans quoi l'écran « Rien à explorer » se superposerait à un
    /// rail bien rempli.
    @ViewBuilder
    private var trendingSection: some View {
        if viewModel.trending.isNotEmpty || viewModel.isLoadingTrending {
            ContentGroupSection {
                VStack(alignment: .leading, spacing: 12) {
                    ExplorerFilterPicker(
                        title: ExplorerStrings.trending,
                        selection: trendingFilterBinding
                    )

                    trendingRail
                }
            } header: {
                ExplorerSectionHeader(title: ExplorerStrings.trending)
            }
        }
    }

    /// Le `Picker` écrit dans le modèle, qui décide s'il faut charger : un
    /// `@Published` en lecture seule ne peut pas être lié directement.
    private var trendingFilterBinding: Binding<EnhancedFinTrendingFilter> {
        Binding(
            get: { viewModel.trendingFilter },
            set: { viewModel.selectTrendingFilter($0) }
        )
    }

    /// Rail portrait, comme le `portraitCard` du web.
    ///
    /// ⚠️ `PosterHStack` et non un `LazyHStack` maison : c'est lui qui porte le
    /// dimensionnement des tuiles (colonnes, encarts, espacement). Le refaire à la
    /// main donnait un rail écrasé, aux affiches rognées.
    ///
    /// La suite se charge à l'approche du bord, via le signal que `CollectionHStack`
    /// émet déjà et que `PosterHStack` relaie désormais.
    @ViewBuilder
    private var trendingRail: some View {
        PosterHStack(
            elements: viewModel.trending,
            displayType: .portrait,
            size: .small,
            onReachedTrailingEdge: viewModel.loadMoreTrending
        ) { item, namespace in
            router.openEnhancedFin(item, in: namespace)
        }
    }

    // MARK: - Mes notes

    /// Repliée sur une rangée : la liste complète compte plusieurs centaines de
    /// titres et occuperait tout l'écran sous les autres sections.
    @ViewBuilder
    private var ratingsSection: some View {
        ContentGroupSection {
            PosterHStack(
                elements: viewModel.ratings,
                displayType: .portrait,
                size: .small
            ) { item, namespace in
                router.openEnhancedFin(item, in: namespace)
            }
        } header: {
            ExplorerSectionHeader(title: ExplorerStrings.myRatings) {
                router.route(to: .explorerRatings(items: viewModel.ratings))
            }
        }
    }

    // MARK: - États

    /// Aucune section n'a de contenu.
    ///
    /// Les tendances en font partie : elles ne dépendent pas du compte, donc si
    /// elles ont chargé, l'Explorer a quelque chose à montrer même à un profil neuf.
    private var isEmpty: Bool {
        viewModel.pending.isEmpty
            && viewModel.watchlist.isEmpty
            && viewModel.ratings.isEmpty
            && viewModel.trending.isEmpty
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
}
