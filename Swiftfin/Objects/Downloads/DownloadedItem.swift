//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// EnhancedFin : un média téléchargé, tel qu'enregistré dans son dossier (`item.json`).
///
/// Écrit **au lancement** du téléchargement, avant le fichier : hors connexion, c'est la
/// seule source de la fiche (titre, pistes, sous-titres), puisqu'il n'y a plus de serveur.
struct DownloadedItem: Codable, Identifiable {

    /// Fiche complète de l'item au moment du téléchargement.
    let item: BaseItemDto
    /// Source téléchargée : ses pistes servent à la lecture locale.
    let mediaSource: MediaSourceInfo
    /// Nom du fichier média dans le dossier de l'item (`media.mkv`…).
    let fileName: String

    var id: String {
        item.id ?? ""
    }
}

/// EnhancedFin : où en est le téléchargement d'un item.
enum DownloadState: Equatable {

    case none
    case downloading(progress: Double)
    case done
    case failed
}

/// EnhancedFin : ce qui empêche de lancer un téléchargement.
enum DownloadError: LocalizedError {

    case missingSource
    case notEnoughSpace(needed: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .missingSource:
            DownloadStrings.missingSource
        case let .notEnoughSpace(needed, available):
            DownloadStrings.notEnoughSpace(needed: needed, available: available)
        }
    }
}

/// EnhancedFin : position atteinte **sans réseau**, en attente d'envoi à Jellyfin
/// (`progress.json`). Supprimée dès qu'elle est envoyée.
struct DownloadProgress: Codable {

    let positionTicks: Int
    let date: Date
}
