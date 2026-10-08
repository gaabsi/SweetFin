//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI

extension LogFile {

    /// SweetFin : télécharge le journal dans un fichier temporaire, pour l'aperçu Quick Look.
    ///
    /// ❌ Avant : une URL avec le jeton admin en paramètre (`queryAPIKey`), ouverte dans
    /// Safari — le jeton finissait dans l'historique. Ici il reste dans l'en-tête. Le nom
    /// vient du serveur : filtré avant de servir de nom de fichier.
    ///
    /// Output :
    /// - file (URL) : le fichier `.txt` écrit dans le dossier temporaire
    func temporaryFile() async throws -> URL {
        guard let client = Container.shared.currentUserSession()?.client else { throw ErrorMessage(L10n.unknownError) }
        let text = try await client.send(Paths.getLogFile(name: name)).value
        let safeName = name.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent((safeName.isEmpty ? "log" : safeName) + ".txt")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    var type: ServerLogType {
        ServerLogType(rawValue: name)
    }
}
