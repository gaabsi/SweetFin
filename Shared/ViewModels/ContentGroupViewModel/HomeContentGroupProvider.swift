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

/// L'Accueil du fork : quatre sections, dans cet ordre.
///
/// | # | Section | Source |
/// |---|---|---|
/// | 1 | Carrousel | tirage aléatoire, non vu |
/// | 2 | Mes médias | les bibliothèques du serveur |
/// | 3 | Continuer de regarder | reprise + épisode suivant + sources externes |
/// | 4 | Ajoutés récemment | toutes bibliothèques confondues |
///
/// Remplace `DefaultContentGroupProvider`, **laissé intact** : c'est un fichier
/// upstream, et le remplacer plutôt que le modifier évite une neuvième retouche à
/// reporter à chaque rebase. Le branchement tient en un mot dans `MainTabView`.
///
/// Ce que l'Accueil upstream montrait et qu'on ne montre plus : « Next Up » en section
/// autonome (fusionnée dans la 3), les N rails « Derniers ajouts dans <bibliothèque> »
/// (fusionnés dans la 4), « Lus récemment » et « En ce moment » (TV en direct).
struct HomeContentGroupProvider: ContentGroupProvider {

    let displayTitle: String = L10n.home
    let id: String = "home-content-group-provider"

    /// ⚠️ **L'ordre d'écriture EST l'ordre à l'écran.** Déplacer une section se fait
    /// ici, et nulle part ailleurs.
    @ContentGroupBuilder
    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {

        // tvOS garde `DefaultContentGroupProvider` et son sélecteur cinématique ;
        // ce provider n'y est pas branché, mais il s'y compile quand même.
        #if os(iOS)
        MediaBarContentGroup()
        #endif

        UserViewsContentGroup()

        PosterGroup(
            library: ContinueWatchingLibrary(),
            posterDisplayType: .landscape,
            // `.medium` donne 1,5 tuile par écran — des vignettes énormes pour une
            // liste qu'on parcourt. `.small` en met deux, comme les autres rails.
            posterSize: .small,
            // Affiche la barre de progression et le libellé « S1E4 » sur les tuiles.
            _viewContext: .isInResume
        )

        // Le réglage « Ajoutés récemment » d'upstream continue de gouverner cette
        // section : il existe toujours dans les réglages, et ne plus le lire en
        // faisait un interrupteur qui ne fait rien.
        if Defaults[.Customization.Home.showRecentlyAdded] {
            PosterGroup(
                library: ItemLibrary(
                    parent: BaseItemDto(name: HomeStrings.recentlyAdded),
                    filters: .init(
                        itemTypes: [.movie, .series],
                        sortBy: [.dateCreated],
                        sortOrder: [.descending]
                    )
                )
            )
        }
    }
}
