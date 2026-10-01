//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get

/// Client de l'API EnhancedFin — le plugin qui porte les données utilisateur
/// (notes, watchlist, reprise, suivis, calendrier).
///
/// Volontairement séparé du `JellyfinClient` : ce sont deux API distinctes sur
/// le même hôte, avec le même jeton. Les mélanger obligerait à patcher le SDK
/// généré à chaque ajout de route côté plugin.
///
/// Base : `{serveur}/api/EnhancedFin/v1`. Aucune route ne prend d'identifiant
/// utilisateur — l'identité vient du jeton, par construction côté serveur.
final class EnhancedFinClient {

    private let client: APIClient

    init(serverURL: URL, accessToken: String) {
        let baseURL = serverURL.appendingPathComponent("api/EnhancedFin/v1")

        client = APIClient(baseURL: baseURL) { configuration in
            configuration.delegate = EnhancedFinDelegate(accessToken: accessToken)
            configuration.sessionDelegate = EnhancedFinRedirectGuard(serverURL: serverURL)
        }
    }

    // MARK: - Notes

    /// Mes notes, les plus récentes d'abord.
    ///
    /// - Parameters:
    ///   - type: restreint à `movie` ou `tv`. `nil` renvoie les deux.
    ///   - score: restreint à une valeur de note. `nil` les renvoie toutes.
    func ratings(
        type: EnhancedFinMediaType? = nil,
        score: EnhancedFinScore? = nil
    ) async throws -> EnhancedFinList<EnhancedFinRating> {
        var query: [(String, String?)] = []
        if let type { query.append(("type", type.rawValue)) }
        if let score { query.append(("score", String(score.rawValue))) }

        return try await send(Request(path: "me/ratings", query: query.isEmpty ? nil : query))
    }

    /// Les médias vus mais pas encore notés.
    ///
    /// Un film vu suffit ; une série demande 5 épisodes, seuil appliqué côté
    /// serveur.
    func pendingRatings() async throws -> EnhancedFinList<EnhancedFinPendingRating> {
        try await send(Request(path: "me/ratings/pending"))
    }

    /// Note un média. Idempotent : rejouer l'appel écrase la note existante.
    ///
    /// Le média est créé côté serveur s'il est inconnu (peuplement paresseux
    /// depuis TMDB), d'où le `404` possible si TMDB ne le connaît pas non plus.
    func rate(_ mediaKey: String, _ score: EnhancedFinScore) async throws {
        try await send(
            Request(path: "me/ratings/\(escaped(mediaKey))", method: .put, body: RateBody(score: score.rawValue))
        )
    }

    /// Retire ma note. `404` si elle n'existe pas.
    func removeRating(_ mediaKey: String) async throws {
        try await send(Request(path: "me/ratings/\(escaped(mediaKey))", method: .delete))
    }

    // MARK: - Fiche média

    /// Métadonnées d'un média **et** mon état dessus, en un seul appel.
    ///
    /// Lève un ``EnhancedFinProblem`` de statut `404` si le média n'est pas dans le
    /// référentiel — cas normal d'un résultat TMDB jamais noté ni mis en watchlist,
    /// puisque les `GET` ne peuplent jamais.
    ///
    /// - Parameters:
    ///   - detail: ajoute le synopsis et, quand ils existent, le casting, les
    ///     studios et les scénaristes.
    ///   - enrich: fait entrer le média dans le référentiel depuis TMDB s'il n'y
    ///     est pas. Le `404` disparaît alors, sauf si TMDB lui-même l'ignore.
    ///     À réserver aux écrans qui en ont besoin — une fiche ouverte, pas une
    ///     liste — pour ne pas accumuler des fiches jamais touchées.
    func media(
        _ mediaKey: String,
        detail: Bool = false,
        enrich: Bool = false
    ) async throws -> EnhancedFinMedia {
        var query: [(String, String?)] = []
        if detail { query.append(("detail", "true")) }
        if enrich { query.append(("enrich", "true")) }

        return try await send(
            Request(path: "media/\(escaped(mediaKey))", query: query.isEmpty ? nil : query)
        )
    }

    /// L'item à lancer pour un média, s'il est lisible sur le serveur.
    ///
    /// - Parameters:
    ///   - season: saison de l'épisode visé ; `nil` pour l'œuvre entière.
    ///   - episode: numéro de l'épisode visé, toujours avec `season` — le serveur
    ///     refuse l'un sans l'autre.
    func playable(
        _ mediaKey: String,
        season: Int? = nil,
        episode: Int? = nil
    ) async throws -> EnhancedFinPlayable {
        var query: [(String, String?)] = []
        if let season, let episode {
            query.append(("season", String(season)))
            query.append(("episode", String(episode)))
        }

        return try await send(
            Request(path: "media/\(escaped(mediaKey))/playable", query: query.isEmpty ? nil : query)
        )
    }

    /// Les épisodes lisibles d'une saison, en une requête — `GET media/{key}/seasons/{n}/playable`.
    ///
    /// Même question pour toute série, dans la médiathèque ou non : le serveur seul
    /// décide. Un épisode absent de la réponse n'est pas lisible.
    ///
    /// - Parameters:
    ///   - mediaKey: clé de la série.
    ///   - season: numéro de saison.
    func playableEpisodes(_ mediaKey: String, season: Int) async throws -> EnhancedFinPlayableSeason {
        try await send(Request(path: "media/\(escaped(mediaKey))/seasons/\(season)/playable"))
    }

    // MARK: - Personne

    /// Filmographie complète d'une personne, sur le serveur ou non.
    ///
    /// Lève un ``EnhancedFinProblem`` de statut `404` si TMDB ne connaît pas
    /// l'identifiant.
    ///
    /// - Parameter tmdbID: identifiant TMDB de la personne, pas son identifiant
    ///   Jellyfin — les deux n'ont aucun rapport.
    func person(_ tmdbID: Int) async throws -> EnhancedFinPerson {
        try await send(Request(path: "person/\(tmdbID)"))
    }

    // MARK: - Watchlist

    /// Ma watchlist, les ajouts les plus récents d'abord.
    ///
    /// - Parameters:
    ///   - type: restreint à `movie` ou `tv`.
    ///   - genre: identifiant de genre TMDB. Le filtre n'existe que depuis que
    ///     les genres sont une table à part et non un CSV.
    func watchlist(
        type: EnhancedFinMediaType? = nil,
        genre: Int? = nil
    ) async throws -> EnhancedFinList<EnhancedFinWatchlistItem> {
        var query: [(String, String?)] = []
        if let type { query.append(("type", type.rawValue)) }
        if let genre { query.append(("genre", String(genre))) }

        return try await send(Request(path: "me/watchlist", query: query.isEmpty ? nil : query))
    }

    func addToWatchlist(_ mediaKey: String) async throws {
        try await send(Request(path: "me/watchlist/\(escaped(mediaKey))", method: .put))
    }

    func removeFromWatchlist(_ mediaKey: String) async throws {
        try await send(Request(path: "me/watchlist/\(escaped(mediaKey))", method: .delete))
    }

    // MARK: - Reprise

    /// Les lectures en cours connues du plugin.
    ///
    /// ⚠️ **Ne couvre que les sources externes.** La table `playback` n'est nourrie
    /// que par `PUT /me/progress` ; ce que tu regardes sur le serveur Jellyfin n'y
    /// arrive jamais. L'Accueil complète donc cette liste avec `/UserItems/Resume` et
    /// `/Shows/NextUp`, et déduplique l'ensemble par identifiant TMDB.
    ///
    /// - Parameter limit: nombre maximum d'entrées. Le serveur plafonne à 200.
    func continueWatching(limit: Int? = nil) async throws -> EnhancedFinList<EnhancedFinContinueWatching> {
        var query: [(String, String?)] = []
        if let limit { query.append(("limit", String(limit))) }

        return try await send(Request(path: "me/continue-watching", query: query.isEmpty ? nil : query))
    }

    // MARK: - Masquage

    /// Tous les items masqués, les plus récents d'abord (500 au plus, la page max du
    /// plugin).
    func hidden() async throws -> EnhancedFinList<EnhancedFinHiddenItem> {
        try await send(Request(path: "me/hidden"))
    }

    /// Masque un média. Il revient de lui-même dès qu'on le relit.
    func hide(_ mediaKey: String) async throws {
        try await send(Request(path: "me/hidden/\(escaped(mediaKey))", method: .put))
    }

    // MARK: - Seerr

    /// Le statut Seerr d'un média, et de chacune de ses saisons pour une série.
    func seerr(_ mediaKey: String) async throws -> EnhancedFinSeerrDetail {
        try await send(Request(path: "seerr/\(escaped(mediaKey))"))
    }

    /// Demande un média sur Seerr, au nom de l'utilisateur connecté (tiré du jeton par
    /// le plugin, avec ses droits Seerr).
    ///
    /// - Parameter seasons: les saisons voulues pour une série ; ignoré pour un film.
    func requestOnSeerr(_ mediaKey: String, seasons: [Int]) async throws {
        try await send(Request(
            path: "me/requests/\(escaped(mediaKey))",
            method: .post,
            body: SeerrRequestBody(seasons: seasons)
        ))
    }

    // MARK: - SyncPlay

    /// Invite un utilisateur dans mon groupe SyncPlay (l'expéditeur est tiré du jeton).
    ///
    /// Output :
    /// - delivered (Bool) : faux si la personne n'a aucun appareil connecté
    func inviteToSyncPlay(groupID: String, userID: String) async throws -> Bool {
        let response: SyncPlayInviteResponse = try await send(Request(
            path: "syncplay/invite",
            method: .post,
            body: SyncPlayInviteBody(groupId: groupID, userId: userID)
        ))
        return response.delivered
    }

    // MARK: - Calendrier

    /// Les sorties des médias suivis, regroupées par jour.
    ///
    /// - Parameters:
    ///   - from: premier jour, `AAAA-MM-JJ`. Omis, le serveur prend aujourd'hui.
    ///   - to: dernier jour inclus. Omis, quinze jours après ``from``.
    ///     La plage ne peut excéder 366 jours — au-delà le serveur répond `400`.
    func calendar(from: String? = nil, to: String? = nil) async throws -> EnhancedFinCalendar {
        var query: [(String, String?)] = []
        if let from { query.append(("from", from)) }
        if let to { query.append(("to", to)) }

        return try await send(Request(path: "me/calendar", query: query.isEmpty ? nil : query))
    }

    // MARK: - Suivis

    /// Les médias suivis, les ajouts les plus récents d'abord.
    ///
    /// Chaque entrée porte sa prochaine date de diffusion connue, quand il y en a une.
    func follows() async throws -> EnhancedFinList<EnhancedFinFollow> {
        try await send(Request(path: "me/follows"))
    }

    /// Suivre une série : ses prochaines sorties entrent au calendrier.
    func follow(_ mediaKey: String) async throws {
        try await send(Request(path: "me/follows/\(escaped(mediaKey))", method: .put))
    }

    func unfollow(_ mediaKey: String) async throws {
        try await send(Request(path: "me/follows/\(escaped(mediaKey))", method: .delete))
    }

    // MARK: - Tendances

    /// Une page du classement TMDB de la semaine, filtrée côté serveur.
    ///
    /// Le filtre est appliqué par le plugin et non ici : une page TMDB de vingt
    /// items ne contient qu'une à trois séries d'animation, donc filtrer après
    /// réception laisserait le rail « Animés » quasi vide. Le serveur empile les
    /// pages nécessaires.
    ///
    /// - Parameters:
    ///   - filter: vue demandée. ``EnhancedFinTrendingFilter/all`` par défaut.
    ///   - cursor: valeur rendue par l'appel précédent. `nil` repart du début.
    ///     ⚠️ À renvoyer **tel quel** : c'est une page TMDB, pas un rang, et le
    ///     serveur en consomme parfois plusieurs d'un coup.
    func trending(
        filter: EnhancedFinTrendingFilter = .all,
        cursor: Int? = nil
    ) async throws -> EnhancedFinTrendingPage {
        var query: [(String, String?)] = [("filter", filter.rawValue)]
        if let cursor { query.append(("cursor", String(cursor))) }

        return try await send(Request(path: "trending", query: query))
    }

    // MARK: - Recherche

    /// Recherche par titre, fusionnant trois sources : mon référentiel, TMDB et
    /// la bibliothèque Jellyfin.
    ///
    /// `type` omis cherche films **et** séries, comme la recherche du front web.
    /// Une requête vide renvoie une liste vide sans toucher le réseau.
    func search(
        _ query: String,
        type: EnhancedFinMediaType? = nil
    ) async throws -> EnhancedFinList<EnhancedFinSearchItem> {
        // Une requête vide ne vaut pas un aller-retour réseau : la barre de
        // recherche en produit une à chaque effacement.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else {
            return EnhancedFinList(items: [], total: 0)
        }

        var query: [(String, String?)] = [("q", trimmed)]
        if let type { query.append(("type", type.rawValue)) }

        return try await send(Request(path: "search", query: query))
    }

    // MARK: - Saisons et épisodes vus

    /// Saisons d'une série de découverte (TMDB), avec mes épisodes vus.
    func seasons(_ mediaKey: String) async throws -> [EnhancedFinSeason] {
        let response: EnhancedFinSeasons = try await send(
            Request(path: "media/\(escaped(mediaKey))/seasons")
        )
        return response.items
    }

    /// Épisodes d'une saison (TMDB), chacun avec son état vu.
    func season(_ mediaKey: String, number: Int) async throws -> EnhancedFinSeasonDetail {
        try await send(Request(path: "media/\(escaped(mediaKey))/seasons/\(number)"))
    }

    /// Marque ou démarque des épisodes d'une saison, en un appel.
    ///
    /// - Parameters:
    ///   - season: numéro de saison ; `0` pour un film
    ///   - episodes: numéros d'épisodes ; `[0]` pour un film
    ///   - watched: `true` pour marquer vu, `false` pour démarquer
    func setWatched(_ mediaKey: String, season: Int, episodes: [Int], watched: Bool) async throws {
        try await send(
            Request(
                path: "me/watched/\(escaped(mediaKey))",
                method: watched ? .put : .delete,
                body: WatchedBody(season: season, episodes: episodes)
            )
        )
    }

    // MARK: - Envoi

    /// Corps de `PUT` et `DELETE /me/watched/{mediaKey}`.
    private struct WatchedBody: Encodable {
        let season: Int
        let episodes: [Int]
    }

    /// Corps de `PUT /me/ratings/{mediaKey}`.
    ///
    /// En minuscule comme sur le fil. Le serveur tolère les deux casses en
    /// entrée (ASP.NET lie le JSON sans tenir compte de la casse), mais on
    /// reste aligné sur ce que le front existant envoie.
    private struct RateBody: Encodable {
        let score: Int
    }

    /// Corps de `POST /me/requests/{mediaKey}`.
    private struct SeerrRequestBody: Encodable {
        let seasons: [Int]
    }

    /// Corps de `POST /syncplay/invite` (camelCase côté plugin).
    private struct SyncPlayInviteBody: Encodable {
        let groupId: String
        let userId: String
    }

    private struct SyncPlayInviteResponse: Decodable {
        let delivered: Bool
    }

    /// Échappe une clé média avant de l'interpoler dans un chemin d'URL.
    ///
    /// `movie:550` passe brut (vérifié : Jellyfin ne s'offusque pas du `:`), mais la
    /// clé n'est pas toujours une constante du code — elle peut venir d'un
    /// `ProviderId` TMDB lu sur un item du serveur. Une valeur contenant `/`, `?` ou
    /// `#` changerait alors la route appelée au lieu d'être rejetée en 400 par le
    /// serveur, qui est le comportement voulu.
    ///
    /// Le repli sur la valeur brute ne perd rien : c'est exactement ce que le code
    /// faisait avant, et le serveur valide de toute façon le format.
    private func escaped(_ mediaKey: String) -> String {
        mediaKey.addingPercentEncoding(withAllowedCharacters: .enhancedFinMediaKey) ?? mediaKey
    }

    private func send<T: Decodable>(_ request: Request<T>) async throws -> T {
        try await client.send(request).value
    }

    private func send(_ request: Request<Void>) async throws {
        try await client.send(request)
    }
}

// MARK: - Délégué

/// Pose le jeton sur chaque requête, et transforme un statut d'erreur en
/// ``EnhancedFinProblem`` portant le message du serveur.
///
/// Le jeton est posé par requête, et non via
/// `sessionConfiguration.httpAdditionalHeaders` — c'est déjà ce que fait le
/// `JellyfinClient` voisin.
///
/// ⚠️ **Cela ne protège pas d'une redirection.** URLSession recopie les en-têtes de
/// la requête d'origine sur la requête redirigée, `Authorization` compris : la façon
/// de poser l'en-tête n'y change rien. C'est ``EnhancedFinRedirectGuard`` qui s'en
/// charge, et lui seul.
///
/// La validation de réponse est ici pour une autre raison : c'est le seul endroit
/// qui voit à la fois le code HTTP et le corps. Sans elle, `Get` lèverait
/// `APIError.unacceptableStatusCode(400)` et le « score doit valoir -1, 1 ou 2 »
/// rédigé par le serveur serait perdu.
private struct EnhancedFinDelegate: APIClientDelegate {

    let accessToken: String

    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        // Forme moderne, la même que celle du JellyfinClient. Jellyfin accepte aussi
        // X-Emby-Token et X-MediaBrowser-Token (vérifié), mais autant n'en utiliser
        // qu'une.
        request.setValue(
            "MediaBrowser Token=\"\(accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )
    }

    func client(
        _ client: APIClient,
        validateResponse response: HTTPURLResponse,
        data: Data,
        task: URLSessionTask
    ) throws {
        guard !(200 ..< 300).contains(response.statusCode) else { return }

        throw EnhancedFinProblem(
            status: response.statusCode,
            body: try? JSONDecoder().decode(EnhancedFinProblem.Body.self, from: data)
        )
    }
}

// MARK: - Redirections

/// Retire le jeton d'une redirection qui sort du serveur.
///
/// ⚠️ **Sans lui, un `302` emporte le jeton Jellyfin vers l'hôte d'arrivée.**
/// URLSession suit les redirections tout seul et recopie les en-têtes de la requête
/// d'origine sur la suivante ; `Get` laisse passer la proposition telle quelle faute
/// de délégué (`DataLoader.urlSession(_:task:willPerformHTTPRedirection:…)`). Un
/// serveur compromis — ou un intermédiaire, l'app autorisant le HTTP en clair pour
/// les serveurs auto-hébergés — obtiendrait un jeton aux droits complets.
///
/// On ne refuse pas la redirection : un serveur derrière un proxy peut légitimement
/// rediriger chez lui. On retire seulement le jeton quand la destination change
/// d'hôte ou de schéma.
private final class EnhancedFinRedirectGuard: NSObject, URLSessionTaskDelegate {

    private let serverURL: URL

    init(serverURL: URL) {
        self.serverURL = serverURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Même origine = même schéma, même hôte **et même port** : sans le port, un 302
        // vers un autre service de la même machine emportait le jeton.
        let isSameOrigin = request.url?.scheme == serverURL.scheme
            && request.url?.host == serverURL.host
            && request.url?.port == serverURL.port

        guard !isSameOrigin else {
            completionHandler(request)
            return
        }

        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(stripped)
    }
}

// MARK: - Échappement

private extension CharacterSet {

    /// Ce qu'une clé média bien formée contient, et rien de plus : lettres, chiffres
    /// et le `:` séparateur. Tout le reste est encodé.
    static let enhancedFinMediaKey = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":"))
}
