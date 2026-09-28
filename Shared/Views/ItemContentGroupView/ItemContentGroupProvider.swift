//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Get
import JellyfinAPI
import SwiftUI

// `class` et non `final class` : `ExplorerItemProvider` en hérite pour rendre la
// même vue à partir de données TMDB, sans interroger le serveur.
class ItemContentGroupProvider: ViewModel, ContentGroupProvider {

    @Published
    private(set) var item: BaseItemDto
    @Published
    private(set) var mediaPlayerItemProvider: MediaPlayerItemProvider?
    @Published
    private(set) var randomBackdropItem: BaseItemDto?
    /// SweetFin : vrai tant que `playable` n'a pas répondu pour une fiche sans
    /// lecteur natif — le bouton Lire affiche alors une roue.
    @Published
    private(set) var isResolvingPlayable = false

    /// SweetFin : la résolution `playable` en cours, pour l'annuler au prochain
    /// chargement et pour que `Router.play` puisse l'attendre.
    private var playableTask: Task<Void, Never>?

    @Published
    var isPresentingDeleteConfirmation = false

    let id: String

    var displayTitle: String {
        item.displayTitle
    }

    init(item: BaseItemDto) {
        self.id = item.id ?? "Unknown"
        self.item = item
        super.init()
    }

    init(id: String) {
        self.id = id
        self.item = .init(id: id)
        super.init()
    }

    /// Remplace l'item publié, sans passer par `getFullItem`.
    ///
    /// `item` est `private(set)` : une sous-classe qui construit sa fiche depuis
    /// une autre source (ici TMDB via EnhancedFin) ne peut pas le réassigner, et
    /// l'en-tête d'`ItemView` — qui lit `provider.item` — resterait sur la version
    /// pauvre reçue à l'initialisation.
    func replaceItem(_ newItem: BaseItemDto) {
        item = newItem
    }

    func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        let userSession = try requireUserSession()
        let fullItem = try await item.getFullItem(userSession: userSession, sendNotification: true)
        // SweetFin : lancé avant les `await` qui suivent, pour courir en parallèle.
        async let newEnhancedFinMedia = fetchEnhancedFinMedia(fullItem.enhancedFinMediaKey)
        let newMediaPlayerItemProvider = try await resolveMediaPlayerItemProvider(
            for: fullItem,
            userSession: userSession
        )
        let newRandomBackdropItem = try? await randomBackdropItem(for: fullItem)

        enhancedFinMedia = await newEnhancedFinMedia
        item = fullItem
        mediaPlayerItemProvider = newMediaPlayerItemProvider
        randomBackdropItem = newRandomBackdropItem
        startPlayableResolution(fullItem.enhancedFinMediaKey, userSession: userSession)

        return try await _makeGroups(
            item: fullItem,
            itemID: id
        )
    }

    /// Fork : le bloc état civil d'une personne, extrait de `_makeGroups`.
    ///
    /// `ExplorerPersonProvider` n'appelle pas `_makeGroups` — celui-ci demanderait
    /// au serveur la filmographie d'un identifiant synthétique qu'il ne connaît
    /// pas — mais a besoin de ces trois lignes. Les recopier là-bas les faisait
    /// exister en double.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : item de type `.person`
    ///
    /// Output :
    /// - groups ([any ContentGroup]) : naissance, décès, lieu ; vide pour un média
    static func personContentGroups(for item: BaseItemDto) -> [any ContentGroup] {
        var groups: [any ContentGroup] = []

        if let birthday = item.birthday?.formatted(date: .long, time: .omitted) {
            groups.append(LabeledContentGroup(L10n.born, value: birthday))
        }

        if let deathday = item.deathday?.formatted(date: .long, time: .omitted) {
            groups.append(LabeledContentGroup(L10n.died, value: deathday))
        }

        if let birthplace = item.birthplace {
            groups.append(LabeledContentGroup(L10n.birthplace, value: birthplace))
        }

        return groups
    }

    /// SweetFin : la fiche du plugin (métadonnées TMDB et notes), si elle a pu
    /// être obtenue. Lue par `facts(for:)`.
    var enhancedFinMedia: EnhancedFinMedia?

    /// SweetFin : demande au plugin la fiche détaillée d'un média.
    ///
    /// `enrich` fait entrer le média au référentiel s'il n'y est pas : la demande
    /// vient d'une fiche ouverte, elle est explicite, donc la règle « un GET ne crée
    /// pas de données » tient.
    ///
    /// Parametres :
    /// - mediaKey (String?) : clé EnhancedFin, `nil` pour un item sans équivalent
    ///   (épisode, personne, pas d'identifiant TMDB)
    ///
    /// Output :
    /// - media (EnhancedFinMedia?) : fiche, `nil` sans clé ou si le plugin échoue
    func fetchEnhancedFinMedia(_ mediaKey: String?) async -> EnhancedFinMedia? {
        guard let mediaKey, let client = userSession?.enhancedFinClient else { return nil }

        do {
            return try await client.media(mediaKey, detail: true, enrich: true)
        } catch let problem as EnhancedFinProblem where problem.status == 404 {
            // Inconnu de TMDB : attendu, la fiche garde ce qu'elle a.
            return nil
        } catch {
            logger.warning("EnhancedFin media lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// SweetFin : lance `playable` **sans l'attendre**, pour que la fiche s'affiche
    /// tout de suite ; seul le bouton Lire patiente (roue), puis s'active ou se grise.
    ///
    /// Une résolution précédente est annulée : un rafraîchissement ne doit pas la
    /// laisser écrire par-dessus la nouvelle.
    ///
    /// Parametres :
    /// - mediaKey (String?) : clé EnhancedFin, `nil` pour un item sans équivalent
    /// - userSession (UserSession) : session courante
    func startPlayableResolution(_ mediaKey: String?, userSession: UserSession) {
        playableTask?.cancel()
        isResolvingPlayable = mediaPlayerItemProvider == nil && mediaKey != nil

        playableTask = Task {
            let itemID = await fetchPlayableItemID(mediaKey)
            await usePlayableItem(itemID, userSession: userSession)

            guard !Task.isCancelled else { return }
            isResolvingPlayable = false
        }
    }

    /// SweetFin : attend la résolution `playable` en cours.
    ///
    /// Pour `Router.play`, qui lance la lecture sans ouvrir la fiche et doit donc
    /// attendre le lecteur que la fiche, elle, recevra plus tard.
    func waitForPlayable() async {
        await playableTask?.value
    }

    /// SweetFin : l'item que le serveur désigne comme lisible pour ce média.
    ///
    /// Demandé pour toute fiche, native comme de découverte : la même question
    /// partout, le serveur seul décide. Une erreur vaut « rien à lire » — on grise
    /// le bouton, on ne casse pas la fiche.
    ///
    /// Parametres :
    /// - mediaKey (String?) : clé EnhancedFin, `nil` pour un item sans équivalent
    ///
    /// Output :
    /// - itemID (String?) : identifiant de l'item à lancer, `nil` si rien n'est lisible
    func fetchPlayableItemID(_ mediaKey: String?) async -> String? {
        guard let mediaKey, let client = userSession?.enhancedFinClient else { return nil }

        do {
            return try await client.playable(mediaKey).itemId
        } catch {
            logger.warning("EnhancedFin playable lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// SweetFin : prépare la lecture de l'item désigné par le serveur, **seulement**
    /// si Jellyfin n'a rien fourni pour cette fiche — le lecteur natif reste prioritaire.
    ///
    /// Passe par le même chemin qu'une fiche native (`resolveMediaPlayerItemProvider`),
    /// donc une série se lance sur son épisode à suivre, comme d'habitude.
    ///
    /// Parametres :
    /// - itemID (String?) : item à lancer, `nil` pour ne rien faire
    /// - userSession (UserSession) : session courante
    func usePlayableItem(_ itemID: String?, userSession: UserSession) async {
        guard mediaPlayerItemProvider == nil, let itemID, !Task.isCancelled else { return }

        do {
            let playableItem = try await BaseItemDto(id: itemID).getFullItem(userSession: userSession)
            let provider = try await resolveMediaPlayerItemProvider(for: playableItem, userSession: userSession)

            // Un rechargement a pu passer entre-temps : ne pas écrire par-dessus.
            guard !Task.isCancelled else { return }
            mediaPlayerItemProvider = provider
        } catch {
            logger.warning("EnhancedFin playable item failed: \(error.localizedDescription)")
        }
    }

    /// SweetFin : les données du bloc « infos ».
    ///
    /// Le plugin d'abord, l'item Jellyfin en secours. Pas de secours pour un item
    /// de découverte : il n'a qu'une année, datée au 1er janvier, et mieux vaut
    /// aucun bloc qu'une date fausse.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : item dont on construit la fiche
    ///
    /// Output :
    /// - facts (ItemFacts?) : informations du bloc, `nil` s'il n'y a rien de fiable
    func facts(for item: BaseItemDto) -> ItemFacts? {
        if let enhancedFinMedia {
            return ItemFacts(media: enhancedFinMedia)
        }

        guard !EnhancedFinSyntheticItem.isSynthetic(item.id) else { return nil }

        return ItemFacts(item: item)
    }

    /// SweetFin : d'où viennent les saisons d'une série.
    ///
    /// Série du serveur : Jellyfin, qui détient aussi l'état vu. Série de découverte :
    /// le plugin (TMDB + sa table `playback`).
    ///
    /// Parametres :
    /// - item (BaseItemDto) : la série
    /// - itemID (String) : identifiant de la fiche
    ///
    /// Output :
    /// - backend (SeasonEpisodesViewModel.Backend?) : source, `nil` si aucune
    func seasonsBackend(for item: BaseItemDto, itemID: String) -> SeasonEpisodesViewModel.Backend? {
        if EnhancedFinSyntheticItem.isSynthetic(itemID) {
            return item.enhancedFinMediaKey.map { .enhancedFin(mediaKey: $0) }
        }

        return .jellyfin(seriesID: itemID, mediaKey: item.enhancedFinMediaKey)
    }

    /// SweetFin : la carte « + » des saisons, pour une série du serveur que Seerr
    /// dit incomplète. Jamais sur une série de découverte : elle montre déjà tout TMDB.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : la série
    /// - itemID (String) : identifiant de la fiche
    ///
    /// Output :
    /// - completion (SeasonsContentGroup.Completion?) : `nil` si rien ne manque ou si
    ///   Seerr n'a pas répondu
    func seasonsCompletion(for item: BaseItemDto, itemID: String) -> SeasonsContentGroup.Completion? {
        guard !EnhancedFinSyntheticItem.isSynthetic(itemID),
              enhancedFinMedia?.isIncompleteSeries == true,
              let mediaKey = item.enhancedFinMediaKey
        else { return nil }

        return .init(
            mediaKey: mediaKey,
            poster: item.imageSource(.primary, environment: ImageSourceOptions(maxWidth: 120))
        )
    }

    @ContentGroupBuilder
    func _makeGroups(item: BaseItemDto, itemID: String) async throws -> [any ContentGroup] {

        Self.personContentGroups(for: item)

        // SweetFin : un item de découverte (`enhancedfin:…`) n'existe pas sur le
        // serveur. Les sections qui l'interrogent — épisodes, saisons, bonus,
        // similaires — ne récoltaient qu'un 400 chacune, sans rien afficher.
        let isOnServer = !EnhancedFinSyntheticItem.isSynthetic(itemID)

        // SweetFin : sur iOS, une série n'a plus le rail horizontal de sa saison
        // courante — ses épisodes s'ouvrent depuis `SeasonsContentGroup`, plus bas.
        // Une page de saison garde le sien : elle n'a pas de rail de saisons.
        #if os(tvOS)
        let showsEpisodeRail = item.type == .season || item.type == .series
        #else
        let showsEpisodeRail = item.type == .season
        #endif

        if isOnServer, showsEpisodeRail {
            SeriesEpisodeContentGroup(
                parent: item,
                playButtonItem: mediaPlayerItemProvider?.item
            )
        }

        // SweetFin : date, genres, réalisation et notes, voir
        // `ItemFactsContentGroup`.
        if let facts = facts(for: item), !facts.isEmpty {
            ItemFactsContentGroup(facts: facts)
        }

        // SweetFin : saisons, et leurs épisodes à marquer vus — série du serveur
        // comme de découverte. Voir `SeasonsContentGroup`.
        #if os(iOS)
        if item.type == .series, let backend = seasonsBackend(for: item, itemID: itemID) {
            SeasonsContentGroup(id: itemID, backend: backend, completion: seasonsCompletion(for: item, itemID: itemID))
        }
        #endif

        // SweetFin : pastilles Genres et Studios retirées (iOS et tvOS) : les genres
        // vivent dans le bloc « infos » ci-dessus (`ItemFactsContentGroup`).

        switch item.type {
        case .movie:
            if item.partCount ?? 0 > 1 {
                PosterGroup(
                    id: "additional-parts",
                    library: AdditionalPartsLibrary(itemID: itemID),
                    posterDisplayType: .landscape,
                    posterSize: .small
                )
            }
        case .boxSet, .person, .musicArtist:
            try await ItemTypeContentGroupProvider(
                itemTypes: BaseItemKind.supportedCases
                    .appending(.episode)
                    .appending(.person),
                parent: item
            )
            .makeGroups(environment: .default)
        case .series:
            // SweetFin : remplacé sur iOS par `SeasonsContentGroup`, plus haut.
            #if os(tvOS)
            try await ItemTypeContentGroupProvider(
                itemTypes: [.season],
                parent: item
            )
            .makeGroups(environment: .default)
            #else
            []
            #endif
        case .channel, .liveTvChannel, .tvChannel:
            PosterGroup(
                id: "channel-programs",
                library: ChannelScheduleLibrary(channel: item),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        default: []
        }

        if item.type == .episode {
            PosterGroup(
                library: StaticLibrary(
                    title: L10n.season,
                    id: "seasons",
                    elements: [BaseItemDto(
                        id: item.seasonID,
                        name: item.seasonName,
                        seriesID: item.seriesID,
                        seriesName: item.seriesName,
                        type: .season
                    )]
                ),
                posterSize: .small,
                environment: .init(isHeaderButtonEnabled: false)
            )
        }

        if let castAndCrew = item.mergedPeople, castAndCrew.isNotEmpty {
            PosterGroup(
                id: "cast-and-crew",
                library: StaticLibrary(
                    title: ItemStrings.cast, // SweetFin : « Casting »
                    id: "cast-and-crew",
                    elements: castAndCrew
                ),
                // SweetFin : forme décidée par le thème (ronds par défaut).
                posterDisplayType: Defaults[.appearance].tokens.personPosterShape.displayType,
                posterSize: .small
            )
        }

        if isOnServer {
            PosterGroup(
                id: "special-features",
                library: SpecialFeaturesLibrary(itemID: itemID),
                posterDisplayType: .landscape,
                posterSize: .small
            )
        }

        // Fork : « À propos » ne s'affiche nulle part. Sa carte de description
        // répétait le synopsis déjà en en-tête, et les informations de fichier
        // (codecs, pistes) seront exposées ailleurs — pas sur la fiche.
        //
        // `AboutItemGroup` reste en place, simplement plus émis — et avec lui
        // `ItemOverview` et la route `.itemOverview`, dont il était le seul
        // appelant : le synopsis se déplie maintenant sur place dans
        // `ItemView.Description`. Les trois sont donc du code mort côté fork,
        // laissés intacts pour que le rebase sur l'upstream reste indolore.
    }

    func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = !beforeIsPlayed
        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
        }
    }

    enum PlaybackSelection {
        case mediaSource(MediaSourceInfo?)
        case audioStreamIndex(Int?)
        case subtitleStreamIndex(Int?)
    }

    func select(_ selection: PlaybackSelection) {
        guard let provider = mediaPlayerItemProvider, let userSession else { return }

        var mediaSource = provider.mediaSource
        var audioStreamIndex = provider.audioStreamIndex
        var subtitleStreamIndex = provider.subtitleStreamIndex

        switch selection {
        case let .mediaSource(source):
            mediaSource = source
            audioStreamIndex = nil
            subtitleStreamIndex = nil
        case let .audioStreamIndex(index):
            audioStreamIndex = index
        case let .subtitleStreamIndex(index):
            subtitleStreamIndex = index
        }

        mediaPlayerItemProvider = provider.item.getPlaybackItemProvider(
            userSession: userSession,
            mediaSource: mediaSource,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    private func resolveMediaPlayerItemProvider(
        for item: BaseItemDto,
        userSession: UserSession
    ) async throws -> MediaPlayerItemProvider? {
        let playbackItem: BaseItemDto? = switch item.type {
        case .series:
            if let nextUp = try await nextUpItem(for: item) {
                nextUp
            } else if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }
        case .season:
            if let resumeItem = try await resumeItem(for: item) {
                resumeItem
            } else {
                try await firstAvailableItem(for: item)
            }
        default:
            item.isPlayable ? item : nil
        }

        guard let playbackItem else { return nil }

        let fullPlaybackItem = if item.type == .series || item.type == .season {
            try await playbackItem.getFullItem(userSession: userSession)
        } else {
            playbackItem
        }

        return fullPlaybackItem.getPlaybackItemProvider(userSession: userSession)
    }

    private func nextUpItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetNextUpParameters()
        parameters.seriesID = item.id

        let request = Paths.getNextUp(parameters: parameters)
        let response = try await send(request)

        guard let item = response.value.items?.first, !item.isMissing else {
            return nil
        }

        return item
    }

    private func resumeItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.limit = 1
        parameters.parentID = item.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func firstAvailableItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.episode]
        parameters.isMissing = false
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.parentID = item.id
        parameters.sortOrder = [.ascending]

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func randomBackdropItem(for item: BaseItemDto) async throws -> BaseItemDto? {
        guard item.type == .person || item.type == .musicArtist || item.type == .boxSet else {
            return nil
        }

        var parameters = Paths.GetItemsParameters()
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.sortBy = [.random]
        parameters.userID = try authenticatedUser.id

        switch item.libraryType {
        case .boxSet, .collectionFolder, .userView:
            parameters.parentID = item.id
        case .person:
            parameters.personIDs = item.id.map { [$0] }
        default:
            parameters.parentID = item.id
        }

        let request = Paths.getItems(parameters: parameters)
        let response = try await send(request)

        return response.value.items?.first
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id else { return }

        // SweetFin : un film de découverte n'existe pas sur le serveur, son état vu
        // vit dans le plugin (saison 0, épisode 0).
        if EnhancedFinSyntheticItem.isSynthetic(itemID) {
            guard let mediaKey = item.enhancedFinMediaKey,
                  let client = userSession?.enhancedFinClient
            else { return }

            try await client.setWatched(mediaKey, season: 0, episodes: [0], watched: isPlayed)
            return
        }

        let request: Request<UserItemDataDto> = if isPlayed {
            try Paths.markPlayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        } else {
            try Paths.markUnplayedItem(
                itemID: itemID,
                userID: authenticatedUser.id
            )
        }

        let response = try await send(request)
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}
