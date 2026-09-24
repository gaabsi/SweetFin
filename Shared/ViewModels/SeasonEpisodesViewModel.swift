//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// EnhancedFin : une saison, quelle que soit sa source.
struct SeasonRow: Identifiable, Hashable {

    let number: Int
    let name: String
    let poster: ImageSource?
    let episodeCount: Int?
    var watchedCount: Int

    /// Jellyfin seulement : l'item saison, pour la marquer vue en un appel.
    let jellyfinID: String?

    var id: Int { number }
}

/// EnhancedFin : un épisode, quelle que soit sa source.
struct EpisodeRow: Identifiable, Hashable {

    let id: String
    let number: Int?
    let name: String?
    let overview: String?
    let thumbnail: ImageSource?
    let airDate: Date?
    var runtime: Duration?
    var isWatched: Bool

    /// Jellyfin seulement : l'item épisode, pour le marquer vu.
    let jellyfinID: String?
}

/// EnhancedFin : saisons et épisodes d'une série, et leur état « vu ».
///
/// Une seule vue pour deux sources, comme la modale d'épisodes du front web :
/// - série **du serveur** : Jellyfin, qui détient aussi l'état vu — le plugin le relit
///   déjà pour « À noter », l'écrire ailleurs ferait deux vérités ;
/// - série **de découverte** : TMDB via le plugin, état vu dans sa table `playback`.
///
/// La vue ne lit que ``SeasonRow`` et ``EpisodeRow`` : elle ignore d'où ils viennent.
final class SeasonEpisodesViewModel: ViewModel, WithRefresh {

    enum Backend {
        /// `mediaKey` : clé TMDB de la série, pour compléter ce que Jellyfin n'a pas.
        case jellyfin(seriesID: String, mediaKey: String?)
        case enhancedFin(mediaKey: String)
    }

    @Published
    private(set) var seasons: [SeasonRow] = []
    @Published
    private(set) var episodes: [EpisodeRow] = []
    @Published
    private(set) var selectedSeason: Int?
    @Published
    private(set) var isLoadingEpisodes = false
    @Published
    private(set) var error: Error?

    let backend: Backend

    init(backend: Backend) {
        self.backend = backend
        super.init()
    }

    // MARK: - Chargement

    func refresh() {
        Task { await refresh() }
    }

    /// Charge la liste des saisons. Silencieux en cas d'échec : le rail disparaît.
    func refresh() async {
        do {
            seasons = switch backend {
            case let .jellyfin(seriesID, _): try await jellyfinSeasons(seriesID)
            case let .enhancedFin(mediaKey): try await enhancedFinSeasons(mediaKey)
            }
        } catch {
            logger.warning("Seasons failed: \(error.localizedDescription)")
        }
    }

    /// Ouvre une saison : ses épisodes remplacent ceux affichés.
    ///
    /// Parametres :
    /// - number (Int) : numéro de saison
    func select(season number: Int) async {
        guard let season = seasons.first(where: { $0.number == number }) else { return }

        selectedSeason = number
        isLoadingEpisodes = true
        // Une saison abandonnée ne coupe pas l'indicateur de celle qui charge.
        defer {
            if selectedSeason == number { isLoadingEpisodes = false }
        }

        do {
            let loaded = switch backend {
            case .jellyfin: try await jellyfinEpisodes(season)
            case let .enhancedFin(mediaKey): try await enhancedFinEpisodes(mediaKey, season: number)
            }
            // Une saison ouverte entre-temps a la priorité : pas d'écrasement tardif.
            guard selectedSeason == number else { return }
            episodes = loaded
            error = nil
        } catch {
            guard selectedSeason == number else { return }
            episodes = []
            self.error = error
        }
    }

    // MARK: - Vu / non vu

    /// Marque ou démarque des épisodes de la saison ouverte.
    ///
    /// Optimiste : l'écran change tout de suite. En cas d'échec, on **recharge** la
    /// saison plutôt que de tout annuler : une partie des appels a pu réussir, et seul
    /// le serveur sait laquelle.
    ///
    /// Parametres :
    /// - ids (Set<String>) : épisodes visés ; ceux déjà dans l'état voulu sont ignorés
    /// - watched (Bool) : vrai pour marquer vu
    func setWatched(_ ids: Set<String>, watched: Bool) async {
        let targets = episodes.filter { ids.contains($0.id) && $0.isWatched != watched }
        guard targets.isNotEmpty,
              let season = seasons.first(where: { $0.number == selectedSeason })
        else { return }

        apply(targets, watched: watched)

        do {
            switch backend {
            case .jellyfin:
                try await writeJellyfin(targets, season: season, watched: watched)
            case let .enhancedFin(mediaKey):
                try await writeEnhancedFin(targets, mediaKey: mediaKey, season: season.number, watched: watched)
            }
        } catch {
            logger.warning("Set watched failed: \(error.localizedDescription)")
            await select(season: season.number)
        }
    }

    /// Reporte l'état sur les épisodes et le compteur de la saison ouverte.
    private func apply(_ targets: [EpisodeRow], watched: Bool) {
        let ids = Set(targets.map(\.id))
        for index in episodes.indices where ids.contains(episodes[index].id) {
            episodes[index].isWatched = watched
        }

        if let index = seasons.firstIndex(where: { $0.number == selectedSeason }) {
            seasons[index].watchedCount = episodes.count(where: \.isWatched)
        }
    }

    // MARK: - Jellyfin

    private func jellyfinSeasons(_ seriesID: String) async throws -> [SeasonRow] {
        var parameters = Paths.GetSeasonsParameters()
        parameters.userID = try authenticatedUser.id
        parameters.isMissing = false
        parameters.enableUserData = true
        parameters.fields = [.childCount]

        let items = try await send(Paths.getSeasons(seriesID: seriesID, parameters: parameters)).value.items ?? []

        return items.map { season in
            let count = season.childCount
            // Jellyfin compte les non-vus : les vus s'en déduisent.
            let unplayed = season.userData?.unplayedItemCount ?? count ?? 0

            return SeasonRow(
                number: season.indexNumber ?? 0,
                name: season.displayTitle,
                // En points : `imageURL` multiplie par la densité d'écran. Jellyfin
                // redimensionne sur le Pi, chaque pixel demandé en trop se paie.
                poster: season.imageSource(.primary, environment: ImageSourceOptions(maxWidth: 120)),
                episodeCount: count,
                watchedCount: max(0, (count ?? 0) - unplayed),
                jellyfinID: season.id
            )
        }
    }

    private func jellyfinEpisodes(_ season: SeasonRow) async throws -> [EpisodeRow] {
        guard let seasonID = season.jellyfinID, case let .jellyfin(seriesID, mediaKey) = backend else { return [] }

        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = try authenticatedUser.id
        parameters.seasonID = seasonID
        parameters.isMissing = false
        parameters.enableUserData = true
        parameters.fields = [.overview]

        let items = try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).value.items ?? []

        let rows = items.map { episode in
            EpisodeRow(
                id: episode.id ?? UUID().uuidString,
                number: episode.indexNumber,
                name: episode.name,
                overview: episode.overview,
                thumbnail: episode.imageSource(.primary, environment: ImageSourceOptions(maxWidth: 128)),
                airDate: episode.premiereDate,
                // 1 tick = 100 ns.
                runtime: episode.runTimeTicks.map { .nanoseconds($0 * 100) },
                isWatched: episode.userData?.isPlayed == true,
                jellyfinID: episode.id
            )
        }

        return await withTMDBRuntimes(rows, mediaKey: mediaKey, season: season.number)
    }

    /// Complète les durées que Jellyfin n'a pas, par celles de TMDB.
    ///
    /// ⚠️ Un `.strm` n'est qu'un lien : Jellyfin ne peut pas le sonder, il n'a donc
    /// pas de `runTimeTicks` (vécu sur Frieren). Un seul appel au plugin, pour la
    /// saison entière, et seulement s'il manque quelque chose. Correspondance par
    /// numéro d'épisode ; un échec laisse les durées telles quelles.
    ///
    /// Parametres :
    /// - rows ([EpisodeRow]) : épisodes Jellyfin
    /// - mediaKey (String?) : clé TMDB de la série
    /// - season (Int) : numéro de saison
    ///
    /// Output :
    /// - rows ([EpisodeRow]) : les mêmes, durées complétées quand TMDB les connaît
    private func withTMDBRuntimes(_ rows: [EpisodeRow], mediaKey: String?, season: Int) async -> [EpisodeRow] {
        guard rows.contains(where: { $0.runtime == nil }),
              let mediaKey,
              let client = userSession?.enhancedFinClient,
              let tmdb = try? await client.season(mediaKey, number: season)
        else { return rows }

        let runtimes = Dictionary(
            tmdb.episodes.compactMap { episode in episode.runtime.map { (episode.number, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        return rows.map { row in
            guard row.runtime == nil, let number = row.number, let minutes = runtimes[number] else { return row }

            var row = row
            row.runtime = .seconds(minutes * 60)
            return row
        }
    }

    /// Une saison entièrement cochée se marque en un appel sur l'item saison, que
    /// Jellyfin répercute sur ses épisodes — comme le `markSeason` du front web.
    private func writeJellyfin(_ targets: [EpisodeRow], season: SeasonRow, watched: Bool) async throws {
        let wholeSeason = watched && episodes.allSatisfy(\.isWatched)

        let itemIDs = if wholeSeason, let seasonID = season.jellyfinID {
            [seasonID]
        } else {
            targets.compactMap(\.jellyfinID)
        }

        let requests = try itemIDs.map { itemID in
            watched
                ? try Paths.markPlayedItem(itemID: itemID, userID: authenticatedUser.id)
                : try Paths.markUnplayedItem(itemID: itemID, userID: authenticatedUser.id)
        }

        // En parallèle : un appel par épisode, qui s'enchaînaient un à un.
        try await withThrowingTaskGroup(of: UserItemDataDto.self) { group in
            for request in requests {
                group.addTask { try await self.send(request).value }
            }

            for try await userData in group {
                Notifications[.itemUserDataDidChange].post(userData)
            }
        }
    }

    // MARK: - EnhancedFin

    private func enhancedFinSeasons(_ mediaKey: String) async throws -> [SeasonRow] {
        guard let client = userSession?.enhancedFinClient else { return [] }

        return try await client.seasons(mediaKey).map { season in
            SeasonRow(
                number: season.number,
                name: season.name ?? "\(L10n.season) \(season.number)",
                poster: URL.enhancedFinImage(season.posterUrl).map { ImageSource(url: $0) },
                episodeCount: season.episodeCount,
                watchedCount: season.watchedCount ?? 0,
                jellyfinID: nil
            )
        }
    }

    private func enhancedFinEpisodes(_ mediaKey: String, season: Int) async throws -> [EpisodeRow] {
        guard let client = userSession?.enhancedFinClient else { return [] }

        return try await client.season(mediaKey, number: season).episodes.map { episode in
            EpisodeRow(
                id: "\(season)-\(episode.number)",
                number: episode.number,
                name: episode.name,
                overview: episode.overview,
                thumbnail: URL.enhancedFinImage(episode.stillUrl).map { ImageSource(url: $0) },
                airDate: episode.airDate.flatMap(EnhancedFinSyntheticItem.day),
                runtime: episode.runtime.map { .seconds($0 * 60) },
                isWatched: episode.watched == true,
                jellyfinID: nil
            )
        }
    }

    private func writeEnhancedFin(_ targets: [EpisodeRow], mediaKey: String, season: Int, watched: Bool) async throws {
        guard let client = userSession?.enhancedFinClient else { return }

        try await client.setWatched(mediaKey, season: season, episodes: targets.compactMap(\.number), watched: watched)
    }
}
