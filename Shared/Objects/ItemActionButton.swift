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
    case favorited
    case trailers
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

    var displayTitle: String {
        switch self {
        case .played:
            L10n.played
        case .favorited:
            L10n.favorited
        case .trailers:
            L10n.trailers
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
        }
    }

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .played:
            "checkmark"
        case .favorited:
            "heart.fill"
        case .trailers:
            "movieclapper"
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
        }
    }

    var secondarySystemImage: String {
        switch self {
        case .favorited:
            "heart"
        case .enhancedFinRating:
            "heart"
        case .enhancedFinWatchlist:
            "bookmark"
        case .enhancedFinFollow:
            "bell"
        default:
            systemImage
        }
    }

    var activeColor: Color? {
        switch self {
        case .played:
            .jellyfinPurple
        case .favorited:
            .pink
        case .enhancedFinRating:
            .orange
        case .enhancedFinWatchlist:
            .teal
        case .enhancedFinFollow:
            .indigo
        default:
            nil
        }
    }

    // Fork : la note et la watchlist prennent la place des favoris et de la
    // lecture dans la barre — ce sont les gestes du quotidien ici. Les autres
    // restent accessibles par le menu, et l'ordre est modifiable dans les réglages.
    static let defaultBarActionButtons: [ItemActionButton] = [
        .enhancedFinRating,
        .enhancedFinWatchlist,
        .enhancedFinFollow,
        .played
    ]

    static let defaultMenuActionButtons: [ItemActionButton] = [
        .favorited,
        .trailers,
        .playback,
        .refresh,
        .subtitles,
        .delete
    ]
        #if os(iOS)
            .prepending(.editMetadata)
        #endif
}
