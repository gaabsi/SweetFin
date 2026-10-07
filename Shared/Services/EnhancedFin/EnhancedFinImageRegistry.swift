//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import os

/// Images externes associées à un identifiant d'item synthétique.
///
/// Les médias hors bibliothèque sont rendus par `ItemView` via un `BaseItemDto`
/// fabriqué de toutes pièces. Leurs images viennent de TMDB par URL absolue, alors
/// que `BaseItemDto.imageURL()` construit toujours une URL du serveur Jellyfin à
/// partir d'un identifiant et d'un tag.
///
/// Plutôt que de dupliquer les vues natives pour y injecter des URL, on enregistre
/// ici les images sous l'identifiant synthétique : `imageURL()` consulte ce registre
/// en premier, et toute la chaîne d'affichage existante fonctionne sans modification.
///
/// - Note: les entrées ne sont jamais retirées. Elles pèsent quelques dizaines
///   d'octets et la durée de vie d'une session de navigation les rend négligeables ;
///   les retirer exposerait à une image vide si une vue se rafraîchit après coup.
final class EnhancedFinImageRegistry {

    static let shared = EnhancedFinImageRegistry()

    private let state = OSAllocatedUnfairLock(initialState: [String: [ImageType: URL]]())

    private init() {}

    /// Enregistre les images d'un item synthétique.
    ///
    /// Parametres :
    /// - itemID (String) : identifiant synthétique, celui du `BaseItemDto` fabriqué
    /// - images ([ImageType: URL]) : URL absolues, typiquement TMDB
    func register(itemID: String, images: [ImageType: URL]) {
        guard images.isNotEmpty else { return }
        // Fusion : un même item reçoit ses images de plusieurs endroits (une série :
        // affiche par sa fiche, `.thumb` par la tuile d'un de ses épisodes).
        state.withLock { $0[itemID, default: [:]].merge(images) { _, new in new } }
    }

    /// URL externe enregistrée, ou `nil` si l'item n'en a pas — cas de tous les
    /// items réels du serveur.
    func url(for itemID: String, type: ImageType) -> URL? {
        state.withLock { $0[itemID]?[type] }
    }
}
