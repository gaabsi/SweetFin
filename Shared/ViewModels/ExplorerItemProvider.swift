//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Provider d'`ItemView` pour un média **absent de la bibliothèque**.
///
/// Rend exactement la même vue que n'importe quel item Jellyfin : on ne
/// réimplémente rien, on remplace seulement la source des données.
///
/// Deux différences avec `ItemContentGroupProvider` :
///
/// 1. **Aucun appel à `getFullItem`.** L'identifiant n'existe sur aucun serveur ;
///    l'interroger renverrait une erreur et laisserait la vue en état d'échec.
/// 2. **`mediaPlayerItemProvider` reste `nil`.** `PlayButton` porte
///    `.disabled(provider.mediaPlayerItemProvider == nil)` — le bouton Lire se grise
///    donc de lui-même, sans qu'on ait à le toucher.
final class ExplorerItemProvider: ItemContentGroupProvider {

    private let mediaKey: String

    init(mediaKey: String, item: BaseItemDto) {
        self.mediaKey = mediaKey
        super.init(item: item)
    }

    /// Construit les groupes à partir de l'item déjà connu, enrichi si possible.
    ///
    /// L'item d'origine vient de l'écran d'où l'on a tapé (recherche, watchlist,
    /// note) et suffit à afficher quelque chose tout de suite. `GET /media/{key}`
    /// y ajoute le logo et le synopsis quand le média est dans le référentiel ;
    /// un `404` y est le cas normal pour un résultat TMDB jamais touché, et ne
    /// doit rien casser.
    override func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        guard let enriched = await enriched() else {
            return try await _makeGroups(item: item, itemID: id)
        }

        // Réassigner `item` et pas seulement le passer à `_makeGroups` : l'en-tête
        // d'`ItemView` lit `provider.item`, et sans ça la fiche garderait la version
        // pauvre de la liste — sans logo ni image de fond — alors que `?enrich=true`
        // vient justement de les renvoyer.
        replaceItem(enriched)

        return try await _makeGroups(item: enriched, itemID: id)
    }

    private func enriched() async -> BaseItemDto? {
        guard let client = userSession?.enhancedFinClient else { return nil }

        do {
            // `enrich` : une fiche de découverte n'a pas de logo ni de synopsis
            // tant que le média n'est pas au référentiel, et c'est précisément là
            // qu'on en a besoin. La demande est explicite, donc la règle tient.
            let media = try await client.media(mediaKey, detail: true, enrich: true)

            return EnhancedFinSyntheticItem.make(
                mediaKey: mediaKey,
                title: media.title,
                year: media.year,
                overview: media.detail?.overview,
                posterURL: media.posterUrl,
                backdropURL: media.backdropUrl,
                logoURL: media.logoUrl
            )
        } catch let problem as EnhancedFinProblem where problem.status == 404 {
            // Média hors référentiel : attendu, on garde ce qu'on a.
            return nil
        } catch {
            logger.warning("EnhancedFin media lookup failed: \(error.localizedDescription)")
            return nil
        }
    }
}
