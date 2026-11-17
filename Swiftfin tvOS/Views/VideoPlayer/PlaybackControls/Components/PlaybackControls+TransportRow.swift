//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// SweetFin : la rangée du lecteur tvOS, iso à celle de l'iPhone (`SweetFinPlaybackControls`)
// avec l'ergonomie TV : précédent · recul · lecture · avance · suivant, et à droite les
// épisodes et l'engrenage (même menu que l'iPhone, `SettingsMenu`). Le focus arrive sur
// Lecture/Pause, plus gros que les autres ; ← / → passent d'un bouton à l'autre, ↓ descend
// sur la barre de progression.

extension VideoPlayer.PlaybackControls {

    /// Côté des boutons de la rangée ; Lecture/Pause est plus gros.
    static let rowButtonSize: CGFloat = 72
    static let playButtonSize: CGFloat = 100

    var transportRow: some View {
        HStack(spacing: 24) {
            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .previous)
                    .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)
            }

            JumpButton(direction: .backward)
                .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)

            PlayPauseButton()
                .font(.system(size: 44, weight: .semibold))
                .frame(width: Self.playButtonSize, height: Self.playButtonSize)
                .focused($isPlayButtonFocused)

            JumpButton(direction: .forward)
                .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)

            if let queue = manager.queue {
                QueueButton(queue: queue, direction: .next)
                    .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)
            }

            Spacer()

            EpisodesButton()
                .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)

            if let playbackItem = manager.playbackItem {
                SettingsMenu(playbackItem: playbackItem)
                    .frame(width: Self.rowButtonSize, height: Self.rowButtonSize)
            }
        }
        .font(.system(size: 30, weight: .semibold))
        .labelStyle(.iconOnly)
        .modifier(OverlayButtonStyleModifier())
        .menuStyle(OverlayMenuStyle())
        .focusSection()
    }

    /// « Série - S1:E1 - Titre (année) », en haut à gauche, comme sur iPhone.
    var titleBar: some View {
        Text(SweetFinPlayer.title(of: manager.item))
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, EdgeInsets.edgePadding)
    }
}
