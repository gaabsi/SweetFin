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
/// Reprend les sections de l'onglet Explorer du front web : recherche, « à noter »,
/// watchlist, puis mes notes. Les tendances viendront quand le plugin exposera un
/// endpoint de découverte.
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
    /// `refresh()` fait déjà cette distinction, la recherche s'y aligne.
    @Published
    private(set) var searchError: Error?

    private var searchTask: Task<Void, Never>?

    /// Charge les trois sections en parallèle.
    ///
    /// Une section en échec ne doit pas vider les deux autres : chacune est isolée,
    /// et l'erreur n'est retenue que si tout échoue.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        guard let client = userSession?.enhancedFinClient else { return }

        async let pending = Self.attempt { try await client.pendingRatings().items }
        async let watchlist = Self.attempt { try await client.watchlist().items }
        async let ratings = Self.attempt { try await client.ratings().items }

        let (p, w, r) = await (pending, watchlist, ratings)

        self.pending = p.value ?? []
        self.watchlist = w.value ?? []
        self.ratings = r.value ?? []

        // Toutes en échec = le plugin ne répond pas (absent du serveur, ou en
        // erreur). Une seule en échec est un incident local qu'on ne remonte pas :
        // les deux autres sections restent utiles.
        error = (p.value == nil && w.value == nil && r.value == nil)
            ? p.error
            : nil

        if let error {
            logger.warning("EnhancedFin unreachable: \(error.localizedDescription)")
        }
    }

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
