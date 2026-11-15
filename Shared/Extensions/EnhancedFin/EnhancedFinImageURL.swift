//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension URL {

    /// Lit une URL d'image renvoyée par le plugin, **hôte vérifié**.
    ///
    /// ⚠️ **Ne jamais passer ces chaînes à `URL(string:)` directement.** Elles
    /// viennent du plugin et, par lui, de TMDB : c'est une donnée distante, pas une
    /// constante du code. `URL(string:)` accepte n'importe quel schéma, `file://`
    /// compris — de quoi faire lire au pipeline d'images un fichier du bac à sable de
    /// l'app et l'afficher.
    ///
    /// Seul `https://image.tmdb.org` passe : c'est le seul hôte que le plugin renvoie,
    /// et le seul tiers annoncé dans la politique de confidentialité. Un plugin
    /// détourné ne peut donc pas faire contacter un autre serveur par l'app.
    ///
    /// Parametres :
    /// - string (String?) : l'URL telle que rendue par le plugin
    ///
    /// Output :
    /// - url (URL?) : l'URL si elle est exploitable, nil sinon
    static func enhancedFinImage(_ string: String?) -> URL? {
        guard let url = string.flatMap(URL.init(string:)),
              url.scheme?.lowercased() == "https",
              url.host()?.lowercased() == "image.tmdb.org"
        else { return nil }

        return url
    }

    /// Même contrôle, pour un **fond plein écran** (fiche, en-tête Seerr) : en plus
    /// grand que la taille rendue par le plugin.
    ///
    /// Le plugin écrit toutes ses URL en `w500` (`TmdbClient.ImageBase`), pensé pour
    /// les tuiles, et elles sont stockées telles quelles en base. Étiré sur une TV 4K,
    /// un fond de 500 px est flou : on change la taille ici, là où l'écran est connu.
    /// Les tuiles gardent `w500` — en `original`, chacune pèserait plusieurs Mo.
    ///
    /// Parametres :
    /// - string (String?) : l'URL telle que rendue par le plugin
    ///
    /// Output :
    /// - url (URL?) : l'URL agrandie si elle est exploitable, nil sinon
    static func enhancedFinBackdrop(_ string: String?) -> URL? {
        guard let url = enhancedFinImage(string) else { return nil }

        #if os(tvOS)
        let size = "original"
        #else
        let size = "w1280"
        #endif

        // Seul le chemin change : l'hôte, déjà vérifié, reste le même.
        let resized = url.absoluteString.replacingOccurrences(of: "/t/p/w500/", with: "/t/p/\(size)/")
        return URL(string: resized) ?? url
    }
}
