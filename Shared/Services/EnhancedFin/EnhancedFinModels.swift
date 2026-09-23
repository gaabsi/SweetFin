//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - Enveloppe

/// Enveloppe commune des réponses de liste d'EnhancedFin : `{ items, total }`.
///
/// Miroir du `ListResponse<T>` côté plugin. Les sept domaines de l'API sortent
/// sous cette forme.
struct EnhancedFinList<Item: Decodable>: Decodable {

    let items: [Item]
    let total: Int
}

// MARK: - Notes

/// Une note, telle que renvoyée par `GET /me/ratings`.
///
/// Les noms de propriétés reproduisent **exactement** le fil : le plugin
/// sérialise avec `PropertyNamingPolicy = null`, donc pas de conversion de casse
/// à espérer d'un côté ni de l'autre.
///
/// `ratedAt` reste une `String` plutôt qu'une `Date` volontairement : une date
/// au format inattendu ferait échouer le décodage de **toute la liste**, alors
/// qu'ici elle ne casse que l'affichage d'un item.
struct EnhancedFinRating: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let score: Int
    let ratedAt: String
    let title: String
    let year: Int?
    let posterUrl: String?

    /// Sert à la fiche : sans image de fond, `ItemView` retombe sur son en-tête
    /// simple avant même que l'enrichissement ait eu lieu.
    let backdropUrl: String?
    let inLibrary: Bool
    let jellyfinId: String?

    var id: String { mediaKey }
}

/// Un média vu mais pas encore noté — `GET /me/ratings/pending`.
///
/// Forme distincte d'``EnhancedFinRating`` : côté serveur les deux routes ne
/// renvoient pas les mêmes champs, et on décrit le fil tel qu'il est.
struct EnhancedFinPendingRating: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let mediaType: String
    let title: String
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let watchedEpisodes: Int
    let lastWatchedAt: String
    let inLibrary: Bool
    let jellyfinId: String?

    var id: String { mediaKey }
}

/// Les trois seules valeurs acceptées par `PUT /me/ratings/{mediaKey}`.
///
/// Le serveur renvoie `400` pour toute autre valeur : ce type rend l'erreur
/// impossible à commettre depuis l'app.
enum EnhancedFinScore: Int, CaseIterable, Hashable {

    case disliked = -1
    case liked = 1
    case loved = 2
}

// MARK: - Watchlist

/// Une entrée de watchlist — `GET /me/watchlist`.
struct EnhancedFinWatchlistItem: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let addedAt: String
    let mediaType: String
    let title: String
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    /// Ma note sur ce média, s'il est déjà noté.
    let rating: Int?
    let inLibrary: Bool
    let jellyfinId: String?

    /// Identifiants de genre TMDB, qui permettent de répartir la watchlist en
    /// catégories sans la redemander au serveur.
    ///
    /// Optionnel bien que le serveur l'émette toujours : le rendre obligatoire
    /// ferait échouer le décodage de **toute la liste** le jour où il cesserait de
    /// l'émettre, alors qu'ici son absence ne coûte qu'un classement par défaut.
    let genreIds: [Int]?

    var id: String { mediaKey }
}

// MARK: - Recherche

/// Un résultat de `GET /search`.
///
/// Les trois origines (référentiel local, TMDB, bibliothèque seule) partagent ce
/// type ; les champs propres à TMDB sont donc optionnels.
struct EnhancedFinSearchItem: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let mediaType: String
    /// Optionnel bien que le serveur l'émette toujours : personne ne le lit côté
    /// app, et le rendre obligatoire ferait échouer le décodage de **toute la
    /// liste** le jour où le serveur cesserait de l'émettre.
    let tmdbId: Int?
    let title: String
    let originalTitle: String?
    let year: Int?
    let releaseDate: String?
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let genreIds: [Int]?

    /// Présent dans mon référentiel (noté, vu, en watchlist…).
    ///
    /// Indépendant de ``inLibrary`` : un film noté peut avoir quitté la
    /// bibliothèque, un film présent peut n'avoir jamais été touché.
    ///
    /// Optionnel pour la même raison que ``tmdbId`` : aucun écran ne le lit.
    let known: Bool?

    /// Le fichier est sur ce serveur, donc lisible immédiatement.
    let inLibrary: Bool
    let jellyfinId: String?

    let me: EnhancedFinSearchItemMe

    var id: String { mediaKey }
}

/// Mon état sur un résultat de recherche.
struct EnhancedFinSearchItemMe: Decodable, Hashable {

    let rating: Int?
    let inWatchlist: Bool
    let following: Bool
}

/// Les deux seuls types de média manipulés par l'API.
///
/// Le préfixe de `mediaKey` n'est pas décoratif : TMDB a des espaces d'ID
/// séparés, donc `movie:550` et `tv:550` désignent deux œuvres sans rapport.
enum EnhancedFinMediaType: String, CaseIterable, Hashable {

    case movie
    case tv

    /// Type déduit du préfixe d'une clé média.
    ///
    /// Toutes les routes ne renvoient pas `mediaType` — `GET /me/ratings` ne le
    /// porte pas — alors que la clé, elle, est toujours là et commence par le type.
    /// La déduire ici évite de répéter le test de préfixe à chaque point d'usage,
    /// et faisait qu'une série notée s'affichait avec l'icône « film ».
    ///
    /// Parametres :
    /// - mediaKey (String) : clé au format `'{movie|tv}:{tmdb_id}'`
    init?(mediaKey: String) {
        guard let prefix = mediaKey.split(separator: ":", maxSplits: 1).first,
              let type = EnhancedFinMediaType(rawValue: String(prefix))
        else { return nil }

        self = type
    }

    /// Symbole SF de ce type, celui qu'utilisent les tuiles sans affiche.
    var systemImage: String {
        switch self {
        case .movie: "film"
        case .tv: "tv"
        }
    }
}

// MARK: - Tendances

/// Les quatre vues du classement TMDB de la semaine.
///
/// ``all`` est le défaut, comme sur le front web : c'est la seule qui ordonne films
/// et séries **entre eux**, le classement étant commun. Les trois autres sont des
/// découpes de ce même classement, appliquées côté serveur.
enum EnhancedFinTrendingFilter: String, CaseIterable, Identifiable, Hashable {

    case all
    case movie
    case tv
    /// Série d'animation. Un film d'animation reste dans ``movie`` — c'est la règle
    /// du front web, et celle que les gens ont en tête.
    case anime

    var id: String { rawValue }
}

/// Une page de tendances — `GET /trending`.
///
/// Pas de `total` : le classement n'a pas de cardinalité connue, et ``nextCursor``
/// porte la seule information utile. Absent, il n'y a plus rien à charger.
///
/// ⚠️ ``nextCursor`` désigne une **page TMDB**, pas un rang. Le serveur en consomme
/// parfois plusieurs pour remplir un filtre rare, d'où des sauts de cinq d'un appel
/// à l'autre. Le renvoyer tel quel est la seule façon de reprendre au bon endroit.
struct EnhancedFinTrendingPage: Decodable {

    let items: [EnhancedFinSearchItem]
    let nextCursor: Int?
}

// MARK: - Suivis

/// Un média suivi — `GET /me/follows`.
///
/// Suivre un média fait entrer ses sorties au calendrier. La liste n'avait jusqu'ici
/// aucun écran : on pouvait suivre depuis une fiche, mais pas voir ce qu'on suivait.
struct EnhancedFinFollow: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let addedAt: String
    let mediaType: String
    let title: String
    let year: Int?
    let posterUrl: String?

    /// Prochaine diffusion connue, au format `AAAA-MM-JJ`.
    ///
    /// ⚠️ **Nulle** pour une série terminée, ou dont la suite n'est pas encore
    /// annoncée — ce qui est fréquent. Le dire explicitement vaut mieux qu'une ligne
    /// qui semble incomplète.
    let nextAirDate: String?

    /// Le fichier est sur ce serveur : la fiche native est ouvrable.
    ///
    /// Rendus depuis la correction de `GET /me/follows` côté plugin — c'était la
    /// seule route de liste à ne pas les porter.
    let inLibrary: Bool
    let jellyfinId: String?

    var id: String { mediaKey }
}

// MARK: - Reprise

/// Une lecture en cours — `GET /me/continue-watching`.
///
/// ⚠️ **Cette route ne voit PAS ce que Jellyfin sait.** Elle lit la seule table
/// `playback` du plugin, alimentée par `PUT /me/progress`, que rien n'appelle
/// aujourd'hui — elle ne contient donc que l'historique migré des **sources
/// externes** (source externe, source externe). La reprise côté serveur vient, elle, des
/// routes Jellyfin natives.
///
/// C'est pour ça que l'Accueil fusionne trois sources plutôt qu'une, et que la
/// fusion déduplique par identifiant TMDB : un même média peut être en cours des
/// deux côtés, avec des identifiants qui n'ont aucun rapport entre eux.
struct EnhancedFinContinueWatching: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let mediaType: String
    let title: String
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?

    /// `0` pour un film : le serveur range les films en `season 0, episode 0`.
    let season: Int
    let episode: Int

    let positionTicks: Int
    let durationTicks: Int

    /// Avancement, déjà calculé et arrondi par le serveur. Absent quand la durée
    /// est inconnue — on ne peut alors pas dessiner de barre de progression.
    let progress: Double?

    /// Dernière activité, ISO-8601. Reste une `String` : une date au format
    /// inattendu ferait échouer le décodage de **toute** la liste.
    let updatedAt: String

    var id: String { mediaKey }
}

// MARK: - Calendrier

/// Réponse de `GET /me/calendar`.
///
/// Les sorties sont **déjà regroupées par jour et triées** par le serveur : le front
/// JS faisait ce travail lui-même, et il aurait fallu le réécrire en Swift puis une
/// troisième fois pour tvOS.
struct EnhancedFinCalendar: Decodable {

    /// La plage réellement couverte, renvoyée en écho. Le client qui pagine sait ainsi
    /// ce qu'il a obtenu sans recalculer ses bornes.
    let from: String
    let to: String

    let days: [EnhancedFinCalendarDay]
}

/// Les sorties d'un jour.
struct EnhancedFinCalendarDay: Decodable, Hashable, Identifiable {

    /// Jour au format `AAAA-MM-JJ`, tel que le serveur l'émet.
    let date: String

    let releases: [EnhancedFinRelease]

    var id: String { date }
}

/// Une sortie : un épisode, ou un film le jour de sa sortie.
struct EnhancedFinRelease: Decodable, Hashable, Identifiable {

    let mediaKey: String
    let mediaType: String

    /// ⚠️ Valent **0 pour un film** : le serveur stocke sa sortie en saison 0 /
    /// épisode 0, pour que le calendrier n'ait pas à distinguer les deux. Ne jamais
    /// formater « S0E00 » — tester ``mediaType`` d'abord.
    let season: Int
    let episode: Int

    /// Nul pour un film, dont ``title`` porte déjà le nom.
    let episodeName: String?

    let title: String
    let posterUrl: String?
    let inLibrary: Bool
    let jellyfinId: String?

    /// ⚠️ La clé média ne suffit pas : une série sort souvent plusieurs épisodes le
    /// même jour, et deux identifiants identiques feraient disparaître des lignes
    /// d'un `ForEach`.
    var id: String { "\(mediaKey)|\(season)|\(episode)" }

    /// Le type, lu par ``EnhancedFinMediaType`` plutôt que comparé en chaîne brute —
    /// une faute de frappe sur `"movie"` ne se verrait qu'à l'écran, et la clé est la
    /// source qui ne ment pas : `mediaType` n'est pas rendu par toutes les routes.
    var isMovie: Bool {
        EnhancedFinMediaType(mediaKey: mediaKey) == .movie
    }
}

// MARK: - Fiche média

/// Réponse de `GET /media/{mediaKey}`.
///
/// `genres` porte les **identifiants TMDB numériques**, `genreNames` les libellés,
/// que le serveur résout désormais depuis son référentiel. Les deux listes sortent
/// dans le même ordre, celui de `genre_id` — c'est `genreNames` qu'on affiche,
/// `genres` restant pour le front JS historique.
struct EnhancedFinMedia: Decodable, Hashable {

    let mediaKey: String
    let mediaType: String
    let tmdbId: Int
    let title: String
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let logoUrl: String?
    let genres: [Int]?

    /// Noms des genres, résolus par le serveur depuis son référentiel TMDB.
    ///
    /// Peut être plus courte que ``genres`` : un genre dont le nom n'a jamais été
    /// vu est écarté plutôt que rendu comme un trou. L'ordre, lui, est le même.
    let genreNames: [String]?

    /// Note TMDB sur 10. Absente quand personne n'a voté : le serveur ne stocke
    /// pas un 0 qui se lirait comme un mauvais film.
    let voteAverage: Double?

    /// Nombre de votes TMDB, qui qualifie ``voteAverage`` — un 9,2 sur douze votes
    /// ne vaut pas un 8,1 sur quarante mille. Décodé sans être encore affiché.
    let voteCount: Int?
    let me: EnhancedFinMediaMe
    let detail: EnhancedFinMediaDetail?
}

/// Mon état sur un média.
struct EnhancedFinMediaMe: Decodable, Hashable {

    let rating: Int?
    let inWatchlist: Bool
    let following: Bool
    let hidden: Bool
}

/// Champs disponibles seulement avec `?detail=true`.
///
/// Tous facultatifs : un média peuplé paresseusement depuis TMDB n'a souvent que
/// son synopsis, le casting n'étant renseigné que par la migration ou un
/// rafraîchissement.
struct EnhancedFinMediaDetail: Decodable, Hashable {

    let overview: String?

    /// Les vingt premiers rôles, dans l'ordre d'affiche de TMDB.
    let cast: [EnhancedFinCastMember]?

    private enum CodingKeys: String, CodingKey {
        case overview
        case cast
    }

    /// Décodage écrit à la main pour **isoler** le casting.
    ///
    /// Le serveur filtre désormais les castings hérités de l'ancien plugin, mais on
    /// ne veut pas que ce filtre soit la seule protection : un casting illisible ne
    /// doit jamais faire tomber son parent. Décodé par l'init synthétisé, un seul
    /// `id` en chaîne faisait échouer ``EnhancedFinMediaDetail``, donc
    /// ``EnhancedFinMedia`` en entier — la fiche perdait logo, image de fond,
    /// genres, note et synopsis, sans aucun message.
    ///
    /// `try?` ici et pas ailleurs : c'est le seul champ dont l'absence est
    /// préférable à l'échec.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        cast = try? container.decodeIfPresent([EnhancedFinCastMember].self, forKey: .cast)
    }
}

/// Un rôle du casting.
struct EnhancedFinCastMember: Decodable, Hashable, Identifiable {

    let id: Int
    let name: String?
    let character: String?
    let profileUrl: String?
}

// MARK: - Personne

/// Une personne et sa filmographie complète — `GET /person/{tmdbId}`.
///
/// Rien n'est stocké côté serveur : la réponse est construite à la demande depuis
/// TMDB, enrichie de ce que porte la bibliothèque et de mon état.
struct EnhancedFinPerson: Decodable, Hashable {

    let tmdbId: Int
    let name: String
    let profileUrl: String?
    let biography: String?

    /// Dates au format `AAAA-MM-JJ`, telles que TMDB les rend.
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?

    let credits: [EnhancedFinPersonCredit]
    let total: Int
}

/// Un média auquel la personne a participé.
struct EnhancedFinPersonCredit: Decodable, Hashable, Identifiable, EnhancedFinPosterItem {

    let mediaKey: String
    let mediaType: String
    let title: String
    let year: Int?
    let posterUrl: String?

    /// Le personnage joué, ou le poste occupé pour l'équipe technique.
    let role: String?

    let inLibrary: Bool
    let jellyfinId: String?
    let rating: Int?

    /// Score TMDB. Renvoyé par le serveur pour que le tri par popularité se fasse
    /// sur la donnée réelle, sans nouvel appel.
    let popularity: Double

    var id: String { mediaKey }

    var posterRatingScore: Int? { rating }

    /// Le rôle prime sur l'année : sur une filmographie, savoir *ce qu'il y jouait*
    /// est plus utile que la date, déjà donnée par l'ordre chronologique.
    var subtitle: String? { role ?? year.map(String.init) }
}

// MARK: - Erreurs

/// Erreur renvoyée par le plugin.
///
/// `status` vient toujours de la réponse HTTP ; `title` et `detail` du corps
/// `ProblemDetails` (RFC 7807) quand le serveur en fournit un — ce qui est le cas
/// de toutes les erreurs métier, via le helper `problem()` du controller de base.
///
/// Les champs `success` et `message` présents sur le fil sont ignorés : ils
/// n'existent que pour la compatibilité du front JS et sont voués à disparaître.
struct EnhancedFinProblem: Error, Hashable, LocalizedError {

    let status: Int
    let title: String?
    let detail: String?

    /// Ce que verra l'utilisateur. Le `detail` du serveur est déjà rédigé pour
    /// être lisible (« score doit valoir -1, 1 ou 2 »), autant s'en servir.
    var errorDescription: String? {
        detail ?? title ?? "EnhancedFin: HTTP \(status)"
    }

    /// Corps `ProblemDetails`, décodé séparément : tous ses champs sont
    /// facultatifs, donc il ne peut pas servir de type d'erreur à lui seul —
    /// un JSON quelconque s'y décoderait avec des `nil` partout.
    struct Body: Decodable {
        let title: String?
        let detail: String?
    }

    init(status: Int, body: Body? = nil) {
        self.status = status
        self.title = body?.title
        self.detail = body?.detail
    }
}
