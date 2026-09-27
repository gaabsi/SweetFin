//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// EnhancedFin : plus de tiroir de filtres. Ne porte que les filtres courants d'une
/// médiathèque, que le sélecteur de lettres modifie.
@MainActor
final class FilterViewModel: ObservableObject {

    @Published
    var currentFilters: ItemFilterCollection

    init(currentFilters: ItemFilterCollection = .default) {
        self.currentFilters = currentFilters
    }
}
