//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// SweetFin : libellés SyncPlay, hors de `L10n` comme les autres écrans du fork.
enum SyncPlayStrings {

    static let title = "SyncPlay"
    static let join = "Rejoindre"
    static let decline = "Refuser"
    static let createGroup = "Créer un groupe"
    static let groups = "Groupes en cours"
    static let noGroups = "Aucun groupe en cours"
    static let participants = "Participants"
    static let invite = "Inviter"
    static let leave = "Quitter le groupe"
    static let offline = "Pas connecté"
    static let noUsers = "Personne d'autre à inviter"
    static let close = "Fermer"

    static func invited(by name: String) -> String {
        "\(name) t'invite à regarder ensemble"
    }

    static func groupName(of user: String) -> String {
        "Groupe de \(user)"
    }

    static func members(_ count: Int) -> String {
        count > 1 ? "\(count) participants" : "1 participant"
    }
}
