//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres au Calendrier, hors de `L10n` comme tous ceux du fork (voir `ExplorerStrings`).
enum CalendarStrings {

    static let calendar = String(localized: "Calendar", table: "SweetFin")
    static let today = String(localized: "Today", table: "SweetFin")

    static let emptyTitle = String(localized: "No Releases", table: "SweetFin")
    static let emptyMessage = String(localized: "Follow shows from their page to see their upcoming episodes here.", table: "SweetFin")

    static let unavailableTitle = String(localized: "Calendar Unavailable", table: "SweetFin")
    static let unavailableMessage = String(localized: "The EnhancedFin plugin did not respond. Check that it is installed on this server.", table: "SweetFin")

    static let previousPeriod = String(localized: "Previous Period", table: "SweetFin")
    static let nextPeriod = String(localized: "Next Period", table: "SweetFin")

    // MARK: - Mes suivis

    static let myFollows = String(localized: "Following", table: "SweetFin")
    static let unfollow = String(localized: "Unfollow", table: "SweetFin")

    /// Une série terminée, ou dont la suite n'est pas encore annoncée.
    static let noNextAirDate = String(localized: "No Date Announced", table: "SweetFin")

    /// Prochaine diffusion connue.
    ///
    /// Parametres :
    /// - date (String) : date déjà formatée pour la langue de l'appareil
    static func nextAir(_ date: String) -> String {
        String(localized: "Next: \(date)", table: "SweetFin")
    }

    // MARK: - Grille

    /// Nombre de sorties non affichées dans une case, faute de place.
    ///
    /// Parametres :
    /// - count (Int) : sorties restantes
    static func more(_ count: Int) -> String {
        "+\(count)"
    }
}
