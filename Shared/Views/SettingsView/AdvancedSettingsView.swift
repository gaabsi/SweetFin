//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// EnhancedFin : l'écran « Avancé » du fork, à la place de `CustomizeSettingsView`.
///
/// Remplace l'écran upstream plutôt que de le modifier : `CustomizeSettingsView` reste
/// intact et sert tvOS. Ce qui n'y figure plus — filtres de recherche, bandes-annonces,
/// boutons de fiche, « Manquant » — est décidé par le fork, pas par l'utilisateur.
struct AdvancedSettingsView: View {

    @Default(.Customization.Home.showMediaBar)
    private var showMediaBar
    @Default(.Customization.Home.showLibraries)
    private var showLibraries
    @Default(.Customization.Home.showContinueWatching)
    private var showContinueWatching
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Home.recentlyAddedLimit)
    private var recentlyAddedLimit

    @Router
    private var router

    var body: some View {
        Form(systemImage: "gear") {
            ChevronButton(L10n.items) {
                router.route(to: .itemSettings)
            }

            ChevronButton(L10n.libraries) {
                router.route(to: .librarySettings)
            }

            ChevronButton(L10n.posters) {
                router.route(to: .posterSettings)
            }

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .playerSettings)
            }

            Section(L10n.home) {
                Toggle(HomeStrings.mediaBar, isOn: $showMediaBar)
                Toggle(HomeStrings.myMedia, isOn: $showLibraries)
                Toggle(HomeStrings.continueWatching, isOn: $showContinueWatching)
                Toggle(HomeStrings.recentlyAdded, isOn: $showRecentlyAdded)

                if showRecentlyAdded {
                    Stepper(value: $recentlyAddedLimit, in: 5 ... 50, step: 5) {
                        LabeledContent(HomeStrings.recentlyAddedLimit, value: recentlyAddedLimit.description)
                    }
                }
            }
        }
        .navigationTitle(L10n.advanced)
        // L'Accueil reste ouvert sous cette feuille : on lui dit de se reconstruire.
        .onChange(of: [showMediaBar, showLibraries, showContinueWatching, showRecentlyAdded]) {
            Notifications[.didRequestGlobalRefresh].post()
        }
        .onChange(of: recentlyAddedLimit) {
            Notifications[.didRequestGlobalRefresh].post()
        }
    }
}
