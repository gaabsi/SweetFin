//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Transaction {

    /// SweetFin : une transaction qui coupe les animations (ouverture du lecteur,
    /// recentrage de la media bar, changement de tri).
    static var noAnimation: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}
