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
    static let cast = "Casting"
}
