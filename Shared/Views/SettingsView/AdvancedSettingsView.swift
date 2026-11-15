//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// SweetFin : l'écran « Avancé » du fork, iPhone et tvOS (❌ `CustomizeSettingsView`
/// d'upstream, supprimé le 2026-11-15 : tvOS n'y avait pas les réglages de l'Accueil).
///
/// Ce qui n'y figure pas (media bar, style de fiche, « Manquant »…) est décidé par le
/// fork, pas par l'utilisateur. tvOS ajoute la disposition de la barre d'onglets.
struct AdvancedSettingsView: View {

    #if os(tvOS)
    @Default(.Customization.tabBarPlacement)
    private var tabBarPlacement
    #endif

    @Default(.Customization.Home.showLibraries)
    private var showLibraries
    @Default(.Customization.Home.showRecentlyAdded)
    private var showRecentlyAdded
    @Default(.Customization.Home.recentlyAddedDays)
    private var recentlyAddedDays

    @Router
    private var router

    var body: some View {
        Form(systemImage: "gear") {
            #if os(tvOS)
            Section(L10n.tabBar) {
                ListRowMenu(L10n.layout, selection: $tabBarPlacement)
            }
            #endif

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .playerSettings)
            }

            Section(L10n.home) {
                Toggle(HomeStrings.myMedia, isOn: $showLibraries)
                Toggle(HomeStrings.recentlyAdded, isOn: $showRecentlyAdded)

                if showRecentlyAdded {
                    Picker(HomeStrings.recentlyAddedDays, selection: $recentlyAddedDays) {
                        ForEach(HomeRecentlyAddedLibrary.dayOptions, id: \.self) { days in
                            Text(HomeStrings.days(days))
                                .tag(days)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.advanced)
        // L'Accueil reste ouvert sous cette feuille : on lui dit de se reconstruire.
        .onChange(of: [showLibraries, showRecentlyAdded]) {
            Notifications[.didRequestGlobalRefresh].post()
        }
        .onChange(of: recentlyAddedDays) {
            Notifications[.didRequestGlobalRefresh].post()
        }
    }
}
