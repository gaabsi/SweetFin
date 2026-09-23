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
        // `enrich` : une fiche de découverte n'a ni logo, ni synopsis, ni casting
        // tant que le média n'est pas au référentiel, et c'est précisément là qu'on
        // en a besoin.
        enhancedFinMedia = await fetchEnhancedFinMedia(mediaKey)

        guard let media = enhancedFinMedia else {
            return try await _makeGroups(item: item, itemID: id)
        }

        let enriched = Self.syntheticItem(from: media, mediaKey: mediaKey)

        // Réassigner `item` et pas seulement le passer à `_makeGroups` : l'en-tête
        // d'`ItemView` lit `provider.item`, et sans ça la fiche garderait la version
        // pauvre de la liste — sans logo ni image de fond — alors que `?enrich=true`
        // vient justement de les renvoyer.
        replaceItem(enriched)

        return try await _makeGroups(item: enriched, itemID: id)
    }

    private static func syntheticItem(
        from media: EnhancedFinMedia,
        mediaKey: String
    ) -> BaseItemDto {
        EnhancedFinSyntheticItem.make(
            mediaKey: mediaKey,
            title: media.title,
            year: media.year,
            overview: media.detail?.overview,
            posterURL: media.posterUrl,
            backdropURL: media.backdropUrl,
            logoURL: media.logoUrl,
            genres: media.genreNames,
            rating: media.voteAverage,
            cast: media.detail?.cast,
            isPlayed: media.me.progress?.watched == true
        )
    }
}
