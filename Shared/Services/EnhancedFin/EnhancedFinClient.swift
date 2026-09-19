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

    // MARK: - Suivis

    /// Suivre une série : ses prochaines sorties entrent au calendrier.
    func follow(_ mediaKey: String) async throws {
        try await send(Request(path: "me/follows/\(escaped(mediaKey))", method: .put))
    }

    func unfollow(_ mediaKey: String) async throws {
        try await send(Request(path: "me/follows/\(escaped(mediaKey))", method: .delete))
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

    // MARK: - Envoi

    /// Corps de `PUT /me/ratings/{mediaKey}`.
    ///
    /// En minuscule comme sur le fil. Le serveur tolère les deux casses en
    /// entrée (ASP.NET lie le JSON sans tenir compte de la casse), mais on
    /// reste aligné sur ce que le front existant envoie.
    private struct RateBody: Encodable {
        let score: Int
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
/// **Le jeton est posé par requête, et non via
/// `sessionConfiguration.httpAdditionalHeaders`.** URLSession recopie les en-têtes
/// de session sur la requête redirigée, y compris vers un autre hôte : un serveur
/// qui répondrait par un `302` vers un domaine tiers lui transmettrait le jeton
/// Jellyfin. `client(_:willSendRequest:)` ne s'applique qu'à la requête d'origine.
/// C'est déjà ce que fait le `JellyfinClient` voisin.
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

// MARK: - Échappement

private extension CharacterSet {

    /// Ce qu'une clé média bien formée contient, et rien de plus : lettres, chiffres
    /// et le `:` séparateur. Tout le reste est encodé.
    static let enhancedFinMediaKey = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":"))
}
