//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import JellyfinAPI

/// « Continuer de regarder » : une seule liste, trois sources.
///
/// L'Accueil de Swiftfin montrait « Continuer » et « Next Up » côte à côte, et une
/// série commencée y apparaissait deux fois. On les fusionne, et on y ajoute les
/// lectures en cours sur les sources externes que le plugin connaît.
///
/// | Source | Route | Ce qu'elle apporte |
/// |---|---|---|
/// | Reprise | `/UserItems/Resume` | épisode ou film commencé, avec sa position |
/// | Épisode suivant | `/Shows/NextUp` | la suite d'une série dont l'épisode est fini |
/// | Externe | `me/continue-watching` | ce qui a été regardé hors de ce serveur |
///
/// ⚠️ **La déduplication se fait par identifiant TMDB, pas par `seriesId`.** Le
/// réflexe est de dédupliquer par série, ce qui suffirait entre les deux routes
/// natives — mais pas avec la source externe, dont les entrées n'ont aucun
/// identifiant Jellyfin. C'est exactement pour ça que media-rating exposait
/// `Resume/ResolveSeriesTmdb`.
struct ContinueWatchingLibrary: BaseItemKindLibrary {

    /// Ce qu'on garde après fusion. Au-delà, le rail devient un inventaire.
    private static let itemLimit = 20

    /// Plafond distinct pour la source externe.
    ///
    /// ⚠️ Sans lui, l'historique migré — des milliers de lignes — noie les reprises
    /// Jellyfin sous des entrées vieilles de deux ans, puisque tout est trié
    /// ensemble par date d'activité.
    private static let externalLimit = 10

    /// Épisodes lus récents interrogés pour dater l'activité des séries
    /// (`seriesActivityDates`).
    private static let recentEpisodesLimit = 100

    let libraryItemTypes: [BaseItemKind] = [.episode, .movie, .video]
    let parent: TitledLibraryParent = .init(
        displayTitle: HomeStrings.continueWatching,
        id: "continue-watching"
    )

    /// ⚠️ Une liste fusionnée puis dédupliquée **ne se pagine pas** : la page 2 de
    /// chaque source ne correspond à rien une fois les doublons retirés.
    let hasNextPage = false

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        // Les trois sources sont indépendantes : les enchaîner tripleraient l'attente
        // avant que le rail s'affiche.
        async let resume = resumeItems(pageState)
        async let nextUp = nextUpItems(pageState)
        async let external = externalItems(pageState)
        async let hiddenDates = hiddenDates(pageState)
        async let seriesActivity = seriesActivityDates(pageState)

        let (resumed, next, externals, hidden, seriesDates) = await (
            resume, nextUp, external, hiddenDates, seriesActivity
        )

        // L'ordre de concaténation EST l'ordre de priorité : être au milieu d'un
        // épisode l'emporte sur en avoir un suivant à proposer, qui l'emporte sur une
        // progression venue d'ailleurs.
        let merged = resumed + next + externals
        let keys = await mediaKeys(for: merged, pageState: pageState)

        let visible = withoutHidden(
            deduplicated(merged, keys: keys),
            keys: keys,
            hidden: hidden,
            seriesDates: seriesDates
        )
        let ordered = stableSorted(visible, seriesDates: seriesDates)

        return Array(ordered.prefix(Self.itemLimit))
    }

    // MARK: - Les trois sources

    /// Une source muette : un rail amputé vaut mieux qu'un écran d'erreur.
    ///
    /// Si `/Shows/NextUp` échoue, on veut toujours voir ses reprises. Seule une panne
    /// des trois donne un rail vide, et le groupe disparaît alors de lui-même.
    private func resumeItems(_ pageState: LibraryPageState) async -> [BaseItemDto] {
        var parameters = Paths.GetResumeItemsParameters()
        parameters.enableUserData = true
        parameters.limit = Self.itemLimit
        parameters.mediaTypes = [.video]
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getResumeItems(parameters: parameters)

        return (try? await pageState.userSession.client.send(request).value.items) ?? []
    }

    private func nextUpItems(_ pageState: LibraryPageState) async -> [BaseItemDto] {
        var parameters = Paths.GetNextUpParameters()
        parameters.enableRewatching = Defaults[.Customization.Home.resumeNextUp]
        parameters.enableUserData = true
        parameters.limit = Self.itemLimit

        let maxNextUp = Defaults[.Customization.Home.maxNextUp]
        if maxNextUp > 0 {
            parameters.nextUpDateCutoff = Date.now.addingTimeInterval(-maxNextUp)
        }

        let request = Paths.getNextUp(parameters: parameters)

        return (try? await pageState.userSession.client.send(request).value.items) ?? []
    }

    /// Les reprises venues des sources externes, converties en items synthétiques.
    ///
    /// ⚠️ **Ces tuiles ne sont pas lisibles dans Swiftfin** : il n'existe pas de
    /// lecteur source externe ou source externe ici. Un tap ouvre la fiche de découverte, et
    /// `PlayButton` se grise tout seul faute de `mediaPlayerItemProvider`. C'est
    /// assumé : savoir où on en est vaut mieux que ne pas voir le média du tout.
    private func externalItems(_ pageState: LibraryPageState) async -> [BaseItemDto] {
        let client = pageState.userSession.enhancedFinClient
        let entries = (try? await client.continueWatching(limit: Self.externalLimit).items) ?? []

        return entries.map(syntheticItem(for:))
    }

    // MARK: - Masquage

    /// Les items masqués (bouton « Masquer » de l'appui long) et leur date de
    /// masquage.
    ///
    /// Un plugin muet ne masque rien : un item masqué qui réapparaît vaut mieux qu'un
    /// rail vide.
    ///
    /// Parametres :
    /// - pageState (LibraryPageState) : la session en cours
    ///
    /// Output :
    /// - hidden ([String: Date]) : clé média → date de masquage
    private func hiddenDates(_ pageState: LibraryPageState) async -> [String: Date] {
        let entries = (try? await pageState.userSession.enhancedFinClient.hidden().items) ?? []

        return entries.reduce(into: [:]) { dates, entry in
            dates[entry.mediaKey] = Self.date(fromISO: entry.hiddenAt)
        }
    }

    /// Retire les items masqués **qui n'ont pas été relus depuis**.
    ///
    /// On masque un média entier : un épisode masqué emporte sa série, et n'importe
    /// quel épisode relu après la fait revenir. Les reprises externes ne sont pas
    /// regardées ici : le plugin les filtre déjà lui-même, avec la même règle.
    ///
    /// Parametres :
    /// - items ([BaseItemDto]) : les items dédupliqués
    /// - keys ([String: String]) : identifiant d'item → clé média
    /// - hidden ([String: Date]) : clé média → date de masquage
    /// - seriesDates ([String: Date]) : série → dernière activité
    ///
    /// Output :
    /// - visible ([BaseItemDto]) : les items à afficher, dans le même ordre
    private func withoutHidden(
        _ items: [BaseItemDto],
        keys: [String: String],
        hidden: [String: Date],
        seriesDates: [String: Date]
    ) -> [BaseItemDto] {
        items.filter { item in
            guard let id = item.id,
                  !EnhancedFinSyntheticItem.isSynthetic(id),
                  let key = keys[id],
                  let hiddenAt = hidden[key]
            else { return true }

            return activityDate(of: item, seriesDates: seriesDates) > hiddenAt
        }
    }

    // MARK: - Activité par série

    /// La dernière activité de chaque série : la lecture de son épisode lu le plus
    /// récemment.
    ///
    /// ⚠️ **Jellyfin ne date jamais la lecture d'une série** (`LastPlayedDate` vide,
    /// même sur une série vue), et un épisode suivant de `/Shows/NextUp` n'a jamais été
    /// lu : sans cette date, tous les « à suivre » tombaient au fond du rail, derrière
    /// les reprises, au lieu d'être mélangés avec elles.
    ///
    /// **Une seule requête** pour toutes les séries : les derniers épisodes lus. Une
    /// série dont la dernière lecture est plus ancienne que ce lot part au fond, ce
    /// qui est de toute façon sa place.
    ///
    /// Parametres :
    /// - pageState (LibraryPageState) : la session en cours
    ///
    /// Output :
    /// - dates ([String: Date]) : identifiant de série → dernière lecture
    private func seriesActivityDates(_ pageState: LibraryPageState) async -> [String: Date] {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.includeItemTypes = [.episode]
        parameters.isRecursive = true
        parameters.limit = Self.recentEpisodesLimit
        parameters.sortBy = [.datePlayed]
        parameters.sortOrder = [.descending]
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let episodes = (try? await pageState.userSession.client.send(request).value.items) ?? []

        // Triés du plus récent au plus ancien : la première date vue par série gagne.
        return episodes.reduce(into: [:]) { dates, episode in
            guard let seriesID = episode.seriesID,
                  dates[seriesID] == nil,
                  let date = episode.userData?.lastPlayedDate
            else { return }

            dates[seriesID] = date
        }
    }

    // MARK: - Résolution des identifiants TMDB

    /// L'identifiant TMDB de chaque item, quand on peut l'obtenir.
    ///
    /// ⚠️ **Un épisode ne porte pas le TMDB de sa série.** `/Shows/NextUp` renvoie des
    /// épisodes, dont les `ProviderIds` sont le plus souvent vides — c'est la série
    /// parente qui porte l'identifiant. Il faut donc aller la chercher.
    ///
    /// Une **seule** requête pour tout le lot, pas une par série.
    ///
    /// Parametres :
    /// - items ([BaseItemDto]) : les items fusionnés, toutes sources confondues
    /// - pageState (LibraryPageState) : la session en cours
    ///
    /// Output :
    /// - keys ([String: String]) : identifiant d'item → clé de dédup
    private func mediaKeys(
        for items: [BaseItemDto],
        pageState: LibraryPageState
    ) async -> [String: String] {
        var keys: [String: String] = [:]
        var seriesToResolve: Set<String> = []

        for item in items {
            guard let id = item.id else { continue }

            // Reprise externe, film ou série : la clé est connue tout de suite. Un épisode
            // n'en a pas (`nil`) et passe par sa série.
            if let key = item.enhancedFinMediaKey {
                keys[id] = key
            } else if let seriesID = item.seriesID {
                seriesToResolve.insert(seriesID)
            }
        }

        guard seriesToResolve.isNotEmpty else { return keys }

        var parameters = Paths.GetItemsParameters()
        parameters.ids = Array(seriesToResolve)
        parameters.fields = [.providerIDs]
        parameters.enableTotalRecordCount = false

        let request = Paths.getItems(parameters: parameters)
        let series = (try? await pageState.userSession.client.send(request).value.items) ?? []

        var seriesKeys: [String: String] = [:]
        for show in series {
            guard let id = show.id, let key = show.enhancedFinMediaKey else { continue }
            seriesKeys[id] = key
        }

        for item in items {
            guard let id = item.id,
                  keys[id] == nil,
                  let seriesID = item.seriesID,
                  let key = seriesKeys[seriesID]
            else { continue }

            keys[id] = key
        }

        return keys
    }

    /// Ne garde qu'un item par clé, le premier rencontré.
    ///
    /// ⚠️ **Un item sans clé n'est jamais fusionné avec un autre item sans clé.** Deux
    /// médias inconnus de TMDB n'ont rien à voir l'un avec l'autre ; les regrouper sous
    /// une clé « vide » en ferait disparaître un. Même précaution que
    /// `ResumeAggregator` côté media-rating, qui leur donnait une clé unique.
    private func deduplicated(_ items: [BaseItemDto], keys: [String: String]) -> [BaseItemDto] {
        var seen: Set<String> = []

        return items.filter { item in
            guard let id = item.id else { return false }
            guard let key = keys[id] else { return true }

            return seen.insert(key).inserted
        }
    }

    // MARK: - Conversions

    /// Date de dernière activité, pour le tri.
    ///
    /// Range les items du plus récemment touché au plus ancien, **à égalité près**.
    ///
    /// ⚠️ **`sorted(by:)` n'est pas stable en Swift** : sans ce départage, deux items à
    /// égalité (sans aucune date, par exemple) changeraient d'ordre d'un chargement à
    /// l'autre.
    ///
    /// Le rang d'origine sert d'arbitre : il porte à la fois l'ordre de pertinence
    /// voulu par chaque source et la priorité entre sources, fixée par l'ordre de
    /// concaténation.
    ///
    /// Parametres :
    /// - items ([BaseItemDto]) : les items fusionnés et dédupliqués
    /// - seriesDates ([String: Date]) : série → dernière activité
    ///
    /// Output :
    /// - sorted ([BaseItemDto]) : les mêmes, du plus récent au plus ancien
    private func stableSorted(_ items: [BaseItemDto], seriesDates: [String: Date]) -> [BaseItemDto] {
        items.enumerated()
            .sorted { left, right in
                let leftDate = activityDate(of: left.element, seriesDates: seriesDates)
                let rightDate = activityDate(of: right.element, seriesDates: seriesDates)

                if leftDate == rightDate { return left.offset < right.offset }

                return leftDate > rightDate
            }
            .map(\.element)
    }

    /// La dernière activité sur le **média** : sa propre lecture, ou pour un épisode
    /// celle de sa série si elle est plus récente — c'est ce qui date un épisode
    /// suivant, jamais lu.
    ///
    /// Les trois sources rangent leur date au même endroit : `userData.lastPlayedDate`.
    /// Un item sans aucune date part au fond plutôt que de disparaître.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : un item du rail
    /// - seriesDates ([String: Date]) : série → dernière activité
    ///
    /// Output :
    /// - date (Date) : `.distantPast` si rien n'est connu
    private func activityDate(of item: BaseItemDto, seriesDates: [String: Date]) -> Date {
        let own = item.userData?.lastPlayedDate ?? .distantPast
        let series = item.seriesID.flatMap { seriesDates[$0] } ?? .distantPast

        return max(own, series)
    }

    /// Fabrique la tuile d'une reprise externe.
    ///
    /// Réutilise ``EnhancedFinSyntheticItem`` et son registre d'images, qui font déjà
    /// tourner les fiches des médias hors serveur — rien de neuf à écrire.
    private func syntheticItem(for entry: EnhancedFinContinueWatching) -> BaseItemDto {
        var item = EnhancedFinSyntheticItem.make(
            mediaKey: entry.mediaKey,
            title: entry.title,
            year: entry.year,
            posterURL: entry.posterUrl,
            backdropURL: entry.backdropUrl
        )

        // `lastPlayedDate` sert au tri, et le range au même endroit que pour les
        // items natifs — une seule règle de tri pour les trois sources.
        //
        // La barre de progression de `PosterButton` lit les deux autres champs. Sans
        // durée, pas de pourcentage possible : la tuile reste sans barre plutôt que
        // d'en afficher une inventée.
        item.userData = UserItemDataDto(
            itemID: item.id,
            key: item.id ?? entry.mediaKey,
            lastPlayedDate: Self.date(fromISO: entry.updatedAt),
            playbackPositionTicks: entry.durationTicks > 0 ? entry.positionTicks : nil,
            playedPercentage: entry.durationTicks > 0 ? entry.progress.map { $0 * 100 } : nil
        )

        if entry.durationTicks > 0 {
            item.runTimeTicks = entry.durationTicks
        }

        return item
    }

    /// Lit une date ISO-8601 **avec ou sans** fraction de seconde.
    ///
    /// ⚠️ Un `ISO8601DateFormatter` est strict : celui qui attend `.withFractionalSeconds`
    /// rejette `2026-09-20T14:00:00Z`, et celui qui ne l'attend pas rejette la forme
    /// avec millisecondes. Le plugin émet les deux selon l'origine de la ligne —
    /// migrée ou écrite par `PUT /me/progress`. D'où les deux essais.
    ///
    /// Un échec n'est pas grave : l'item est alors trié comme le plus ancien, il ne
    /// disparaît pas.
    ///
    /// Parametres :
    /// - value (String) : date ISO-8601
    ///
    /// Output :
    /// - date (Date?) : nil si aucune des deux formes ne correspond
    private static func date(fromISO value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return formatter
    }()
}
