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
/// Une librairie à part plutôt qu'un `ItemLibrary` : le rail est plafonné par le
/// réglage, et `ItemLibrary` pagine par 20 sans point d'accroche pour ça.
struct HomeRecentlyAddedLibrary: BaseItemKindLibrary {

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
        parameters.includeItemTypes = libraryItemTypes
        parameters.isRecursive = true
        parameters.limit = Defaults[.Customization.Home.recentlyAddedLimit]
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)

        return try await pageState.userSession.client.send(request).value.items ?? []
    }
}
