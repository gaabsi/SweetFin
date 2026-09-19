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
        if let id, id.hasPrefix(EnhancedFinSyntheticItem.idPrefix) {
            return String(id.dropFirst(EnhancedFinSyntheticItem.idPrefix.count))
        }

        guard let tmdbID = providerIDs?["Tmdb"], Int(tmdbID) != nil else { return nil }

        return switch type {
        case .movie: "movie:\(tmdbID)"
        case .series: "tv:\(tmdbID)"
        default: nil
        }
    }
}
