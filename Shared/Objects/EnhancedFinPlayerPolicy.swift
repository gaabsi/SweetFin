//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

/// EnhancedFin : tout ce que le fork impose au lecteur iOS, en un seul endroit.
///
/// Ces réglages ne sont plus proposés à l'utilisateur (`PlayerSettingsView`). Ils sont
/// **écrits** plutôt que lus en dur là où upstream les consulte : aucun fichier upstream
/// à modifier, et un compte qui avait d'autres valeurs (réglages enregistrés par compte)
/// les voit remplacées.
///
/// Appelé à chaque ouverture de session (`RootCoordinator.setUserDefaultsObservation`),
/// seul moment où les réglages du compte sont lisibles — et avant toute lecture : le
/// moteur est choisi dès la construction du lecteur, trop tôt pour l'overlay.
enum EnhancedFinPlayerPolicy {

    /// Vitesses proposées dans le lecteur.
    static let playbackRates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    /// Ancienneté maximale d'un épisode « à suivre » : 366 jours.
    static let maxNextUp: TimeInterval = 366 * 86400

    @MainActor
    static func enforce() {
        #if os(iOS)
        Defaults[.VideoPlayer.videoPlayerType] = .vlc

        // Un seul panneau dans le lecteur : les épisodes, ouverts par l'icône pile.
        Defaults[.VideoPlayer.supplements] = [.queue]

        // Aperçus au scrub, sans découpe en chapitres sur la barre.
        StoredValues[.User.previewImageScrubbing] = .trickplay(fallbackToChapters: true)
        Defaults[.VideoPlayer.Overlay.chapterSlider] = false

        // Gestes : tap simple (overlay, géré par le conteneur) et double tap gauche /
        // droite = recul / avance. Tout le reste est coupé.
        Defaults[.VideoPlayer.Gesture.multiTapGesture] = .jump
        Defaults[.VideoPlayer.Gesture.doubleTouchGesture] = .none
        Defaults[.VideoPlayer.Gesture.longPressAction] = .none
        Defaults[.VideoPlayer.Gesture.pinchGesture] = .none
        Defaults[.VideoPlayer.Gesture.horizontalPanAction] = .none
        Defaults[.VideoPlayer.Gesture.horizontalSwipeAction] = .none
        Defaults[.VideoPlayer.Gesture.verticalPanLeftAction] = .none
        Defaults[.VideoPlayer.Gesture.verticalPanRightAction] = .none
        #endif
    }
}
