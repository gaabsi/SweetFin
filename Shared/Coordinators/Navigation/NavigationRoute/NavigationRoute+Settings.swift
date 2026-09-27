//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import PulseUI
import SwiftUI

extension NavigationRoute {

    #if os(iOS)
    static var adminDashboard: NavigationRoute {
        NavigationRoute(
            id: "adminDashboard"
        ) {
            AdminDashboardView()
        }
    }
    #endif

    static var customizeSettingsView: NavigationRoute {
        NavigationRoute(
            id: "customizeSettingsView"
        ) {
            CustomizeSettingsView()
        }
    }

    #if DEBUG
    static var debugSettings: NavigationRoute {
        NavigationRoute(
            id: "debugSettings"
        ) {
            DebugSettingsView()
        }
    }
    #endif

    static func editLocalServer(server: ServerState, isEditing: Bool = false) -> NavigationRoute {
        NavigationRoute(id: "editServer") {
            EditLocalServerView(
                server: server,
                isDeletePresented: isEditing
            )
        }
    }

    @MainActor
    static func serverConnections(viewModel: ServerConnectionViewModel) -> NavigationRoute {
        NavigationRoute(
            id: "serverConnections-\(viewModel.server.id)"
        ) {
            ServerConnectionView(viewModel: viewModel)
        }
    }

    @MainActor
    static func editServerConnection(
        viewModel: ServerConnectionViewModel,
        connection: ServerConnection
    ) -> NavigationRoute {
        NavigationRoute(
            id: "serverConnection-\(viewModel.server.id)-\(connection.id)",
            style: .sheet
        ) {
            EditServerConnectionView(
                viewModel: viewModel,
                connection: connection
            )
        }
    }

    static var posterSettings: NavigationRoute {
        NavigationRoute(
            id: "posterSettings"
        ) {
            CustomizeSettingsView.PosterSection()
        }
    }

    static var indicatorSettings: NavigationRoute {
        NavigationRoute(
            id: "indicatorSettings"
        ) {
            IndicatorSettingsView()
        }
    }

    static func localUserSettings(user: UserDto) -> NavigationRoute {
        NavigationRoute(id: "localUserSettings") {
            LocalUserSettingsView(user: user)
        }
    }

    static var log: NavigationRoute {
        NavigationRoute(
            id: "log"
        ) {
            ConsoleView()
        }
    }

    #if os(iOS)
    static func resetUserPassword(userID: String) -> NavigationRoute {
        NavigationRoute(
            id: "resetUserPassword",
            style: .sheet
        ) {
            ResetUserPasswordView(userID: userID, requiresCurrentPassword: true)
        }
    }
    #endif

    static var settings: NavigationRoute {
        NavigationRoute(
            id: "settings",
            style: .sheet
        ) {
            SettingsView()
        }
    }

}
