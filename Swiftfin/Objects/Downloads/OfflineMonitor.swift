//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Network

extension Container {

    var offlineMonitor: Factory<OfflineMonitor> {
        self { OfflineMonitor() }
            .singleton
    }
}

/// SweetFin : « l'appareil n'a aucun réseau » (mode avion, ni Wi-Fi ni cellulaire).
///
/// **Seulement ça** : une 4G/5G compte comme « en ligne », même si le serveur ne répond
/// pas — le streaming habituel reste la règle dès qu'il y a du réseau.
/// D'où l'absence de sonde du serveur : la surveillance réseau d'iOS suffit, et elle
/// répond sans délai.
final class OfflineMonitor: ObservableObject {

    @Published
    private(set) var isOffline = false

    private let monitor = NWPathMonitor()

    init() {
        // Appelé tout de suite avec l'état courant, puis à chaque changement de réseau.
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied

            DispatchQueue.main.async {
                guard let self, self.isOffline != isOffline else { return }
                self.isOffline = isOffline
            }
        }
        monitor.start(queue: DispatchQueue(label: "SweetFin.OfflineMonitor"))
    }
}
