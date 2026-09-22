//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// Un tirage aléatoire de films et de séries, pour alimenter la media bar.
///
/// Requête reprise du plugin Jellyfin **Media Bar** (`slideshowpure.js`), qui n'expose
/// aucune API de contenu : son carrousel interroge lui aussi `/Items`, côté navigateur.
/// On reprend donc sa recette, pas une de ses routes.
struct RandomItemsLibrary: BaseItemKindLibrary {

    /// Nombre de diapos.
    ///
    /// ⚠️ **On s'écarte ici du plugin, qui en charge 50.** Sur mobile, le carrousel
    /// affiche un point par diapo : au-delà d'une poignée, la rangée de points devient
    /// une frise illisible qui ne renseigne plus sur rien. Huit se comptent d'un coup
    /// d'œil, et le tirage étant renouvelé à chaque chargement, la variété ne vient pas
    /// de la longueur de la liste.
    static let itemLimit = 8

    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent = .init(displayTitle: HomeStrings.mediaBar, id: "media-bar")

    /// Un tirage aléatoire ne se pagine pas : la page 2 rejouerait les mêmes titres.
    let hasNextPage = false

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = pageState.userSession.user.id
        parameters.includeItemTypes = libraryItemTypes
        parameters.isRecursive = true
        parameters.sortBy = [.random]
        parameters.limit = Self.itemLimit

        // ⚠️ `imageTypes` est un FILTRE, pas une demande de champs : le serveur n'écarte
        // pas les images, il écarte les MÉDIAS qui n'ont pas à la fois un logo et une
        // image de fond. C'est ce qui dispense d'un repli « logo sinon titre » — une
        // diapo sans logo n'existe pas. Ne pas confondre avec `enableImageTypes`
        // ci-dessous, qui lui demande bien les champs.
        parameters.imageTypes = [.logo, .backdrop]
        parameters.enableImageTypes = [.backdrop, .logo, .primary]

        // Même intention : une fiche sans synopsis ne mérite pas la pleine largeur.
        parameters.hasOverview = true

        // Le carrousel est une invitation à découvrir. Ce qu'on a déjà vu n'y a pas sa
        // place — retirer cette ligne suffit à tirer dans tout le catalogue.
        parameters.isPlayed = false

        parameters.enableUserData = true
        parameters.fields = [.overview, .taglines, .genres]

        // Le total ne sert à rien ici et coûte un comptage au serveur.
        parameters.enableTotalRecordCount = false

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }
}
