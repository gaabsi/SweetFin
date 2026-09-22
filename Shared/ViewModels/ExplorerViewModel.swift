//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

/// Alimente l'onglet Explorer depuis le plugin EnhancedFin.
///
/// Reprend les sections de l'onglet Explorer du front web, dans son ordre :
/// recherche, « à noter », watchlist, tendances, mes notes.
@MainActor
final class ExplorerViewModel: ViewModel {

    @Published
    private(set) var pending: [EnhancedFinPendingRating] = []

    @Published
    private(set) var watchlist: [EnhancedFinWatchlistItem] = []

    @Published
    private(set) var ratings: [EnhancedFinRating] = []

    @Published
    private(set) var searchResults: [EnhancedFinSearchItem] = []

    @Published
    private(set) var isLoading = false

    /// Renseignée seulement si **toutes** les sections ont échoué — typiquement un
    /// serveur sur lequel le plugin EnhancedFin n'est pas installé.
    @Published
    private(set) var error: Error?

    @Published
    private(set) var isSearching = false

    /// Échec de la dernière recherche.
    ///
    /// Sans elle, une panne réseau se présentait comme « Aucun résultat » : le
    /// même écran pour « ce titre n'existe pas » et « le serveur n'a pas répondu ».
    @Published
    private(set) var searchError: Error?

    // MARK: - Tendances

    @Published
    private(set) var trendingFilter: EnhancedFinTrendingFilter = .all

    @Published
    private(set) var isLoadingTrending = false

    /// Ce qui est déjà chargé pour chaque filtre.
    ///
    /// Un état **par filtre** et non un seul remis à zéro : revenir sur « Tout »
    /// après un détour par « Animés » doit retrouver la liste et sa position, pas
    /// relancer un appel pour réafficher ce qu'on avait déjà.
    private struct TrendingFeed {

        var items: [EnhancedFinSearchItem] = []

        /// Clés déjà affichées.
        ///
        /// ⚠️ **Indispensable côté client.** Le serveur est sans état : son curseur
        /// désigne une page TMDB, et TMDB rejoue le même titre d'une page à l'autre
        /// quand son classement bouge (mesuré : ~14 % de répétitions sur « Tout »).
        /// Personne d'autre que nous ne peut écarter ces doublons.
        var seen: Set<String> = []

        /// Page à demander pour la suite. `nil` avec ``hasLoaded`` signifie « fini ».
        var cursor: Int?

        var hasLoaded = false
    }

    @Published
    private var feeds: [EnhancedFinTrendingFilter: TrendingFeed] = [:]

    /// Les tendances du filtre courant.
    var trending: [EnhancedFinSearchItem] {
        feeds[trendingFilter]?.items ?? []
    }

    /// Reste-t-il des pages à charger pour le filtre courant ?
    var canLoadMoreTrending: Bool {
        guard let feed = feeds[trendingFilter] else { return true }
        return feed.cursor != nil || !feed.hasLoaded
    }

    private var searchTask: Task<Void, Never>?

    /// Chargement de tendances en cours, mémorisé pour n'en garder **qu'un** en vol.
    ///
    /// Un booléen ne suffirait pas : le défilement déclenche plusieurs demandes
    /// avant la première suspension, elles franchiraient toutes le garde et
    /// empileraient les appels — le même piège que `load()` sur les boutons d'action.
    private var trendingTask: Task<Void, Never>?

    // MARK: - Chargement

    /// Charge les sections en parallèle.
    ///
    /// Une section en échec ne doit pas vider les autres : chacune est isolée, et
    /// l'erreur n'est retenue que si tout échoue.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        guard let client = userSession?.enhancedFinClient else { return }

        async let pending = Self.attempt { try await client.pendingRatings().items }
        async let watchlist = Self.attempt { try await client.watchlist().items }
        async let ratings = Self.attempt { try await client.ratings().items }
        async let trending = Self.attempt { try await client.trending(filter: .all) }

        let (p, w, r, t) = await (pending, watchlist, ratings, trending)

        self.pending = p.value ?? []
        self.watchlist = w.value ?? []
        self.ratings = r.value ?? []

        if let page = t.value {
            feeds[.all] = feed(.all, adding: page, to: TrendingFeed())
        }

        // Toutes en échec = le plugin ne répond pas (absent du serveur, ou en
        // erreur). Une seule en échec est un incident local qu'on ne remonte pas.
        error = (p.value == nil && w.value == nil && r.value == nil && t.value == nil)
            ? p.error
            : nil

        if let error {
            logger.warning("EnhancedFin unreachable: \(error.localizedDescription)")
        }
    }

    /// Bascule de filtre, en ne chargeant que ce qui manque.
    func selectTrendingFilter(_ filter: EnhancedFinTrendingFilter) {
        guard filter != trendingFilter else { return }

        trendingFilter = filter

        if feeds[filter]?.hasLoaded != true {
            loadMoreTrending()
        }
    }

    /// Charge la page suivante du filtre courant.
    ///
    /// Sans effet si le serveur a signalé la fin en ne rendant pas de curseur.
    ///
    /// ⚠️ **Un chargement déjà en vol ne fait pas abandonner la demande**, il la
    /// diffère. Abandonner laissait un filtre vide pour de bon : changer de filtre
    /// pendant le chargement d'une page ne planifiait rien, et un rail vide n'a rien
    /// à faire défiler pour redéclencher `onReachedTrailingEdge`.
    func loadMoreTrending() {
        guard trendingTask == nil else { return }

        let filter = trendingFilter
        let cursor = feeds[filter]?.cursor
        guard cursor != nil || feeds[filter]?.hasLoaded != true else { return }

        isLoadingTrending = true

        trendingTask = Task { [weak self] in
            guard let self else { return }

            defer {
                trendingTask = nil
                isLoadingTrending = false

                // Le filtre a changé pendant le vol : sa demande n'a pas été servie.
                if trendingFilter != filter, feeds[trendingFilter]?.hasLoaded != true {
                    loadMoreTrending()
                }
            }

            guard let client = userSession?.enhancedFinClient else { return }

            do {
                let page = try await client.trending(filter: filter, cursor: cursor)
                guard !Task.isCancelled else { return }

                // ⚠️ **Relire le flux ici**, et ne pas fusionner dans la copie prise
                // avant l'`await` : un `refresh()` a pu le vider entre-temps, et la
                // copie ressusciterait l'ancienne liste avec son ancien curseur.
                feeds[filter] = self.feed(filter, adding: page, to: feeds[filter] ?? TrendingFeed())
            } catch {
                logger.warning("EnhancedFin trending failed: \(error.localizedDescription)")
            }
        }
    }

    /// Ajoute une page à un flux, doublons écartés.
    ///
    /// Parametres :
    /// - filter (EnhancedFinTrendingFilter) : flux concerné
    /// - page (EnhancedFinTrendingPage) : page reçue
    /// - feed (TrendingFeed) : état courant du flux
    ///
    /// Output :
    /// - feed (TrendingFeed) : état enrichi de la page
    private func feed(
        _ filter: EnhancedFinTrendingFilter,
        adding page: EnhancedFinTrendingPage,
        to feed: TrendingFeed
    ) -> TrendingFeed {
        var feed = feed

        for item in page.items where feed.seen.insert(item.mediaKey).inserted {
            feed.items.append(item)
        }

        feed.cursor = page.nextCursor
        feed.hasLoaded = true

        return feed
    }

    // MARK: - Recherche

    /// Délai d'inactivité avant de lancer une recherche.
    ///
    /// ⚠️ **Ce n'est pas qu'une politesse réseau.** `/search` fusionne référentiel,
    /// TMDB et bibliothèque côté plugin : chaque frappe déclenchait un appel TMDB
    /// sortant depuis le serveur. « interstellar » en valait douze, dont onze jetés.
    private static let searchDebounce: Duration = .milliseconds(300)

    /// Lance une recherche, en annulant la précédente.
    ///
    /// Annuler est ce qui rend la frappe fluide : sans ça, chaque caractère laisse
    /// une requête en vol et les réponses arrivent dans le désordre.
    func search(_ query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isNotEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil

        searchTask = Task { [weak self] in
            // L'attente est **dans** la tâche, avant tout réseau : l'annulation déjà
            // en place au début de `search` suffit alors à jeter les frappes
            // intermédiaires, sans qu'aucune n'atteigne le serveur.
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }

            guard let self, let client = userSession?.enhancedFinClient else { return }

            do {
                let results = try await client.search(trimmed).items
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                logger.warning("EnhancedFin search failed: \(error.localizedDescription)")
                searchResults = []
                searchError = error
            }

            isSearching = false
        }
    }

    // MARK: - Watchlist

    /// Rayon affiché.
    ///
    /// ``WatchlistFilter/all`` par défaut, comme les tendances : à l'ouverture, voir
    /// ses derniers ajouts tous types confondus renseigne davantage qu'un rayon
    /// choisi arbitrairement.
    @Published
    private(set) var watchlistFilter: WatchlistFilter = .all

    /// Les entrées du rayon courant.
    ///
    /// Filtrées à la volée, sans regroupement conservé : la watchlist tient en
    /// mémoire et se compte en dizaines d'entrées. Contrairement aux tendances,
    /// changer de rayon ne déclenche donc **aucun appel**.
    var watchlistItems: [EnhancedFinWatchlistItem] {
        watchlist.filter(watchlistFilter.accepts)
    }

    func selectWatchlistFilter(_ filter: WatchlistFilter) {
        watchlistFilter = filter
    }

    // MARK: - Outils

    /// Résultat d'un chargement de section : la valeur, ou l'erreur rencontrée.
    ///
    /// On garde l'erreur au lieu d'un simple `nil` — sans elle, un écran vide ne
    /// permet pas de distinguer « rien à afficher » de « le plugin ne répond pas ».
    private struct Attempt<T> {
        let value: T?
        let error: Error?
    }

    private static func attempt<T>(_ body: () async throws -> T) async -> Attempt<T> {
        do {
            return Attempt(value: try await body(), error: nil)
        } catch {
            return Attempt(value: nil, error: error)
        }
    }
}
