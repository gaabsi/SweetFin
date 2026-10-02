//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let server: ServerState
    let user: UserState

    lazy var client: JellyfinClient = JellyfinClient(
        configuration: .swiftfinConfiguration(
            url: server.effectiveServerURL,
            accessToken: user.accessToken
        ),
        sessionConfiguration: .swiftfin,
        sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.swiftfin())
    )

    /// Client du plugin EnhancedFin (données utilisateur : notes, watchlist,
    /// reprise, suivis). API distincte du `JellyfinClient` ci-dessus, sur le
    /// même hôte et avec le même jeton.
    lazy var enhancedFinClient = EnhancedFinClient(
        serverURL: server.effectiveServerURL,
        accessToken: user.accessToken
    )

    lazy var serverSocketManager = ServerSocketManager()

    // SweetFin : SyncPlay
    @MainActor
    lazy var syncPlayManager = SyncPlayManager()

    @MainActor
    private lazy var services: [any UserSessionService] = [
        serverSocketManager,
        syncPlayManager,
    ]

    init(
        server: ServerState,
        user: UserState
    ) {
        self.server = server
        self.user = user
    }

    @MainActor
    func willStart() async {
        for service in services {
            await service.willStart(userSession: self)
        }

        // SweetFin : première connexion à ce serveur, on attend la réponse (2 s au plus)
        // pour que la barre d'onglets soit juste dès son affichage ; sinon la valeur
        // mémorisée suffit et la vérification part en tâche de fond.
        if Defaults[.enhancedFinAvailable] == nil {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.refreshEnhancedFinAvailability() }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
        } else {
            Task {
                await refreshEnhancedFinAvailability()
            }
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    /// SweetFin : détecte le plugin EnhancedFin et mémorise la réponse. Une réponse
    /// incertaine (pas de réseau, serveur en erreur) garde la dernière connue : couper
    /// le Wi-Fi ne doit pas faire disparaître l'Explorer.
    @MainActor
    func refreshEnhancedFinAvailability() async {
        guard let available = await enhancedFinClient.checkAvailability() else { return }

        Defaults[.enhancedFinAvailable] = available
    }

    @MainActor
    func willStop() {
        for service in services.reversed() {
            service.willStop(userSession: self)
        }
    }
}
