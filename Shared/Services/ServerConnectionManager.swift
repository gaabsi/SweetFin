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

/// EnhancedFin : ne garde que le test d'une adresse de serveur. Le changement
/// automatique de connexion (surveillance du réseau, bascule d'adresse) est supprimé.
enum ServerConnectionManager {

    static func test(
        connection: ServerConnection,
        accessToken: String? = nil,
        matchingServerID serverID: String
    ) async throws -> PublicSystemInfo {
        let sessionConfiguration = URLSessionConfiguration.swiftfin.copy() as! URLSessionConfiguration
        sessionConfiguration.timeoutIntervalForRequest = 8
        sessionConfiguration.timeoutIntervalForResource = 12
        sessionConfiguration.waitsForConnectivity = false

        let client = JellyfinClient(
            configuration: .swiftfinConfiguration(
                url: connection.url,
                accessToken: accessToken
            ),
            sessionConfiguration: sessionConfiguration,
            sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
        )

        let response = try await client.send(Paths.getPublicSystemInfo)
        let publicInfo = response.value

        if publicInfo.id != serverID {
            throw ErrorMessage(L10n.connectionServerMismatch)
        }

        return publicInfo
    }
}
