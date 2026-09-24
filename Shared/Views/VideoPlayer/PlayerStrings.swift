//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres au lecteur du fork.
///
/// Hors de `L10n`, pour la même raison que `HomeStrings` : `L10n` est généré depuis les
/// fichiers de traduction upstream, qui entreraient en conflit à chaque rebase.
enum PlayerStrings {

    static let jumpBackward = "Reculer"
    static let jumpForward = "Avancer"

    /// L'icône pile : ouvre le panneau des épisodes.
    static let episodes = "Épisodes"
    static let settings = "Réglages"
    /// La piste audio, dans l'engrenage.
    static let language = "Langue"

    // Réglages du lecteur
    static let audioAndSubtitles = "Audio & Sous-titres"
    static let preferredAudioLanguage = "Langue audio préférée"
    static let preferredSubtitleLanguage = "Langue des sous-titres préférée"

    // Écran de pause
    static let endsAt = "Se termine à"

    static func watched(percent: Int) -> String {
        "\(percent) % regardé"
    }
}
