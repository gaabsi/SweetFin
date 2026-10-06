//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Libellés propres au lecteur, hors de `L10n` comme tous ceux du fork (voir `ExplorerStrings`).
enum PlayerStrings {

    /// Lecture lancée depuis une tuile, quand le serveur n'a finalement rien à lire.
    static let nothingToPlay = String(localized: "Nothing to play for this media", table: "SweetFin")

    static let jumpBackward = String(localized: "Jump Back", table: "SweetFin")
    static let jumpForward = String(localized: "Jump Forward", table: "SweetFin")

    /// L'icône pile : ouvre le panneau des épisodes.
    static let episodes = String(localized: "Episodes", table: "SweetFin")
    static let settings = String(localized: "Settings", table: "SweetFin")
    /// La piste audio, dans l'engrenage.
    static let language = String(localized: "Language", table: "SweetFin")

    // Réglages du lecteur
    static let audioAndSubtitles = String(localized: "Audio & Subtitles", table: "SweetFin")
    static let preferredAudioLanguage = String(localized: "Preferred Audio Language", table: "SweetFin")
    static let preferredSubtitleLanguage = String(localized: "Preferred Subtitle Language", table: "SweetFin")
    static let extraSubtitleLanguages = String(localized: "Other Subtitle Languages", table: "SweetFin")
    static let showSDH = String(localized: "SDH Subtitles", table: "SweetFin")
    static let showAudioDescription = String(localized: "Audio Description", table: "SweetFin")
    static let accessibilityFooter = String(
        localized: """
        SDH: subtitles for the deaf and hard of hearing, which also describe sounds, music \
        and who is speaking. Audio description: a voice describes the action for the \
        visually impaired. Forced subtitles in your languages are always offered.
        """,
        table: "SweetFin"
    )

    // Pistes de l'engrenage (`MediaTrackFilter`)
    static func forcedTrack(_ language: String) -> String {
        String(localized: "\(language) (Forced)", table: "SweetFin")
    }

    static func sdhTrack(_ language: String) -> String {
        "\(language) (SDH)"
    }

    static func audioDescriptionTrack(_ language: String) -> String {
        String(localized: "\(language) (Audio Description)", table: "SweetFin")
    }

    /// Une piste sans langue connue : « Audio 2 », « Piste 3 ».
    static func untitledTrack(isAudio: Bool, position: Int) -> String {
        isAudio
            ? String(localized: "Audio \(position)", table: "SweetFin")
            : String(localized: "Track \(position)", table: "SweetFin")
    }

    // Segments (`SkipSegmentButton`)
    static let skipIntro = String(localized: "Skip Intro", table: "SweetFin")
    static let skipRecap = String(localized: "Skip Recap", table: "SweetFin")
    static let skipCredits = String(localized: "Skip Credits", table: "SweetFin")
    static let nextEpisode = String(localized: "Next Episode", table: "SweetFin")
    static let skip = String(localized: "Skip", table: "SweetFin")

    // Écran de pause
    static let endsAt = String(localized: "Ends at", table: "SweetFin")

    static func watched(percent: Int) -> String {
        String(localized: "\(percent)% watched", table: "SweetFin")
    }
}
