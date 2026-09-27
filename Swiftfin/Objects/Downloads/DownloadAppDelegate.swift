//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import UIKit

/// EnhancedFin : seul point d'entrée qu'iOS offre quand il relance l'app pour un
/// téléchargement terminé app fermée. SwiftUI n'a pas d'équivalent.
final class DownloadAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.sessionIdentifier else { return completionHandler() }

        // Créer le gestionnaire recrée la session : iOS lui livre alors ses événements.
        Container.shared.downloadManager().backgroundCompletionHandler = completionHandler
    }
}
