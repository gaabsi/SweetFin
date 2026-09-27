//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum ItemActionButton: String, CaseIterable, Displayable, Equatable, Identifiable, Storable, SystemImageable {

    case played
    case playback
    case subtitles
    case refresh
    case delete
    #if os(iOS)
    case editMetadata
    #endif

    // Fork : actions EnhancedFin. Disponibles seulement si l'item a une clé
    // EnhancedFin, c'est-à-dire un identifiant TMDB et un type représentable.
    case enhancedFinRating
    case enhancedFinWatchlist
    case enhancedFinFollow
    #if os(iOS)
    case download
    #endif

    var displayTitle: String {
        switch self {
        case .played:
            L10n.played
        case .playback:
            L10n.playback
        case .refresh:
            L10n.refreshMetadata
        case .subtitles:
            L10n.subtitles
        case .delete:
            L10n.delete
        #if os(iOS)
        case .editMetadata:
            L10n.edit
        #endif
        case .enhancedFinRating:
            ExplorerStrings.rate
        case .enhancedFinWatchlist:
            ExplorerStrings.watchlistButton
        case .enhancedFinFollow:
            ExplorerStrings.follow
        #if os(iOS)
        case .download:
            DownloadStrings.download
        #endif
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .played:
            "checkmark"
        case .playback:
            "list.and.film"
        case .refresh:
            "arrow.clockwise"
        case .subtitles:
            "captions.bubble"
        case .delete:
            "trash"
        #if os(iOS)
        case .editMetadata:
            "pencil"
        #endif
        case .enhancedFinRating:
            "heart.fill"
        case .enhancedFinWatchlist:
            "bookmark.fill"
        case .enhancedFinFollow:
            "bell.fill"
        #if os(iOS)
        case .download:
            "arrow.down.circle.fill"
        #endif
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .enhancedFinRating:
            "heart"
        case .enhancedFinWatchlist:
            "bookmark"
        case .enhancedFinFollow:
            "bell"
        #if os(iOS)
        case .download:
            "arrow.down.circle"
        #endif
        default:
            systemImage
        }
    }

    var activeColor: Color? {
        switch self {
        case .played:
            .jellyfinPurple
        case .enhancedFinRating:
            .orange
        case .enhancedFinWatchlist:
            .teal
        case .enhancedFinFollow:
            .indigo
        #if os(iOS)
        case .download:
            .green
        #endif
        default:
            nil
        }
    }

    // EnhancedFin : les boutons de la fiche sont **imposés**, pas réglables (lus par
    // `ItemActionButtons.Configuration`). Barre : les trois gestes du quotidien.
    static let barButtons: [ItemActionButton] = [
        .enhancedFinRating,
        .enhancedFinWatchlist,
        .enhancedFinFollow,
    ]

    // EnhancedFin : menu « ⋯ » court — modifier, marquer comme vu, télécharger (le
    // téléchargement n'existe que sur iPhone). Favoris, bandes-annonces, versions,
    // actualiser, sous-titres et supprimer n'y sont plus.
    static let menuButtons: [ItemActionButton] = {
        #if os(iOS)
        [.editMetadata, .played, .download]
        #else
        [.played]
        #endif
    }()
}
