//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

extension BaseItemDto {

    /// Clé EnhancedFin de cet item, au format `'{movie|tv}:{tmdb_id}'`.
    ///
    /// Deux origines :
    /// - un item **synthétique** de l'Explorer porte déjà la clé dans son identifiant ;
    /// - un item **du serveur** la reconstitue depuis son `ProviderId` TMDB.
    ///
    /// Vaut `nil` quand le rapprochement est impossible : pas d'identifiant TMDB, ou
    /// type sans équivalent côté référentiel (épisode, saison, personne, musique).
    /// Les actions EnhancedFin sont alors simplement indisponibles — c'est ce qui
    /// évite de proposer « noter » sur un épisode isolé, que le référentiel ne sait
    /// pas représenter.
    var enhancedFinMediaKey: String? {
        // Une personne synthétique n'a pas de clé : sans ça, noter, watchlist et suivre
        // apparaîtraient sur la fiche d'un acteur (voir `mediaKey(from:)`).
        if EnhancedFinSyntheticItem.isSynthetic(id) {
            return EnhancedFinSyntheticItem.mediaKey(from: id)
        }

        guard let tmdbID = providerIDs?["Tmdb"], Int(tmdbID) != nil else { return nil }

        return switch type {
        case .movie: "movie:\(tmdbID)"
        case .series: "tv:\(tmdbID)"
        default: nil
        }
    }

    /// Clés EnhancedFin d'items du serveur, en une seule requête qui demande leurs
    /// `ProviderIds` : les requêtes de liste (médiathèques, reprise…) ne les demandent
    /// pas, et les y ajouter toucherait du code upstream pour des clés rarement utiles.
    ///
    /// Parametres :
    /// - ids ([String]) : items Jellyfin (films ou séries)
    /// - userSession (UserSession) : la session en cours
    ///
    /// Output :
    /// - keys ([String: String]) : identifiant Jellyfin → clé ; un item sans
    ///   identifiant TMDB, ou une requête en échec, n'y figure pas
    static func enhancedFinMediaKeys(of ids: [String], userSession: UserSession) async -> [String: String] {
        guard ids.isNotEmpty else { return [:] }

        var parameters = Paths.GetItemsParameters()
        parameters.ids = ids
        parameters.fields = [.providerIDs]
        parameters.enableTotalRecordCount = false

        let items = (try? await userSession.client.send(Paths.getItems(parameters: parameters)).value.items) ?? []

        return items.reduce(into: [:]) { keys, item in
            guard let id = item.id, let key = item.enhancedFinMediaKey else { return }
            keys[id] = key
        }
    }
}
