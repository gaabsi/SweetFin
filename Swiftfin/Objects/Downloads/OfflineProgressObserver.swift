//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation

/// SweetFin : note la position d'une lecture de téléchargement **quand il n'y a aucun
/// réseau**, là où les rapports de `MediaProgressObserver` échouent.
///
/// En ligne, il ne fait rien : upstream rapporte déjà la position à Jellyfin, et une copie
/// locale écraserait plus tard ce qui aurait été regardé ailleurs entre-temps.
///
/// Même cadence qu'upstream, en plus lent : toutes les 10 s, à chaque pause ou reprise,
/// et à l'arrêt.
final class OfflineProgressObserver: MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let save: (Duration) -> Void
    private let timer = PokeIntervalTimer(defaultInterval: 10)
    private var cancellables = Set<AnyCancellable>()

    /// Parametres :
    /// - save ((Duration) -> Void) : écrit la position dans le dossier du téléchargement
    init(save: @escaping (Duration) -> Void) {
        self.save = save
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        timer.sink { [weak self] in
            self?.saveIfOffline()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] _ in self?.saveIfOffline() }
            .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                guard case .stop = action else { return }
                self?.saveIfOffline()
                self?.timer.stop()
                self?.cancellables = []
            }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self] _ in self?.saveIfOffline() }
            .store(in: &cancellables)

        timer.poke()
    }

    private func saveIfOffline() {
        guard let manager, Container.shared.offlineMonitor().isOffline else { return }
        save(manager.seconds)
    }
}
