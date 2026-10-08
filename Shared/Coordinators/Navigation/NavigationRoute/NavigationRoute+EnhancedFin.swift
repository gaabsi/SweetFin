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
    /// vue, nourrie par TMDB, bouton Lire selon la réponse du serveur (`playable`).
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

    /// Lance la lecture d'un item depuis une tuile, sans passer par sa fiche.
    ///
    /// Le lecteur s'ouvre **tout de suite** sur la tuile (titre, fond) et affiche le
    /// chargement : la résolution se fait dedans, comme une chaîne de TV en direct.
    /// `ItemContentGroupProvider.resolvePlayback` y trouve l'épisode à lire et sa
    /// position par le même chemin que la fiche. Un épisode reçoit sa file
    /// (précédent / suivant, panneau Épisodes) une fois connu.
    ///
    /// Partagé par la media bar et « Continuer de regarder ».
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item à lire
    @MainActor
    func play(_ item: BaseItemDto) {
        play(MediaPlayerItemProvider(item: item) { item, modifyItem in
            guard let resolved = await ItemContentGroupProvider(item: item).resolvePlayback() else {
                throw ErrorMessage(PlayerStrings.nothingToPlay)
            }
            return try await resolved.modifyingItem { modifyItem?(&$0) }()
        })
    }

    /// Ouvre le lecteur tout de suite sur une lecture encore à résoudre. Un épisode
    /// reçoit sa file une fois résolu.
    ///
    /// Partagé par les tuiles (``play(_:)-item``), la feuille des épisodes et le bouton
    /// Lire de la fiche : une seule règle pour la file, appliquée à l'item résolu.
    ///
    /// Parametres :
    /// - provider (MediaPlayerItemProvider) : lecture à résoudre dans le lecteur
    /// - seriesKey (String?) : clé de la série, à défaut celle de l'id synthétique affiché
    @MainActor
    func play(_ provider: MediaPlayerItemProvider, seriesKey: String? = nil) {
        // L'item affiché pendant la résolution porte la série quand elle est hors
        // bibliothèque (id synthétique) : la file en a besoin pour ses épisodes.
        let seriesKey = seriesKey ?? EnhancedFinSyntheticItem.mediaKey(from: provider.item.id)
        let manager = MediaPlayerManager(provider: provider) { resolvedItem in
            resolvedItem.type == .episode ? EpisodeMediaPlayerQueue(episode: resolvedItem, seriesKey: seriesKey) : nil
        }
        route(to: .videoPlayer(manager: manager))
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
    /// la route doit partir sans attendre. `ExplorerPersonProvider` s'en charge ; sans
    /// identifiant TMDB, il retombe sur l'état civil seul.
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

    #if os(iOS)
    /// L'écran « Avancé » du fork, voir `AdvancedSettingsView`. iOS uniquement.
    static var advancedSettings: NavigationRoute {
        NavigationRoute(id: "advancedSettings") {
            AdvancedSettingsView()
        }
    }
    #endif

    #if os(iOS)
    /// La suite de la saison en cours à télécharger, voir `SeasonDownloadView`.
    static func seasonDownload(series: BaseItemDto) -> NavigationRoute {
        NavigationRoute(id: "seasonDownload-\(series.id ?? "")", style: .sheet) {
            SeasonDownloadView(series: series)
        }
    }
    #endif

    /// La fenêtre « Demander sur Seerr », voir `SeerrRequestView`.
    static func seerrRequest(media: EnhancedFinMedia) -> NavigationRoute {
        NavigationRoute(id: "seerrRequest-\(media.mediaKey)", style: .sheet) {
            SeerrRequestView(media: media)
        }
    }

    /// Les réglages du lecteur du fork, voir `PlayerSettingsView`.
    static var playerSettings: NavigationRoute {
        NavigationRoute(id: "playerSettings") {
            PlayerSettingsView()
        }
    }
}
