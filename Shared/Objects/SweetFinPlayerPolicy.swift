//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// SweetFin : les valeurs que le fork impose au lecteur, en un seul endroit.
///
/// Le reste de la politique du lecteur est câblé en dur là où il s'applique : VLC seul
/// (`VideoPlayer`), aperçus trickplay (`MediaPlayerItem.build`), panneau des épisodes
/// seul (`MediaPlayerManager.setSupplements`), gestes (`…+TapGesture`, `…+PanGesture`).
enum SweetFinPlayerPolicy {

    /// Vitesses proposées dans le lecteur.
    static let playbackRates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    /// Ancienneté maximale d'un épisode « à suivre » : 366 jours.
    static let maxNextUp: TimeInterval = 366 * 86400
}
