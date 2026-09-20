//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Ce qu'on affiche de la watchlist.
///
/// Les trois rayons viennent du front web (`_classify_wl_fav` / `_classify_wl_ext`) :
/// **un animé est une série d'animation**. Un film d'animation — Pixar, Disney —
/// reste dans « Films », parce que c'est ce que les gens entendent par « animé ».
///
/// ⚠️ C'est un **filtre**, pas la catégorie d'un média, et la distinction n'est pas
/// cosmétique : `all` ne désigne aucun rayon. Un enum de catégories auquel on
/// ajouterait un cas « tout » aurait une valeur qu'aucun média ne peut porter — d'où
/// `accepts(_:)`, qui juge un item plutôt que de prétendre le classer. Même patron
/// que `FilmographyGroup.TypeFilter`.
///
/// L'ordre des cas est celui d'``EnhancedFinTrendingFilter`` : les deux sélecteurs se
/// suivent à l'écran, et des ordres différents se paieraient à chaque coup d'œil.
///
/// Le tri se fait côté client : `/me/watchlist` renvoie `genreIds`, donc un seul appel
/// suffit et changer de rayon ne coûte aucune requête. Côté serveur il en faudrait
/// trois, « séries sauf animation » étant un *sauf* que `?genre=` ne sait pas exprimer.
enum WatchlistFilter: String, CaseIterable, Identifiable, Hashable {

    case all
    case movie
    case tv
    case anime

    /// Identifiant TMDB du genre « Animation ».
    private static let animationGenre = 16

    var id: String { rawValue }

    /// Retient-on cette entrée ?
    ///
    /// Parametres :
    /// - item (EnhancedFinWatchlistItem) : entrée de la watchlist
    ///
    /// Output :
    /// - keep (bool) : vrai si elle appartient au rayon affiché
    func accepts(_ item: EnhancedFinWatchlistItem) -> Bool {
        let isSeries = EnhancedFinMediaType(mediaKey: item.mediaKey) == .tv
        let isAnimated = item.genreIds?.contains(Self.animationGenre) == true

        return switch self {
        case .all: true
        case .movie: !isSeries
        // Une série sans genre connu reste une série : l'absence de genre ne doit pas
        // coûter sa place à un média.
        case .tv: isSeries && !isAnimated
        case .anime: isSeries && isAnimated
        }
    }
}
