//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres à la fiche média du fork.
///
/// Hors de `L10n`, pour la même raison qu'`ExplorerStrings` et `HomeStrings` :
/// celui-ci est généré par SwiftGen depuis les fichiers de traduction upstream, qu'il
/// faudrait modifier dans les vingt langues — et qui entreraient en conflit à chaque
/// rebase.
enum ItemStrings {

    /// Remplace `L10n.castAndCrew`, traduit « Distribution des rôles & équipe
    /// technique » : trop long pour un titre de rail.
    static let cast = String(localized: "Cast", table: "SweetFin")

    // Bloc « infos » (`ItemFactsContentGroup`).
    static let facts = String(localized: "Info", table: "SweetFin")
    static let releaseDate = String(localized: "Release Date", table: "SweetFin")
    static let firstAired = String(localized: "First Aired", table: "SweetFin")
    static let directedBy = String(localized: "Directed By", table: "SweetFin")
    static let createdBy = String(localized: "Created By", table: "SweetFin")
    static let ratings = String(localized: "Ratings", table: "SweetFin")

    // Saisons et épisodes (`SeasonsContentGroup`).
    static let markAsWatched = String(localized: "Mark as Watched", table: "SweetFin")
    static let validate = String(localized: "Confirm", table: "SweetFin")

    static func watchedCount(_ watched: Int, of total: Int) -> String {
        String(localized: "\(watched)/\(total) watched", table: "SweetFin")
    }
}
