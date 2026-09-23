//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

struct RootView: View {

    // EnhancedFin : le thème du lancement précédent, déjà en `UserDefaults`.
    //
    // ⚠️ **Sans ce fond, l'app démarre en blanc puis en noir.** L'état `.initial`
    // n'était qu'un `ProgressView` sans fond : on voyait le `systemBackground` de la
    // fenêtre, en clair tant que `rootCoordinator.start()` n'avait pas imposé le style
    // sombre — et `start()` part d'un `.task`, donc après la première image. Lire le
    // thème ici est synchrone et ne dépend ni du réseau ni d'une session ouverte.
    @Default(.appearance)
    private var appearance

    @StateObject
    private var rootCoordinator: RootCoordinator = .init()

    var body: some View {
        ZStack {
            switch rootCoordinator.state {
            case .initial:
                ProgressView()
            case .error:
                ErrorView(error: rootCoordinator.error ?? ErrorMessage(L10n.unknownError))
            case .ready:
                UserSessionRootView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appearance.tokens.background.ignoresSafeArea())
        .animation(.linear(duration: 0.1), value: rootCoordinator.state)
        .task {
            rootCoordinator.start()
        }
    }
}
