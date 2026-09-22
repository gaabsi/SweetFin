//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres à l'Explorer.
///
/// Volontairement hors de `L10n` : celui-ci est généré par SwiftGen depuis les
/// fichiers de traduction upstream, qu'il faudrait modifier dans les vingt langues
/// — et qui entreraient en conflit à chaque rebase sur `upstream/main`. Les
/// libellés qui n'existent que dans ce fork vivent donc ici.
enum ExplorerStrings {

    static let explore = "Explorer"
    static let toRate = "À noter"
    /// Titre de la section de l'Explorer.
    static let watchlistSection = "Ma watchlist"

    /// Libellé du bouton de la barre d'actions. Distinct du titre de section :
    /// « Ma watchlist » se lit comme un lieu, pas comme une action à déclencher.
    static let watchlistButton = "Watchlist"
    static let myRatings = "Mes notes"

    static let emptyTitle = "Rien à explorer"
    static let emptyMessage = "Note un média ou ajoute-le à ta watchlist pour le voir apparaître ici."

    static let unavailableTitle = "EnhancedFin indisponible"
    static let unavailableMessage = "Le plugin EnhancedFin n'a pas répondu. Vérifie qu'il est installé sur ce serveur."

    static let rate = "Noter"
    static let disliked = "Pas pour moi"
    static let liked = "J'aime bien"
    static let loved = "J'adore !"

    static let addToWatchlist = "Ajouter à ma watchlist"
    static let removeFromWatchlist = "Retirer de ma watchlist"

    static let follow = "Suivre"
    static let unfollow = "Ne plus suivre"

    /// Pendant de `L10n.seeMore`, qui n'a pas d'équivalent inverse en amont.
    static let seeLess = "Voir moins"

    /// Catégories de la watchlist et filtres des tendances partagent leurs
    /// libellés avec la filmographie (`allTypes`, `moviesOnly`, `seriesOnly`) :
    /// ce sont les mêmes mots pour les mêmes choses. Seuls les animés s'y ajoutent.
    static let animesOnly = "Animés"

    static let trending = "Tendances"

    /// Tuile d'une catégorie de watchlist sans aucun média.
    static let categoryEmpty = "Vide"

    /// Titre de l'écran ouvert depuis une tuile de catégorie.
    ///
    /// Parametres :
    /// - category (String) : libellé de la catégorie
    static func watchlistCategory(_ category: String) -> String {
        "Ma watchlist · \(category)"
    }

    static let filmography = "Filmographie"
    static let sortByPopularity = "Popularité"
    static let sortByDate = "Date"
    static let allTypes = "Tout"
    static let moviesOnly = "Films"
    static let seriesOnly = "Séries"
}
