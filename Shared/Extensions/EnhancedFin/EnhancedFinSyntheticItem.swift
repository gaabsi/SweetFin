//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Fabrique un `BaseItemDto` à partir des données EnhancedFin, pour qu'un média
/// absent de la bibliothèque soit rendu par la vraie `ItemView`.
///
/// L'identifiant n'existe sur aucun serveur : il est dérivé du `mediaKey`, donc
/// stable d'une ouverture à l'autre — deux navigations vers le même titre
/// réutilisent les images déjà enregistrées.
///
/// - Important: ce `BaseItemDto` ne doit jamais partir vers l'API Jellyfin. Il ne
///   sert qu'à nourrir l'affichage.
enum EnhancedFinSyntheticItem {

    /// Préfixe qui rend un item synthétique reconnaissable dans les journaux et
    /// empêche toute collision avec un GUID Jellyfin.
    static let idPrefix = "enhancedfin:"

    static func id(for mediaKey: String) -> String {
        idPrefix + mediaKey
    }

    static func isSynthetic(_ itemID: String?) -> Bool {
        itemID?.hasPrefix(idPrefix) ?? false
    }

    /// Construit l'item et enregistre ses images externes.
    ///
    /// Parametres :
    /// - mediaKey (String) : clé au format '{movie|tv}:{tmdb_id}'
    /// - title (String) : titre affiché
    /// - year (Int?) : année de sortie
    /// - overview (String?) : synopsis
    /// - posterURL (String?) : affiche TMDB
    /// - backdropURL (String?) : image large TMDB
    /// - logoURL (String?) : logo TMDB
    /// - genres ([String]?) : noms de genres
    ///
    /// Output :
    /// - item (BaseItemDto) : item synthétique prêt à être affiché
    static func make(
        mediaKey: String,
        title: String,
        year: Int? = nil,
        overview: String? = nil,
        posterURL: String? = nil,
        backdropURL: String? = nil,
        logoURL: String? = nil,
        genres: [String]? = nil
    ) -> BaseItemDto {
        let itemID = id(for: mediaKey)

        var images: [ImageType: URL] = [:]
        if let url = posterURL.flatMap(URL.init(string:)) { images[.primary] = url }
        if let url = backdropURL.flatMap(URL.init(string:)) { images[.backdrop] = url }
        if let url = logoURL.flatMap(URL.init(string:)) { images[.logo] = url }

        EnhancedFinImageRegistry.shared.register(itemID: itemID, images: images)

        var item = BaseItemDto(id: itemID)
        item.name = title
        item.overview = overview
        item.productionYear = year
        item.genres = genres
        item.type = EnhancedFinMediaType(mediaKey: mediaKey) == .tv ? .series : .movie

        // `ItemView` choisit sa présentation enrichie sur la présence d'un tag de
        // backdrop. Le tag lui-même n'est jamais utilisé — l'URL vient du registre —
        // mais sans lui la fiche retomberait sur l'en-tête simple.
        if images[.backdrop] != nil {
            item.backdropImageTags = [itemID]
        }
        if images[.primary] != nil {
            item.imageTags = [ImageType.primary.rawValue: itemID]
        }
        if images[.logo] != nil {
            item.imageTags = (item.imageTags ?? [:]).merging(
                [ImageType.logo.rawValue: itemID],
                uniquingKeysWith: { current, _ in current }
            )
        }

        return item
    }
}

// MARK: - Depuis les items EnhancedFin

extension EnhancedFinSearchItem {

    /// Item synthétique pour un résultat de recherche absent de la bibliothèque.
    ///
    /// Les genres TMDB arrivent en identifiants numériques, pas en noms : on les
    /// laisse de côté plutôt que d'afficher « 18, 80 ». Ils viendront avec
    /// l'enrichissement.
    var syntheticItem: BaseItemDto {
        EnhancedFinSyntheticItem.make(
            mediaKey: mediaKey,
            title: title,
            year: year,
            overview: overview,
            posterURL: posterUrl,
            backdropURL: backdropUrl
        )
    }
}

extension EnhancedFinWatchlistItem {

    var syntheticItem: BaseItemDto {
        EnhancedFinSyntheticItem.make(
            mediaKey: mediaKey,
            title: title,
            year: year,
            posterURL: posterUrl,
            backdropURL: backdropUrl
        )
    }
}

extension EnhancedFinRating {

    var syntheticItem: BaseItemDto {
        EnhancedFinSyntheticItem.make(
            mediaKey: mediaKey,
            title: title,
            year: year,
            posterURL: posterUrl
        )
    }
}

extension EnhancedFinPendingRating {

    var syntheticItem: BaseItemDto {
        EnhancedFinSyntheticItem.make(
            mediaKey: mediaKey,
            title: title,
            year: year,
            posterURL: posterUrl
        )
    }
}
