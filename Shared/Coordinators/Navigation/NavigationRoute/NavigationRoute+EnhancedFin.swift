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

    /// Fiche d'une personne, avec sa filmographie complète.
    ///
    /// L'identifiant TMDB n'est pas résolu ici : il demande parfois une requête, et
    /// la route doit partir sans attendre. `ExplorerPersonProvider` s'en charge, et
    /// affiche l'échec s'il y en a un — y compris « pas d'identifiant TMDB », qui
    /// n'a donc plus besoin de sa route dédiée.
    @MainActor
    static func explorerPerson(person: BaseItemPerson) -> NavigationRoute {
        let provider = ExplorerPersonProvider(person: person)

        return NavigationRoute(
            id: "explorer-person-\(person.id ?? person.name ?? "")",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            ItemView(provider: provider)
        }
    }
}
