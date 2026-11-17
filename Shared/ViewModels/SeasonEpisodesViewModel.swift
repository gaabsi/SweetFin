//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// SweetFin : une saison, quelle que soit sa source.
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

/// SweetFin : ce qu'un tap peut faire d'un épisode.
enum EpisodeAvailability {
    /// Un item à lancer est connu.
    case playable
    /// Réponse du serveur pas encore arrivée : ni lisible ni grisé, pas de clignotement.
    case pending
    /// Le serveur ne le propose pas : aucun lecteur ne s'ouvre.
    case unavailable
}

/// SweetFin : un épisode, quelle que soit sa source.
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

    /// SweetFin : pas encore diffusé (date connue, après aujourd'hui). Ni lisible ni
    /// marquable vu.
    var isUpcoming: Bool {
        airDate.map { $0 > .now } ?? false
    }
}

/// SweetFin : saisons et épisodes d'une série, et leur état « vu ».
///
/// Une seule vue pour deux sources, comme la modale d'épisodes du front web :
/// - série **du serveur** : Jellyfin, qui détient aussi l'état vu — le plugin le relit
///   déjà pour « À noter », l'écrire ailleurs ferait deux vérités. TMDB y ajoute les
///   saisons et épisodes absents du serveur, comme sur une fiche de découverte ;
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
    /// SweetFin : épisodes lisibles de la saison ouverte, par numéro (`playable` par
    /// saison), `nil` tant que le serveur n'a pas répondu. Le natif reste prioritaire :
    /// voir `availability(of:)` et `playableItemID(for:)`.
    @Published
    private(set) var playableEpisodes: [Int: EnhancedFinPlayableSeason.Episode]?

    let backend: Backend

    /// SweetFin : la résolution `playable` en cours, annulée au changement de saison.
    private var playableTask: Task<Void, Never>?

    /// Clé EnhancedFin de la série, quel que soit le backend.
    private var mediaKey: String? {
        switch backend {
        case let .jellyfin(_, mediaKey): mediaKey
        case let .enhancedFin(mediaKey): mediaKey
        }
    }

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
            case let .jellyfin(seriesID, mediaKey): try await withMissingSeasons(jellyfinSeasons(seriesID), mediaKey: mediaKey)
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
        startPlayableResolution(season: number)
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

    // MARK: - Lecture

    /// SweetFin : demande au serveur les épisodes lisibles de la saison, **sans
    /// l'attendre** — la feuille s'affiche tout de suite. Même question pour toute
    /// série : le serveur seul décide de ce qui est lisible.
    ///
    /// Parametres :
    /// - number (Int) : numéro de saison
    private func startPlayableResolution(season number: Int) {
        playableTask?.cancel()
        playableEpisodes = nil

        // Rien à demander sans plugin : seuls les épisodes de la médiathèque sont listés.
        guard let mediaKey, let client = userSession?.enhancedFinClient else {
            playableEpisodes = [:]
            return
        }

        playableTask = Task {
            let response = try? await client.playableEpisodes(mediaKey, season: number)

            // Une saison ouverte entre-temps a la priorité : pas d'écrasement tardif.
            guard !Task.isCancelled, selectedSeason == number else { return }
            // Erreur : aucun épisode de plus, plutôt qu'une attente sans fin.
            playableEpisodes = Dictionary(
                (response?.episodes ?? []).map { ($0.episode, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    /// Ce qu'un tap peut faire d'un épisode : lisible s'il a son item Jellyfin, sinon
    /// la liste du serveur décide.
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode de la saison ouverte
    ///
    /// Output :
    /// - availability (EpisodeAvailability) : lisible, en attente du serveur ou non
    func availability(of episode: EpisodeRow) -> EpisodeAvailability {
        if episode.jellyfinID != nil { return .playable }
        guard let playableEpisodes else { return .pending }

        return episode.number.flatMap { playableEpisodes[$0] } == nil ? .unavailable : .playable
    }

    /// L'item à lancer pour un épisode : celui de Jellyfin s'il est déjà là (le natif
    /// reste prioritaire, comme pour les films), sinon celui que le serveur désigne.
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode de la saison ouverte
    ///
    /// Output :
    /// - itemID (String?) : `nil` si la route de l'épisode le donne
    func playableItemID(for episode: EpisodeRow) -> String? {
        episode.jellyfinID ?? episode.number.flatMap { playableEpisodes?[$0]?.itemId }
    }

    /// SweetFin : pour télécharger un épisode lisible **hors médiathèque**, l'item à demander
    /// au serveur au moment du tap (la feuille ne le connaît souvent pas encore : il est
    /// désigné au tap, comme pour la lecture). `nil` pour un épisode du serveur ou pas lisible.
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode de la saison ouverte
    ///
    /// Output :
    /// - resolve ((() async throws -> BaseItemDto)?) : renvoie l'item à télécharger
    func downloadResolver(for episode: EpisodeRow) -> (() async throws -> BaseItemDto)? {
        guard episode.jellyfinID == nil, availability(of: episode) == .playable,
              let mediaKey, let season = selectedSeason, let number = episode.number,
              let client = userSession?.enhancedFinClient
        else { return nil }

        let known = playableItemID(for: episode)
        return {
            let itemID: String? = if let known { known } else {
                try await client.playable(mediaKey, season: season, episode: number).itemId
            }
            guard let itemID else { throw ErrorMessage(ItemStrings.unavailable) }
            return BaseItemDto(id: itemID, type: .episode)
        }
    }

    /// SweetFin : l'épisode tel que la ligne le connaît, pour la fiche provisoire d'un
    /// téléchargement : rangé dans sa série et titré dès le tap, avant la fiche complète.
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode de la saison ouverte
    /// - id (String) : id de l'item à télécharger
    ///
    /// Output :
    /// - item (BaseItemDto) : épisode avec série, saison, numéro et titre
    func provisionalItem(for episode: EpisodeRow, id: String) -> BaseItemDto {
        let seriesID: String? = if case let .jellyfin(seriesID, _) = backend { seriesID } else { nil }
        return BaseItemDto(
            id: id,
            indexNumber: episode.number,
            name: episode.name,
            parentIndexNumber: selectedSeason,
            seriesID: seriesID,
            type: .episode
        )
    }

    /// Lecture d'un épisode, rendue **tout de suite** : le lecteur s'ouvre sur son titre
    /// et résout dedans, par le même chemin qu'une fiche (fiche complète de l'item, puis
    /// son lecteur). Appelé seulement pour un épisode lisible (`availability(of:)`).
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode à lire
    ///
    /// Output :
    /// - provider (MediaPlayerItemProvider) : lecteur de l'item désigné par le serveur
    func playbackProvider(for episode: EpisodeRow) -> MediaPlayerItemProvider {
        let season = selectedSeason

        // De quoi afficher le lecteur le temps que le serveur réponde. Sans item
        // Jellyfin, l'id synthétique de l'épisode (celui de la ligne) : les images ne le
        // demandent pas à Jellyfin.
        var placeholder = BaseItemDto(id: episode.id)
        placeholder.name = episode.name
        placeholder.type = .episode
        placeholder.parentIndexNumber = season
        placeholder.indexNumber = episode.number

        return .playable(placeholder, mediaKey: mediaKey, itemID: playableItemID(for: episode))
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
            case let .jellyfin(_, mediaKey):
                let onServer = targets.filter { $0.jellyfinID != nil }
                let outside = targets.filter { $0.jellyfinID == nil }
                if onServer.isNotEmpty {
                    try await writeJellyfin(onServer, season: season, watched: watched)
                }
                if outside.isNotEmpty, let mediaKey {
                    try await writeEnhancedFin(outside, mediaKey: mediaKey, season: season.number, watched: watched)
                }
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
                // redimensionne sur le serveur, chaque pixel demandé en trop se paie.
                poster: season.imageSource(.primary, environment: ImageSourceOptions(maxWidth: SeasonsLayout.poster.width)),
                episodeCount: count,
                watchedCount: max(0, (count ?? 0) - unplayed),
                jellyfinID: season.id
            )
        }
    }

    private func jellyfinEpisodes(_ season: SeasonRow) async throws -> [EpisodeRow] {
        guard case let .jellyfin(seriesID, mediaKey) = backend else { return [] }
        guard let seasonID = season.jellyfinID else {
            guard let mediaKey else { return [] }
            return try await enhancedFinEpisodes(mediaKey, season: season.number)
        }

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
                thumbnail: episode.imageSource(.primary, environment: ImageSourceOptions(maxWidth: SeasonsLayout.thumbnail.width)),
                airDate: episode.premiereDate,
                // 1 tick = 100 ns.
                runtime: episode.runTimeTicks.map { .ticks($0) },
                isWatched: episode.userData?.isPlayed == true,
                jellyfinID: episode.id
            )
        }

        return await completed(rows, mediaKey: mediaKey, season: season.number)
    }

    /// Ajoute aux saisons du serveur celles que seul TMDB connaît. Les saisons du serveur
    /// gardent leurs données, mais comptent les épisodes qu'il leur manque. Un échec
    /// laisse la liste du serveur.
    ///
    /// Parametres :
    /// - seasons ([SeasonRow]) : saisons Jellyfin
    /// - mediaKey (String?) : clé TMDB de la série
    ///
    /// Output :
    /// - seasons ([SeasonRow]) : saisons complétées, dans l'ordre
    private func withMissingSeasons(_ seasons: [SeasonRow], mediaKey: String?) async -> [SeasonRow] {
        guard let mediaKey, let tmdb = try? await enhancedFinSeasons(mediaKey) else { return seasons }

        let tmdbByNumber = Dictionary(tmdb.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let onServer = Set(seasons.map(\.number))
        let merged = seasons.map { season in
            guard let known = tmdbByNumber[season.number] else { return season }

            return SeasonRow(
                number: season.number,
                name: season.name,
                poster: season.poster,
                episodeCount: max(season.episodeCount ?? 0, known.episodeCount ?? 0),
                watchedCount: max(season.watchedCount, known.watchedCount),
                jellyfinID: season.jellyfinID
            )
        }

        return (merged + tmdb.filter { !onServer.contains($0.number) }).sorted { $0.number < $1.number }
    }

    /// Complète une saison du serveur par TMDB : les durées que Jellyfin n'a pas
    /// (`runTimeTicks` vide) et les épisodes absents du serveur. Correspondance par
    /// numéro d'épisode ; un échec laisse la liste du serveur.
    ///
    /// Parametres :
    /// - rows ([EpisodeRow]) : épisodes Jellyfin
    /// - mediaKey (String?) : clé TMDB de la série
    /// - season (Int) : numéro de saison
    ///
    /// Output :
    /// - rows ([EpisodeRow]) : épisodes complétés, dans l'ordre
    private func completed(_ rows: [EpisodeRow], mediaKey: String?, season: Int) async -> [EpisodeRow] {
        // Les épisodes spéciaux (saison 0) n'existent pas côté plugin.
        guard season > 0,
              let mediaKey,
              let tmdb = try? await enhancedFinEpisodes(mediaKey, season: season)
        else { return rows }

        let runtimes = Dictionary(
            tmdb.compactMap { row in row.number.flatMap { number in row.runtime.map { (number, $0) } } },
            uniquingKeysWith: { first, _ in first }
        )
        let onServer = Set(rows.compactMap(\.number))
        let timed = rows.map { row in
            guard row.runtime == nil, let number = row.number, let runtime = runtimes[number] else { return row }

            var row = row
            row.runtime = runtime
            return row
        }

        return (timed + tmdb.filter { $0.number.map { !onServer.contains($0) } ?? false })
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
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
                name: season.displayName,
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
                id: EnhancedFinSyntheticItem.id(for: mediaKey, season: season, episode: episode.number),
                number: episode.number,
                name: episode.name,
                overview: episode.overview,
                thumbnail: URL.enhancedFinImage(episode.stillUrl).map { ImageSource(url: $0) },
                airDate: episode.airDate.flatMap(DateFormatter.calendarDay.date(from:)),
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
