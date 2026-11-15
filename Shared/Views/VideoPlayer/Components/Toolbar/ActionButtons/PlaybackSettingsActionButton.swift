//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: compatibility picker
// TODO: don't present for offline/live items
//       - value on media player item

extension VideoPlayer.PlaybackControls.Toolbar.ActionButtons {

    struct PlaybackSettings: View {

        @EnvironmentObject
        private var manager: MediaPlayerManager

        // SweetFin : plus de choix de qualité (lecture directe), seulement la version.
        var body: some View {
            if let playbackItem = manager.playbackItem,
               let versions = playbackItem.baseItem.mediaSources,
               versions.count > 1
            {
                Menu {
                    Picker(
                        selection: Binding(
                            get: { playbackItem.mediaSource.id },
                            set: { newID in
                                guard let newSource = versions.first(where: { $0.id == newID }) else { return }
                                manager.switchVersion(to: newSource)
                            }
                        )
                    ) {
                        ForEach(versions, id: \.hashValue) { version in
                            Text(version.displayTitle)
                                .tag(version.id)
                        }
                    } label: {
                        Text(L10n.version)
                        Text(playbackItem.mediaSource.displayTitle)
                    }
                } label: {
                    Label(
                        L10n.version,
                        systemImage: VideoPlayerActionButton.playbackSettings.systemImage
                    )
                }
            }
        }
    }
}

// SweetFin : changer de version en reprenant à la position courante, partagé par ce menu
// (tvOS) et l'engrenage du lecteur iOS (`SettingsMenu`).
extension MediaPlayerManager {

    /// Passe sur une autre version de l'item en lecture, reprise à la position courante.
    /// Sans effet si c'est déjà elle.
    ///
    /// Parametres :
    /// - mediaSource (MediaSourceInfo) : la version voulue
    func switchVersion(to mediaSource: MediaSourceInfo) {
        guard let playbackItem, mediaSource.id != playbackItem.mediaSource.id else { return }

        var adjustedBaseItem = playbackItem.baseItem
        adjustedBaseItem.userData?.playbackPositionTicks = seconds.ticks
        let provider = MediaPlayerItemProvider(item: adjustedBaseItem, mediaSource: mediaSource) { baseItem, modifyItem in
            try await MediaPlayerItem.build(
                for: baseItem,
                mediaSource: mediaSource,
                modifyItem: modifyItem
            )
        }
        playNewItem(provider: provider)
    }
}
