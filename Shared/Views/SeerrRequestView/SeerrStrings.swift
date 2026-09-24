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

    static let requestOnSeerr = "Demander sur Seerr"
    static let request = "Demander"

    static let requestSeries = "Demander une série"
    static let requestMovie = "Demander un film"

    static let selectAll = "Tout sélectionner"
    static let seasons = "Saisons"

    static func season(_ number: Int) -> String {
        "Saison \(number)"
    }

    static func episodes(_ count: Int) -> String {
        "\(count) ép."
    }

    static func confirmMovie(_ title: String) -> String {
        "« \(title) » sera demandé sur Seerr, à ton nom."
    }

    // Statuts Seerr
    static let available = "Disponible"
    static let partiallyAvailable = "Partielle"
    static let pending = "En attente"
    static let notRequested = "Non demandée"
}
