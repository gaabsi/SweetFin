//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés des demandes Seerr (menu « … » de la fiche, fenêtre de demande).
///
/// Hors de `L10n`, pour la même raison que `HomeStrings` : `L10n` est généré depuis les
/// fichiers de traduction upstream, qui entreraient en conflit à chaque rebase.
enum SeerrStrings {

    static let requestOnSeerr = String(localized: "Request on Seerr", table: "SweetFin")
    static let request = String(localized: "Request", table: "SweetFin")

    static let requestSeries = String(localized: "Request a Show", table: "SweetFin")
    static let requestMovie = String(localized: "Request a Movie", table: "SweetFin")

    static let selectAll = String(localized: "Select All", table: "SweetFin")
    static let seasons = String(localized: "Seasons", table: "SweetFin")

    static func season(_ number: Int) -> String {
        String(localized: "Season \(number)", table: "SweetFin")
    }

    static func episodes(_ count: Int) -> String {
        String(localized: "\(count) ep.", table: "SweetFin")
    }

    static func confirmMovie(_ title: String) -> String {
        String(localized: "“\(title)” will be requested on Seerr under your name.", table: "SweetFin")
    }

    // Statuts Seerr
    static let available = String(localized: "Available", table: "SweetFin")
    static let partiallyAvailable = String(localized: "Partially Available", table: "SweetFin")
    static let pending = String(localized: "Pending", table: "SweetFin")
    static let notRequested = String(localized: "Not Requested", table: "SweetFin")
}
