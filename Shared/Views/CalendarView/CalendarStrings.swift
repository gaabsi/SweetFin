//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres au Calendrier.
///
/// Hors de `L10n`, pour la même raison qu'`ExplorerStrings` : celui-ci est généré par
/// SwiftGen depuis les fichiers de traduction upstream, qu'il faudrait modifier dans
/// les vingt langues — et qui entreraient en conflit à chaque rebase.
enum CalendarStrings {

    static let calendar = "Calendrier"
    static let today = "Aujourd'hui"

    static let emptyTitle = "Aucune sortie"
    static let emptyMessage = "Suis des séries depuis leur fiche pour voir leurs prochains épisodes ici."

    static let unavailableTitle = "Calendrier indisponible"
    static let unavailableMessage = "Le plugin EnhancedFin n'a pas répondu. Vérifie qu'il est installé sur ce serveur."

    static let previousPeriod = "Période précédente"
    static let nextPeriod = "Période suivante"

    // MARK: - Mes suivis

    static let myFollows = "Mes suivis"
    static let unfollow = "Ne plus suivre"

    /// Une série terminée, ou dont la suite n'est pas encore annoncée.
    static let noNextAirDate = "Aucune date annoncée"

    /// Prochaine diffusion connue.
    ///
    /// Parametres :
    /// - date (String) : date déjà formatée pour la langue de l'appareil
    static func nextAir(_ date: String) -> String {
        "Prochain : \(date)"
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
