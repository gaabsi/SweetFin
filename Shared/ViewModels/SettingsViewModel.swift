//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

// TODO: should probably break out into a `Settings` and `AppSettings` view models
//       - could clean up all settings view models

final class SettingsViewModel: ViewModel {

    @Published
    var servers: [ServerState] = []

    override init() {
        super.init()

        servers = getServers()
    }

    private func getServers() -> [ServerState] {
        StoredValues[.Server.servers]
            .sorted(using: \.name)
    }
}
