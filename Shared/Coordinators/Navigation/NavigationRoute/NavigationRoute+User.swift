//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension NavigationRoute {

    static var connectToServer: NavigationRoute {
        NavigationRoute(
            id: "connectToServer",
            style: .sheet
        ) {
            ConnectToServerView()
        }
    }

    static func quickConnect(client: JellyfinClient, action: @escaping (String) async -> Void) -> NavigationRoute {
        NavigationRoute(
            id: "quickConnectView",
            style: .sheet
        ) {
            QuickConnectView(client: client, action: action)
        }
    }

    static func userSignIn(server: ServerState) -> NavigationRoute {
        NavigationRoute(
            id: "userSignIn",
            style: .sheet
        ) {
            UserSignInView(server: server)
        }
    }
}
