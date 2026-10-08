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

    /// Identifiant synthétique d'un média, d'une de ses saisons ou d'un épisode.
    ///
    /// Saison et épisode ont le leur (`enhancedfin:tv:95479/s1`, `…/s1e3`) : le
    /// registre d'images est indexé par identifiant, et la vignette d'un épisode ne
    /// doit pas remplacer l'affiche de la série.
    ///
    /// Parametres :
    /// - mediaKey (String) : clé '{movie|tv}:{tmdb_id}'
    /// - season (Int?) : saison, `nil` pour le média
    /// - episode (Int?) : numéro de l'épisode, avec `season`
    ///
    /// Output :
    /// - id (String) : identifiant synthétique
    static func id(for mediaKey: String, season: Int? = nil, episode: Int? = nil) -> String {
        switch (season, episode) {
        case let (season?, episode?): "\(idPrefix)\(mediaKey)/s\(season)e\(episode)"
        case let (season?, nil): "\(idPrefix)\(mediaKey)/s\(season)"
        default: idPrefix + mediaKey
        }
    }

    static func isSynthetic(_ itemID: String?) -> Bool {
        itemID?.hasPrefix(idPrefix) ?? false
    }

    /// Lecture inverse de ``id(for:season:episode:)`` : la clé du **média**, épisode
    /// compris.
    ///
    /// Le type est validé, pas seulement le préfixe retiré : une personne synthétique
    /// (`enhancedfin:person:{id}`) donnerait sinon la clé `person:6384`, que le
    /// serveur rejette.
    ///
    /// Parametres :
    /// - itemID (String?) : identifiant d'un item, synthétique ou non
    ///
    /// Output :
    /// - mediaKey (String?) : clé EnhancedFin, `nil` si l'item n'est pas un média synthétique
    static func mediaKey(from itemID: String?) -> String? {
        guard let itemID, isSynthetic(itemID) else { return nil }

        let key = String(itemID.dropFirst(idPrefix.count).prefix { $0 != "/" })
        return EnhancedFinMediaType(mediaKey: key) == nil ? nil : key
    }

    /// Le format d'un id de personne, écrit une seule fois.
    private static let personPrefix = idPrefix + "person:"

    /// Identifiant synthétique d'une personne.
    ///
    /// Ce format était écrit à la main à quatre endroits, dont un qui le **produit**
    /// et un autre qui le **relit**. Un décalage entre les deux n'aurait produit
    /// aucune erreur de compilation : juste une fiche vide, au hasard.
    ///
    /// Parametres :
    /// - tmdbID (Int) : identifiant TMDB de la personne
    ///
    /// Output :
    /// - id (String) : identifiant synthétique
    static func personID(for tmdbID: Int) -> String {
        personPrefix + String(tmdbID)
    }

    /// Lecture inverse de ``personID(for:)``.
    ///
    /// Parametres :
    /// - itemID (String) : identifiant d'un item, synthétique ou non
    ///
    /// Output :
    /// - tmdbID (Int?) : identifiant TMDB, `nil` si l'item n'est pas une personne
    ///   synthétique
    static func personTmdbID(from itemID: String) -> Int? {
        guard itemID.hasPrefix(personPrefix) else { return nil }

        return Int(itemID.dropFirst(personPrefix.count))
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
    /// - rating (Double?) : note TMDB sur 10
    /// - cast ([EnhancedFinCastMember]?) : rôles, dans l'ordre d'affiche
    /// - isPlayed (Bool) : marqué vu dans le plugin
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
        genres: [String]? = nil,
        rating: Double? = nil,
        cast: [EnhancedFinCastMember]? = nil,
        isPlayed: Bool = false
    ) -> BaseItemDto {
        let itemID = id(for: mediaKey)

        var images: [ImageType: URL] = [:]
        if let url = URL.enhancedFinImage(posterURL) { images[.primary] = url }
        if let url = URL.enhancedFinImage(backdropURL) { images[.backdrop] = url }
        if let url = URL.enhancedFinImage(logoURL) { images[.logo] = url }

        EnhancedFinImageRegistry.shared.register(itemID: itemID, images: images)

        var item = BaseItemDto(id: itemID)
        item.name = title
        item.overview = overview
        item.productionYear = year

        // `MetadataHStack` lit `premiereDateYear`, dérivé de `premiereDate` et non
        // de `productionYear` : sans cette date l'année n'apparaît pas sous le logo.
        // Seule l'année est affichée, le 1er janvier est donc sans conséquence.
        item.premiereDate = year.flatMap {
            Calendar.current.date(from: DateComponents(year: $0, month: 1, day: 1))
        }
        item.genres = genres
        item.communityRating = rating.map(Float.init)
        item.people = cast.map(people(from:))
        item.type = EnhancedFinMediaType(mediaKey: mediaKey) == .tv ? .series : .movie
        // Lu par le bouton natif « Marquer comme vu » du menu : sans `userData`,
        // `toggleIsPlayed` ne saurait pas dans quel état est le film.
        item.userData = UserItemDataDto(isPlayed: isPlayed, itemID: itemID, key: itemID)

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

    /// Fabrique la saison d'une série hors bibliothèque, pour les vues natives des
    /// saisons (panneau Épisodes du lecteur).
    ///
    /// Parametres :
    /// - mediaKey (String) : clé de la série
    /// - seriesTitle (String?) : titre de la série, transmis à ses épisodes
    /// - season (EnhancedFinSeason) : la saison, d'après TMDB
    ///
    /// Output :
    /// - item (BaseItemDto) : saison synthétique
    static func makeSeason(mediaKey: String, seriesTitle: String?, season: EnhancedFinSeason) -> BaseItemDto {
        let itemID = id(for: mediaKey, season: season.number)
        if let poster = URL.enhancedFinImage(season.posterUrl) {
            EnhancedFinImageRegistry.shared.register(itemID: itemID, images: [.primary: poster])
        }

        var item = BaseItemDto(id: itemID)
        item.type = .season
        item.name = season.displayName
        item.indexNumber = season.number
        item.seriesID = id(for: mediaKey)
        item.seriesName = seriesTitle
        return item
    }

    /// Fabrique l'épisode d'une série hors bibliothèque, rendu comme un épisode du
    /// serveur (nom de la série, SxEy, nom de l'épisode).
    ///
    /// Images, par le même chemin que le natif :
    /// - une **tuile** (rail `.isThumb`) montre l'image de sa série : `seriesID` pointe
    ///   la série synthétique, dont le fond est enregistré en `.thumb` ;
    /// - une **carte d'épisode** (panneau du lecteur) montre sa vignette, `.primary`.
    ///
    /// Parametres :
    /// - mediaKey (String) : clé de la série
    /// - seriesTitle (String?) : titre de la série
    /// - season (Int) : saison
    /// - episode (Int) : numéro de l'épisode
    /// - name (String?) : nom de l'épisode
    /// - overview (String?) : synopsis
    /// - stillURL (String?) : vignette TMDB de l'épisode
    /// - backdropURL (String?) : fond TMDB de la série
    /// - runtimeMinutes (Int?) : durée
    /// - isPlayed (Bool) : vu
    ///
    /// Output :
    /// - item (BaseItemDto) : épisode synthétique prêt à être affiché
    static func makeEpisode(
        mediaKey: String,
        seriesTitle: String?,
        season: Int,
        episode: Int,
        name: String?,
        overview: String? = nil,
        stillURL: String? = nil,
        backdropURL: String? = nil,
        runtimeMinutes: Int? = nil,
        isPlayed: Bool = false
    ) -> BaseItemDto {
        let itemID = id(for: mediaKey, season: season, episode: episode)
        let seriesID = id(for: mediaKey)

        // Validée une fois : l'étiquette d'image ci-dessous ne vaut que pour une URL acceptée.
        let backdrop = URL.enhancedFinImage(backdropURL)
        if let backdrop {
            EnhancedFinImageRegistry.shared.register(itemID: seriesID, images: [.thumb: backdrop, .backdrop: backdrop])
        }
        let still = URL.enhancedFinImage(stillURL)
        if let still {
            EnhancedFinImageRegistry.shared.register(itemID: itemID, images: [.primary: still])
        }

        var item = BaseItemDto(id: itemID)
        item.type = .episode
        item.seriesID = seriesID
        item.seriesName = seriesTitle
        item.seriesThumbImageTag = backdrop == nil ? nil : seriesID
        item.name = name ?? seriesTitle
        item.overview = overview
        item.parentIndexNumber = season
        item.indexNumber = episode
        item.runTimeTicks = runtimeMinutes.map { Duration.minutes($0).ticks }
        item.userData = UserItemDataDto(isPlayed: isPlayed, itemID: itemID, key: itemID)
        if still != nil {
            item.imageTags = [ImageType.primary.rawValue: itemID]
        }
        return item
    }

    /// Convertit le casting en `BaseItemPerson`, pour que la section « Distribution »
    /// native s'affiche sans qu'on écrive de vue.
    ///
    /// Les portraits suivent le même chemin que les affiches : enregistrés dans
    /// ``EnhancedFinImageRegistry`` sous un identifiant synthétique propre à la
    /// personne, puis servis par `BaseItemDto.imageURL()` sans qu'elle sache d'où
    /// ils viennent.
    ///
    /// Parametres :
    /// - cast ([EnhancedFinCastMember]) : rôles renvoyés par le plugin
    ///
    /// Output :
    /// - people ([BaseItemPerson]) : distribution prête à afficher
    private static func people(from cast: [EnhancedFinCastMember]) -> [BaseItemPerson] {
        cast.map { member in
            let personID = personID(for: member.id)

            if let url = URL.enhancedFinImage(member.profileUrl) {
                EnhancedFinImageRegistry.shared.register(
                    itemID: personID,
                    images: [.primary: url]
                )
            }

            var person = BaseItemPerson(id: personID, name: member.name)
            person.role = member.character
            person.type = .actor

            // Le tag n'est jamais lu — l'URL vient du registre — mais son absence
            // ferait considérer la personne comme dépourvue d'image.
            if member.profileUrl != nil {
                person.primaryImageTag = personID
            }

            return person
        }
    }
}

// MARK: - Depuis les items EnhancedFin

extension EnhancedFinPosterItem {

    /// Item synthétique d'un média absent de la bibliothèque.
    ///
    /// Le protocole déclare déjà tout ce que `make` demande — clé, titre, année,
    /// affiche, image large — d'où une implémentation unique. Les cinq corps
    /// concrets qui la précédaient étaient identiques à un champ près, et chaque
    /// champ ajouté à l'item synthétique demandait cinq modifications.
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

extension EnhancedFinSearchItem {

    /// Seul type à s'écarter du défaut : `/search` est la seule route qui renvoie
    /// un synopsis, et c'est celle dont les résultats s'ouvrent sur une fiche qui
    /// n'a encore rien d'autre à afficher.
    ///
    /// Les genres n'y sont pas repris : `genreIds` porte des identifiants TMDB
    /// numériques, pas des noms. Ils arrivent avec l'enrichissement de la fiche.
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

// MARK: - Personne

extension EnhancedFinSyntheticItem {

    /// Fabrique le `BaseItemDto` d'une personne, pour que `ItemView` rende sa fiche.
    ///
    /// `ItemContentGroupProvider` sait déjà présenter une personne : date de
    /// naissance, décès, lieu. On lui donne donc un item de type `.person` plutôt
    /// que d'écrire une vue.
    ///
    /// Parametres :
    /// - person (EnhancedFinPerson) : fiche renvoyée par le plugin
    ///
    /// Output :
    /// - item (BaseItemDto) : personne synthétique prête à être affichée
    static func makePerson(_ person: EnhancedFinPerson) -> BaseItemDto {
        let itemID = personID(for: person.tmdbId)

        if let url = URL.enhancedFinImage(person.profileUrl) {
            EnhancedFinImageRegistry.shared.register(itemID: itemID, images: [.primary: url])
        }

        var item = BaseItemDto(id: itemID)
        item.name = person.name
        item.overview = person.biography
        item.type = .person
        // Pour une personne, Jellyfin range la date de naissance dans `premiereDate`
        // et la mort dans `endDate` — `birthday` et `deathday` n'en sont que des
        // lectures conditionnées par `type == .person`.
        item.premiereDate = person.birthday.flatMap(DateFormatter.calendarDay.date(from:))
        item.endDate = person.deathday.flatMap(DateFormatter.calendarDay.date(from:))
        item.productionLocations = person.placeOfBirth.map { [$0] }

        if person.profileUrl != nil {
            item.imageTags = [ImageType.primary.rawValue: itemID]
        }

        return item
    }

    /// Item minimal d'une personne, le temps que sa fiche arrive.
    ///
    /// La navigation part au doigt levé, donc `ItemView` a besoin d'un item avant
    /// que le serveur ait répondu. Celui-ci porte le nom — déjà connu — et le type,
    /// dont dépend la mise en page.
    ///
    /// Fabriquer un `BaseItemDto` n'est pas l'affaire d'une route : le format de
    /// l'identifiant synthétique se décide ici, et nulle part ailleurs.
    ///
    /// Parametres :
    /// - person (BaseItemPerson) : la personne sur laquelle on vient d'appuyer
    ///
    /// Output :
    /// - item (BaseItemDto) : item provisoire, remplacé dès la fiche reçue
    static func makePersonPlaceholder(_ person: BaseItemPerson) -> BaseItemDto {
        var item = BaseItemDto(id: person.id ?? personPrefix + "inconnu")
        item.name = person.name
        item.type = .person

        return item
    }
}
