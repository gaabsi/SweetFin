//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension URL {

    /// Lit une URL d'image renvoyée par le plugin, **schéma vérifié**.
    ///
    /// ⚠️ **Ne jamais passer ces chaînes à `URL(string:)` directement.** Elles
    /// viennent du plugin et, par lui, de TMDB : c'est une donnée distante, pas une
    /// constante du code. `URL(string:)` accepte n'importe quel schéma, `file://`
    /// compris — de quoi faire lire au pipeline d'images un fichier du bac à sable de
    /// l'app et l'afficher.
    ///
    /// `http` reste accepté : l'application doit joindre des serveurs auto-hébergés
    /// en clair, et le refuser ici casserait les installations sans TLS.
    ///
    /// Parametres :
    /// - string (String?) : l'URL telle que rendue par le plugin
    ///
    /// Output :
    /// - url (URL?) : l'URL si elle est exploitable, nil sinon
    static func enhancedFinImage(_ string: String?) -> URL? {
        guard let url = string.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }

        return url
    }
}
