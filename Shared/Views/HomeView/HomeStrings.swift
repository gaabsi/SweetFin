//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres à l'Accueil du fork.
///
/// Hors de `L10n`, pour la même raison qu'`ExplorerStrings` et `CalendarStrings` :
/// celui-ci est généré par SwiftGen depuis les fichiers de traduction upstream, qu'il
/// faudrait modifier dans les vingt langues — et qui entreraient en conflit à chaque
/// rebase. Les traductions (anglais, français) vivent dans `Translations/SweetFin.xcstrings`,
/// la clé étant le texte anglais.
enum HomeStrings {

    static let myMedia = String(localized: "My Media", table: "SweetFin")
    static let continueWatching = String(localized: "Continue Watching", table: "SweetFin")
    static let recentlyAdded = String(localized: "Recently Added", table: "SweetFin")
    static let recentlyAddedDays = String(localized: "Added in the last", table: "SweetFin")

    static func days(_ count: Int) -> String {
        String(localized: "\(count) days", table: "SweetFin")
    }
    static let hide = String(localized: "Hide", table: "SweetFin")

    /// « Ajouter à ma watchlist » passait sur deux lignes dans le menu d'appui long ;
    /// l'icône (signet +) porte déjà l'action.
    static let watchlist = String(localized: "Watchlist", table: "SweetFin")

    /// Libellé d'accessibilité du carrousel. Il n'est pas affiché : les diapos portent
    /// déjà le logo du média, et un titre au-dessus ferait doublon.
    static let mediaBar = String(localized: "Featured", table: "SweetFin")
    /// Bouton de la vitrine tvOS qui ouvre la fiche.
    static let info = String(localized: "Info", table: "SweetFin")
}
