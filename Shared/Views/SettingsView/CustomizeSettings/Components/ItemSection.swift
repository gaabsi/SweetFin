//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension CustomizeSettingsView {

    #if os(tvOS)
    typealias PlatformPicker = ListRowMenu
    #else
    typealias PlatformPicker = Picker
    #endif

    struct ItemSection: View {

        @Default(.Customization.itemViewType)
        private var itemViewType

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers

        @Default(.Customization.shouldShowRecommendations)
        private var shouldShowRecommendations
        @Default(.Customization.shouldShowMissingSeasons)
        private var shouldShowMissingSeasons
        @Default(.Customization.shouldShowMissingEpisodes)
        private var shouldShowMissingEpisodes

        var body: some View {
            Form(systemImage: "gear") {
                Section {
                    PlatformPicker(L10n.style, selection: $itemViewType)
                } header: {
                    Text(L10n.itemView.localizedCapitalized)
                }

                Section {
                    PlatformPicker(L10n.enabledTrailers, selection: $enabledTrailers)

                    Toggle(L10n.showRecommendations, isOn: $shouldShowRecommendations)
                }

                // EnhancedFin : plus de section « Boutons » — ceux de la fiche sont imposés
                // (`ItemActionButton.barButtons`, `menuButtons`).

                Section {
                    Toggle(L10n.showMissingSeasons, isOn: $shouldShowMissingSeasons)
                    Toggle(L10n.showMissingEpisodes, isOn: $shouldShowMissingEpisodes)
                } header: {
                    Text(L10n.missing)
                }
            }
            .navigationTitle(L10n.items)
        }
    }
}
