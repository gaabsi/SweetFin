//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct ServerConnection: Displayable, Hashable, Identifiable, Storable {

    enum TestState {
        case idle
        case testing
        case success
        case failure(String)
    }

    let id: String
    var name: String
    private(set) var url: URL
    var priority: Int

    init(
        id: String,
        name: String,
        url: URL,
        priority: Int
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.priority = priority
    }

    var displayTitle: String {
        name.nilIfBlank ?? url.absoluteString
    }

    static func isDuplicate(_ connection: ServerConnection, in connections: [ServerConnection]) -> Bool {
        connections.contains { existingConnection in
            existingConnection.id != connection.id &&
                existingConnection.url == connection.url
        }
    }

    static func ordered(_ connections: [ServerConnection], preservingOrder: Bool = false) -> [ServerConnection] {
        let connections = preservingOrder ? connections : connections.sorted(using: \.priority)

        return connections
            .enumerated()
            .map { index, connection in
                connection.with(priority: index)
            }
    }

    func with(priority: Int) -> ServerConnection {
        ServerConnection(
            id: id,
            name: name,
            url: url,
            priority: priority
        )
    }
}
