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

// MARK: - Fiche média

/// Réponse de `GET /media/{mediaKey}`.
///
/// `genres` arrive en **identifiants TMDB numériques**, pas en noms : le plugin ne
/// résout pas encore le libellé. Les afficher tels quels donnerait « 12, 18, 878 »,
/// donc on s'en abstient jusqu'à ce que le serveur expose les noms.
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
