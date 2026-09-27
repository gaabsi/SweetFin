//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

/// A structure representing a collection of item filters
struct ItemFilterCollection: Hashable, Storable {

    var audioLanguages: [ItemLanguage] = []
    var categories: [ChannelCategory] = []
    var genres: [ItemGenre] = []
    var itemTypes: [BaseItemKind] = []
    var letter: [ItemLetter] = []
    var officialRatings: [ItemOfficialRating] = []
    var sortBy: [ItemSortBy] = [ItemSortBy.sortName]
    var sortOrder: [ItemSortOrder] = [ItemSortOrder.ascending]
    var subtitleLanguages: [ItemLanguage] = []
    var tags: [ItemTag] = []
    var traits: [ItemTrait] = []
    var years: [ItemYear] = []

    var query: String?

    /// The default collection of filters
    static let `default`: ItemFilterCollection = .init()

    static let recent: ItemFilterCollection = .init(
        sortBy: [ItemSortBy.dateCreated],
        sortOrder: [ItemSortOrder.descending]
    )

    var isNotEmpty: Bool {
        self != Self.default
    }

    var hasQueryableFilters: Bool {
        audioLanguages.isNotEmpty ||
            categories.isNotEmpty ||
            genres.isNotEmpty ||
            itemTypes.isNotEmpty ||
            letter.isNotEmpty ||
            officialRatings.isNotEmpty ||
            subtitleLanguages.isNotEmpty ||
            tags.isNotEmpty ||
            traits.isNotEmpty ||
            years.isNotEmpty ||
            !query.isNilOrEmpty
    }
}
