//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

/// EnhancedFin : « Ajoutés récemment » de l'Accueil, films et séries confondus.
///
/// Les 20 derniers ajouts, limités aux `recentlyAddedDays` derniers jours.
///
/// L'API `/Items` ne filtre pas sur la date d'ajout (`DateLastSaved` bouge à chaque
/// rafraîchissement de métadonnées) : on demande les 20 plus récents et on écarte les
/// trop anciens. Une librairie à part plutôt qu'un `ItemLibrary`, qui pagine sans point
/// d'accroche pour ça.
struct HomeRecentlyAddedLibrary: BaseItemKindLibrary {

    /// Choix proposés dans les réglages, en jours.
    static let dayOptions = [7, 14, 30, 60, 90]

    private static let itemLimit = 20

    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent = .init(
        displayTitle: HomeStrings.recentlyAdded,
        id: "home-recently-added"
    )

    /// Une liste plafonnée ne se pagine pas : le titre de section n'ouvre rien, et
    /// le rail n'affiche que la première page.
    let hasNextPage = false

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = [.dateCreated]
        parameters.includeItemTypes = libraryItemTypes
        parameters.isRecursive = true
        parameters.limit = Self.itemLimit
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let items = try await pageState.userSession.client.send(request).value.items ?? []

        let days = Defaults[.Customization.Home.recentlyAddedDays]
        let cutoff = Date.now.addingTimeInterval(-TimeInterval(days) * 86400)

        return items.filter { ($0.dateCreated ?? .distantPast) >= cutoff }
    }
}
