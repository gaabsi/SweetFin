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
/// libellés qui n'existent que dans ce fork vivent donc ici, traduits (anglais, français)
/// dans `Translations/SweetFin.xcstrings`, la clé étant le texte anglais.
enum ExplorerStrings {

    static let explore = String(localized: "Explore", table: "SweetFin")
    static let toRate = String(localized: "To Rate", table: "SweetFin")
    /// Titre de la section de l'Explorer.
    static let watchlistSection = String(localized: "My Watchlist", table: "SweetFin")

    /// Libellé du bouton de la barre d'actions. Distinct du titre de section :
    /// « Ma watchlist » se lit comme un lieu, pas comme une action à déclencher.
    static let watchlistButton = String(localized: "Watchlist", table: "SweetFin")
    static let myRatings = String(localized: "My Ratings", table: "SweetFin")

    static let emptyTitle = String(localized: "Nothing to Explore", table: "SweetFin")
    static let emptyMessage = String(localized: "Rate a title or add it to your watchlist to see it here.", table: "SweetFin")

    static let unavailableTitle = String(localized: "EnhancedFin Unavailable", table: "SweetFin")
    static let unavailableMessage = String(localized: "The EnhancedFin plugin did not respond. Check that it is installed on this server.", table: "SweetFin")

    static let rate = String(localized: "Rate", table: "SweetFin")
    static let disliked = String(localized: "Not for Me", table: "SweetFin")
    static let liked = String(localized: "Liked It", table: "SweetFin")
    static let loved = String(localized: "Loved It!", table: "SweetFin")

    static let addToWatchlist = String(localized: "Add to Watchlist", table: "SweetFin")
    static let removeFromWatchlist = String(localized: "Remove from Watchlist", table: "SweetFin")

    static let follow = String(localized: "Follow", table: "SweetFin")
    static let unfollow = String(localized: "Unfollow", table: "SweetFin")

    /// Pendant de `L10n.seeMore`, qui n'a pas d'équivalent inverse en amont.
    static let seeLess = String(localized: "See Less", table: "SweetFin")

    /// Catégories de la watchlist et filtres des tendances partagent leurs
    /// libellés avec la filmographie (`allTypes`, `moviesOnly`, `seriesOnly`) :
    /// ce sont les mêmes mots pour les mêmes choses. Seuls les animés s'y ajoutent.
    static let animesOnly = String(localized: "Anime", table: "SweetFin")

    static let trending = String(localized: "Trending", table: "SweetFin")

    /// Titre de l'écran ouvert depuis une tuile de catégorie.
    ///
    /// Parametres :
    /// - category (String) : libellé de la catégorie
    static func watchlistCategory(_ category: String) -> String {
        String(localized: "My Watchlist · \(category)", table: "SweetFin")
    }

    static let filmography = String(localized: "Filmography", table: "SweetFin")
    static let sortByPopularity = String(localized: "Popularity", table: "SweetFin")
    static let sortByDate = String(localized: "Date", table: "SweetFin")
    static let allTypes = String(localized: "All", table: "SweetFin")
    static let moviesOnly = String(localized: "Movies", table: "SweetFin")
    static let seriesOnly = String(localized: "Shows", table: "SweetFin")
}
