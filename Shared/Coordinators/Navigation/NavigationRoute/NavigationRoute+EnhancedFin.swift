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

    /// Fiche d'un média absent de la bibliothèque.
    ///
    /// Même destination qu'un item Jellyfin — `ItemView` — mais nourrie par un
    /// provider qui ne consulte pas le serveur. La transition est identique pour
    /// que rien ne distingue les deux à l'usage.
    @MainActor
    static func explorerItem(mediaKey: String, item: BaseItemDto) -> NavigationRoute {
        let provider = ExplorerItemProvider(mediaKey: mediaKey, item: item)

        return NavigationRoute(
            id: "explorer-item-\(mediaKey)",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ItemView(provider: provider)
        }
    }
}
