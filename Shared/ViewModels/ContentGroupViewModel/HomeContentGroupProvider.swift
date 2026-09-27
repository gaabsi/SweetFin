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

        // Chaque section est activée dans Réglages → Avancé (`AdvancedSettingsView`) ;
        // l'Accueil ne fait que lire ces réglages.
        //
        // Aucun titre de section n'est cliquable : l'Accueil montre une sélection, pas
        // un catalogue. Les bibliothèques complètes s'ouvrent depuis « Mes médias ».

        // La media bar : carrousel à balayer sur iOS, sélecteur cinématique (le fond
        // suit le focus) sur tvOS. Même tirage aléatoire des deux côtés.
        #if os(iOS)
        MediaBarContentGroup()
        #else
        CinematicMediaBarContentGroup()
        #endif

        if Defaults[.Customization.Home.showLibraries] {
            UserViewsContentGroup()
        }

        ContinueWatchingContentGroup()

        if Defaults[.Customization.Home.showRecentlyAdded] {
            PosterGroup(
                library: HomeRecentlyAddedLibrary(),
                environment: .init(isHeaderButtonEnabled: false)
            )
        }
    }
}
