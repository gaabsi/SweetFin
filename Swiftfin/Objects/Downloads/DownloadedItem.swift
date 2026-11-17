//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// SweetFin : un média téléchargé, tel qu'enregistré dans son dossier (`item.json`).
///
/// Écrit **au lancement** du téléchargement, avant le fichier : hors connexion, c'est la
/// seule source de la fiche (titre, pistes, sous-titres), puisqu'il n'y a plus de serveur.
struct DownloadedItem: Codable, Identifiable {

    /// Fiche complète de l'item au moment du téléchargement.
    var item: BaseItemDto
    /// Source téléchargée : ses pistes servent à la lecture locale.
    let mediaSource: MediaSourceInfo
    /// Nom du fichier média dans le dossier de l'item (`media.mkv`…).
    let fileName: String
    /// SweetFin : clé TMDB de l'œuvre (`movie:550`, `tv:95479`), pour un item hors
    /// médiathèque : sa progression hors ligne part au plugin sous cette clé.
    let mediaKey: String?
    /// SweetFin : nom du dossier du téléchargement, posé à la relecture du disque (pas
    /// enregistré : le dossier fait foi). Id stable, même hors médiathèque, où l'id de
    /// l'item est un identifiant temporaire du serveur (le dossier porte alors l'id de la fiche).
    var storageID: String?

    private enum CodingKeys: String, CodingKey {
        case item, mediaSource, fileName, mediaKey
    }

    /// L'identifiant du téléchargement (dossier, état, affiche, progression locale).
    var id: String {
        storageID ?? item.id ?? ""
    }

    /// SweetFin : item hors médiathèque, que Jellyfin ne connaît pas (ni progression ni
    /// position à échanger avec lui).
    var isOutsideLibrary: Bool {
        mediaKey != nil
    }

    /// SweetFin : la série d'un épisode (clé TMDB hors médiathèque, id Jellyfin sinon),
    /// pour regrouper ses épisodes ; `nil` pour un film.
    var seriesKey: String? {
        guard item.type == .episode else { return nil }
        return mediaKey ?? item.seriesID ?? item.seriesName
    }

    /// SweetFin : rang d'un épisode dans sa série (saison, épisode).
    var episodeOrder: (Int, Int) {
        (item.parentIndexNumber ?? 0, item.indexNumber ?? 0)
    }

    /// SweetFin : durée du fichier téléchargé, à défaut celle de la fiche.
    var runtimeTicks: Int? {
        [mediaSource.runTimeTicks, item.runTimeTicks].compactMap(\.self).first { $0 > 0 }
    }

    /// SweetFin : part regardée, entre 0 et 1 ; `nil` si rien d'entamé ou déjà vu.
    var progress: Double? {
        guard item.userData?.isPlayed != true,
              let position = item.userData?.playbackPositionTicks, position > 0,
              let runtime = runtimeTicks
        else { return nil }

        return min(Double(position) / Double(runtime), 1)
    }
}

/// SweetFin : où en est le téléchargement d'un item.
enum DownloadState: Equatable {

    case none
    /// Fiche complète demandée au serveur, fichier pas encore lancé.
    case preparing
    case downloading(progress: Double)
    case done
    case failed
}

/// SweetFin : ce qui empêche de lancer un téléchargement.
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

/// SweetFin : position atteinte en lisant un téléchargement, en attente d'envoi au serveur
/// (`progress.json`). Supprimée dès qu'elle est envoyée.
struct DownloadProgress: Codable {

    let positionTicks: Int
    let date: Date
}
