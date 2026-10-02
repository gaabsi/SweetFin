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
    static let join = String(localized: "Join", table: "SweetFin")
    static let decline = String(localized: "Decline", table: "SweetFin")
    static let createGroup = String(localized: "Create a Group", table: "SweetFin")
    static let groups = String(localized: "Active Groups", table: "SweetFin")
    static let noGroups = String(localized: "No Active Groups", table: "SweetFin")
    static let participants = String(localized: "Participants", table: "SweetFin")
    static let invite = String(localized: "Invite", table: "SweetFin")
    static let leave = String(localized: "Leave Group", table: "SweetFin")
    static let offline = String(localized: "Offline", table: "SweetFin")
    static let noUsers = String(localized: "No One Else to Invite", table: "SweetFin")
    static let close = String(localized: "Close", table: "SweetFin")

    static func invited(by name: String) -> String {
        String(localized: "\(name) invites you to watch together", table: "SweetFin")
    }

    static func groupName(of user: String) -> String {
        String(localized: "\(user)'s Group", table: "SweetFin")
    }

    static func members(_ count: Int) -> String {
        String(localized: "\(count) participants", table: "SweetFin")
    }
}
