//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import SwiftUI

/// Mon état sur un média — note, watchlist, suivi — et les actions qui le changent.
///
/// Partagé entre les trois boutons de la barre d'actions : sans ça chacun ferait
/// sa propre requête pour afficher le même `me`.
///
/// Les actions sont **optimistes** : l'état bascule immédiatement, et n'est rétabli
/// que si le serveur refuse. Un bouton qui attend l'aller-retour donne une
/// impression de lenteur sur une action aussi banale qu'une note.
@MainActor
final class EnhancedFinItemState: ObservableObject {

    @Published
    private(set) var rating: EnhancedFinScore?

    @Published
    private(set) var isInWatchlist = false

    @Published
    private(set) var isFollowing = false

    @Published
    private(set) var isLoaded = false

    let mediaKey: String

    private let logger = Logger.swiftfin()

    /// Chargement en cours ou déjà fait.
    ///
    /// Mémoriser la `Task` et non un booléen : les trois boutons appellent `load()`
    /// dans le même tour de boucle, donc **avant** la première suspension. Un
    /// drapeau posé à la sortie les laisserait tous franchir le garde et émettre
    /// trois fois la même requête `/media/{key}`. Attendre la tâche existante donne
    /// une requête et trois attentes.
    private var loadTask: Task<Void, Never>?

    @Injected(\.currentUserSession)
    private var userSession: UserSession?

    init(mediaKey: String) {
        self.mediaKey = mediaKey
    }

    /// Charge l'état depuis le serveur, une seule fois — **si le chargement aboutit**.
    ///
    /// Un `404` signifie que le média n'est pas encore dans le référentiel : ce
    /// n'est pas une erreur, simplement un média sur lequel je n'ai rien fait. C'est
    /// donc une réponse, et elle se mémorise.
    ///
    /// ⚠️ **Un échec réseau, lui, ne se mémorise pas.** `loadTask` sert de « déjà
    /// chargé » : y laisser un timeout figeait « non noté / pas en watchlist » sur la
    /// fiche pour toute la session, y compris après le retour du réseau, puisque
    /// l'état est en cache dans ``EnhancedFinItemStateStore``.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }

        // Pas de session : on ne mémorise rien, pour que l'appel suivant réessaie
        // une fois la session établie.
        guard EnhancedFinClient.isAvailable, let client = userSession?.enhancedFinClient else { return }

        let task = Task { [weak self] in
            await self?.fetch(with: client)
            return ()
        }
        loadTask = task

        await task.value
    }

    private func fetch(with client: EnhancedFinClient) async {
        do {
            let me = try await client.media(mediaKey).me
            rating = me.rating.flatMap(EnhancedFinScore.init(rawValue:))
            isInWatchlist = me.inWatchlist
            isFollowing = me.following
        } catch let problem as EnhancedFinProblem where problem.status == 404 {
            // Média hors référentiel : une réponse, pas un échec.
        } catch {
            logger.warning("EnhancedFin state load failed: \(error.localizedDescription)")

            // Réessayable au prochain affichage de la fiche.
            loadTask = nil
        }

        isLoaded = true
    }

    // MARK: - Actions

    func setRating(_ score: EnhancedFinScore?) async {
        let previous = rating
        rating = score

        await perform(revert: { self.rating = previous }) { client in
            if let score {
                try await client.rate(self.mediaKey, score)
            } else {
                try await client.removeRating(self.mediaKey)
            }
        }
    }

    func toggleWatchlist() async {
        let previous = isInWatchlist
        isInWatchlist.toggle()

        await perform(revert: { self.isInWatchlist = previous }) { client in
            if previous {
                try await client.removeFromWatchlist(self.mediaKey)
            } else {
                try await client.addToWatchlist(self.mediaKey)
            }
        }
    }

    func toggleFollow() async {
        let previous = isFollowing
        isFollowing.toggle()

        await perform(revert: { self.isFollowing = previous }) { client in
            if previous {
                try await client.unfollow(self.mediaKey)
            } else {
                try await client.follow(self.mediaKey)
            }
        }
    }

    private func perform(
        revert: @escaping () -> Void,
        _ action: (EnhancedFinClient) async throws -> Void
    ) async {
        guard let client = userSession?.enhancedFinClient else {
            revert()
            return
        }

        do {
            try await action(client)
            UIDevice.feedback(.success)
        } catch {
            revert()
            UIDevice.feedback(.error)
            logger.warning("EnhancedFin action failed: \(error.localizedDescription)")
        }
    }
}

/// Garde un seul ``EnhancedFinItemState`` par média **et par utilisateur**.
///
/// Sans ce cache, rouvrir une fiche repartirait d'un état vide et referait la
/// requête, et une note posée depuis la fiche ne se verrait pas au retour sur la
/// liste.
///
/// - Important: le cache est purgé au changement d'utilisateur. Indexé par le seul
///   `mediaKey`, il aurait servi à un profil la note du précédent, sans requête et
///   donc sans jamais se corriger — les données d'un compte fuitaient dans
///   l'affichage d'un autre.
@MainActor
final class EnhancedFinItemStateStore {

    static let shared = EnhancedFinItemStateStore()

    private var states: [String: EnhancedFinItemState] = [:]

    /// Utilisateur auquel appartiennent les états en cache.
    private var ownerID: String?

    private init() {}

    func state(for mediaKey: String) -> EnhancedFinItemState {
        // Serveur **et** utilisateur : le même profil sur deux serveurs n'a pas les
        // mêmes notes, et deux serveurs peuvent porter le même identifiant d'user.
        let currentID = Container.shared.currentUserSession()
            .map { "\($0.server.id)|\($0.user.id)" }

        if ownerID != currentID {
            states.removeAll()
            ownerID = currentID
        }

        if let existing = states[mediaKey] { return existing }

        let state = EnhancedFinItemState(mediaKey: mediaKey)
        states[mediaKey] = state
        return state
    }
}
