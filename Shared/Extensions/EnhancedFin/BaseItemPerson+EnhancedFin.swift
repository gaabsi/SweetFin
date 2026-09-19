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

extension BaseItemPerson {

    /// Identifiant TMDB de cette personne, quand il est connaissable.
    ///
    /// Deux origines, très inégales :
    ///
    /// - une personne issue d'une **fiche de découverte** porte déjà la clé dans son
    ///   identifiant, que nous avons posée ;
    /// - une personne issue d'une **fiche native** n'a qu'un GUID Jellyfin.
    ///   `BaseItemPerson` ne transporte pas de `ProviderIds` — il faut donc
    ///   interroger le serveur pour lire celui de l'item correspondant, que le
    ///   fournisseur de métadonnées a renseigné ou non.
    ///
    /// - Important: la méthode **lève** au lieu d'avaler l'erreur réseau. Un `try?`
    ///   confondait « le serveur n'a pas répondu » et « cette personne n'a pas
    ///   d'identifiant TMDB », et l'appelant présentait un délai d'attente ou un
    ///   401 comme une absence de métadonnées.
    ///
    /// Output :
    /// - id (Int?) : identifiant TMDB, `nil` si la personne n'en a réellement pas
    func enhancedFinTmdbID() async throws -> Int? {
        guard let id else { return nil }

        if let tmdbID = EnhancedFinSyntheticItem.personTmdbID(from: id) {
            return tmdbID
        }

        guard let userSession = Container.shared.currentUserSession() else { return nil }

        let request = Paths.getItem(itemID: id, userID: userSession.user.id)
        let response = try await userSession.client.send(request)

        return response.value.providerIDs?["Tmdb"].flatMap(Int.init)
    }
}
