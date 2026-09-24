//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// `Router.Wrapper` et non `NavigationCoordinator.Router` : c'est ce que le
// property wrapper `@Router` expose aux vues.
extension Router.Wrapper {

    /// Ouvre la fiche d'un item EnhancedFin, sur le serveur ou non.
    ///
    /// En bibliothèque : la fiche native, avec lecture et épisodes. Sinon la même
    /// vue, nourrie par TMDB, bouton Lire grisé.
    ///
    /// Ici et non dans chaque écran : la règle était recopiée dans `ExplorerView` et
    /// `FilmographyGroup`, et chaque nouvelle liste en ajoutait une copie. Un écart
    /// entre elles n'aurait produit aucune erreur de compilation — juste une liste
    /// qui ouvre la mauvaise fiche.
    ///
    /// Parametres :
    /// - item (EnhancedFinLibraryLinkable) : item tapé
    /// - namespace (Namespace.ID) : espace de la transition
    func openEnhancedFin(_ item: some EnhancedFinLibraryLinkable, in namespace: Namespace.ID) {
        if let jellyfinItem = item.jellyfinItem {
            route(to: .item(item: jellyfinItem), in: namespace)
        } else {
            route(to: .explorerItem(mediaKey: item.mediaKey, item: item.syntheticItem), in: namespace)
        }
    }
}

extension NavigationRoute {

    /// Un rayon de watchlist en pleine page.
    ///
    /// Les items sont passés tels quels : l'Explorer les a déjà chargés, et les
    /// redemander afficherait un écran vide le temps d'une requête pour un contenu
    /// déjà en main.
    @MainActor
    static func explorerWatchlist(
        filter: WatchlistFilter,
        items: [EnhancedFinWatchlistItem]
    ) -> NavigationRoute {
        NavigationRoute(id: "explorer-watchlist-\(filter.rawValue)") {
            ExplorerPosterGrid(title: filter.pageTitle, items: items)
        }
    }

    /// Tout ce qui reste à noter, quand l'aperçu de l'Explorer ne suffit plus.
    @MainActor
    static func explorerPending(items: [EnhancedFinPendingRating]) -> NavigationRoute {
        NavigationRoute(id: "explorer-pending") {
            ExplorerPosterGrid(title: ExplorerStrings.toRate, items: items)
        }
    }

    /// Toutes mes notes, quand l'aperçu de l'Explorer ne suffit plus.
    @MainActor
    static func explorerRatings(items: [EnhancedFinRating]) -> NavigationRoute {
        NavigationRoute(id: "explorer-ratings") {
            ExplorerPosterGrid(title: ExplorerStrings.myRatings, items: items)
        }
    }

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

    /// L'écran « Avancé » du fork, voir `AdvancedSettingsView`.
    static var advancedSettings: NavigationRoute {
        NavigationRoute(id: "advancedSettings") {
            AdvancedSettingsView()
        }
    }
}
