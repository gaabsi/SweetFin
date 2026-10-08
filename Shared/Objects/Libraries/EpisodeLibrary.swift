//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

struct EpisodeLibrary: BaseItemKindLibrary {

    let hasNextPage = false
    let libraryItemTypes: [BaseItemKind] = [.episode]
    let parent: BaseItemDto

    init(season: BaseItemDto) {
        self.parent = season
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        guard let seasonID = parent.id else {
            throw ErrorMessage(L10n.unknownError)
        }

        // SweetFin : saison hors bibliothèque → épisodes TMDB, via le plugin.
        if let mediaKey = EnhancedFinSyntheticItem.mediaKey(from: seasonID), let number = parent.indexNumber {
            guard let client = pageState.userSession.enhancedFinClient else { return [] }
            return try await client.season(mediaKey, number: number).episodes.map {
                EnhancedFinSyntheticItem.makeEpisode(
                    mediaKey: mediaKey,
                    seriesTitle: parent.seriesName,
                    season: number,
                    episode: $0.number,
                    name: $0.name,
                    overview: $0.overview,
                    stillURL: $0.stillUrl,
                    runtimeMinutes: $0.runtime,
                    isPlayed: $0.watched == true
                )
            }
        }

        var parameters = Paths.GetEpisodesParameters()
        parameters.enableUserData = true
        parameters.fields = [.overview]
        parameters.isMissing = false
        parameters.seasonID = seasonID
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getEpisodes(
            seriesID: seasonID,
            parameters: parameters
        )
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }
}
