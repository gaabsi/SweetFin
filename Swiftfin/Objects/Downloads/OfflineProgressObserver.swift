//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// SweetFin : note la position d'une lecture de téléchargement, **réseau ou pas**, puis
/// demande son envoi à l'arrêt (`onStop`).
///
/// ❌ Noter seulement « hors connexion » (`OfflineMonitor`) : une 4G sans signal compte
/// comme connectée, rien n'était noté et les rapports d'upstream échouaient — position
/// perdue (vécu le 2026-11-16). L'envoi dès l'arrêt limite le risque inverse : écraser plus
/// tard ce qui aurait été regardé ailleurs entre-temps.
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
    private let onStop: () -> Void
    private let timer = PokeIntervalTimer(defaultInterval: 10)
    private var cancellables = Set<AnyCancellable>()

    /// Parametres :
    /// - save ((Duration) -> Void) : écrit la position dans le dossier du téléchargement
    /// - onStop (() -> Void) : appelé à l'arrêt, après la dernière position notée
    init(save: @escaping (Duration) -> Void, onStop: @escaping () -> Void) {
        self.save = save
        self.onStop = onStop
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        timer.sink { [weak self] in
            self?.saveProgress()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] _ in self?.saveProgress() }
            .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                guard case .stop = action else { return }
                self?.saveProgress()
                self?.onStop()
                self?.timer.stop()
                self?.cancellables = []
            }
            .store(in: &cancellables)

        Notifications[.applicationWillTerminate]
            .publisher
            .sink { [weak self] _ in self?.saveProgress() }
            .store(in: &cancellables)

        timer.poke()
    }

    private func saveProgress() {
        guard let manager else { return }
        save(manager.seconds)
    }
}
