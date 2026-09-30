//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let server: ServerState
    let user: UserState

    lazy var client: JellyfinClient = JellyfinClient(
        configuration: .swiftfinConfiguration(
            url: server.effectiveServerURL,
            accessToken: user.accessToken
        ),
        sessionConfiguration: .swiftfin,
        sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
    )

    /// Client du plugin EnhancedFin (données utilisateur : notes, watchlist,
    /// reprise, suivis). API distincte du `JellyfinClient` ci-dessus, sur le
    /// même hôte et avec le même jeton.
    lazy var enhancedFinClient = EnhancedFinClient(
        serverURL: server.effectiveServerURL,
        accessToken: user.accessToken
    )

    lazy var serverSocketManager = ServerSocketManager()

    // SweetFin : SyncPlay
    @MainActor
    lazy var syncPlayManager = SyncPlayManager()

    @MainActor
    private lazy var services: [any UserSessionService] = [
        serverSocketManager,
        syncPlayManager,
    ]

    init(
        server: ServerState,
        user: UserState
    ) {
        self.server = server
        self.user = user
    }

    @MainActor
    func willStart() async {
        for service in services {
            await service.willStart(userSession: self)
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    @MainActor
    func willStop() {
        for service in services.reversed() {
            service.willStop(userSession: self)
        }
    }
}
