//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct CustomizeSettingsView: View {

    #if os(tvOS)
    typealias PlatformPicker = ListRowMenu
    #else
    typealias PlatformPicker = Picker
    #endif

    #if os(tvOS)
    @Default(.Customization.tabBarPlacement)
    private var tabBarPlacement
    #endif

    @Router
    private var router

    var body: some View {
        Form(systemImage: "gear") {

            #if os(tvOS)
            Section(L10n.tabBar) {
                ListRowMenu(L10n.layout, selection: $tabBarPlacement)
            }
            #endif

            ChevronButton(L10n.posters) {
                router.route(to: .posterSettings)
            }

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .playerSettings)
            }
        }
        .navigationTitle(L10n.advanced)
    }
}
