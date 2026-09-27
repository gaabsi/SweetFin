//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum DownloadStrings {

    static let download = "Télécharger"
    static let downloaded = "Téléchargé"
    static let cancelDownload = "Annuler le téléchargement"
    static let deleteDownload = "Supprimer le téléchargement"
    static let retryDownload = "Réessayer le téléchargement"
    static let missingSource = "Aucun fichier à télécharger pour ce média."

    static func downloading(_ progress: Double) -> String {
        "Téléchargement \(Int(progress * 100)) %"
    }

    static func notEnoughSpace(needed: Int64, available: Int64) -> String {
        let format: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return "Pas assez d'espace : \(format(needed)) nécessaires, \(format(available)) disponibles."
    }
}
