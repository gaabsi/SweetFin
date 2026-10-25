//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import Logging
import SwiftUI

struct PlayButton: View {

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var provider: ItemContentGroupProvider

    @Router
    private var router

    /// Pas encore d'item à lancer, le serveur n'a pas encore répondu (`playable`).
    private var isResolving: Bool {
        provider.mediaPlayerItemProvider == nil && provider.isResolvingPlayable
    }

    /// Rien à lire sur ce serveur, réponse connue : le bouton le dit au lieu de proposer
    /// une lecture grisée (rien n'est présenté comme lisible sans item à lancer).
    private var isUnavailable: Bool {
        provider.mediaPlayerItemProvider == nil && !provider.isResolvingPlayable
    }

    private var label: String {
        if isUnavailable { return ItemStrings.unavailable }
        return provider.mediaPlayerItemProvider?.item.playButtonLabel ?? L10n.play
    }

    private var mediaSource: String? {
        guard provider.mediaPlayerItemProvider?.item.mediaSources?.count ?? 0 > 1 else { return nil }
        return provider.mediaPlayerItemProvider?.mediaSource?.displayTitle
    }

    private func play(fromBeginning: Bool = false) {
        let mediaPlayerItemProvider = if fromBeginning {
            provider.mediaPlayerItemProvider?.modifyingItem {
                $0.userData?.playbackPositionTicks = 0
            }
        } else {
            provider.mediaPlayerItemProvider
        }

        guard let mediaPlayerItemProvider else {
            provider.logger.error("Play selected with no playback item provider")
            return
        }

        // SweetFin : même chemin que les tuiles ; la file se construit sur l'item résolu.
        // La clé de la fiche sert à la file si l'épisode est désigné par le serveur.
        router.play(mediaPlayerItemProvider, seriesKey: provider.item.enhancedFinMediaKey)
    }

    var body: some View {
        Button {
            play()
        } label: {
            HStack {
                // SweetFin : roue tant que le serveur n'a pas dit s'il y a quelque
                // chose à lire (`playable`, résolu après l'affichage de la fiche), sans
                // libellé : rien n'annonce une lecture avant qu'elle soit possible.
                if isResolving {
                    ProgressView()
                } else {
                    Image(systemName: isUnavailable ? "nosign" : "play.fill")
                }

                VStack(spacing: 2) {
                    if !isResolving {
                        Text(label)
                    }

                    if let mediaSource {
                        Marquee(mediaSource, speed: 40, delay: 3, fade: 5)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.callout)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: accentColor,
                    foregroundColor: accentColor.overlayColor
                ),
                in: .capsule
            )
        }
        .buttonBorderShape(.capsule)
        .buttonStyle(BasicHoverButtonStyle())
        .contextMenu {
            if provider.mediaPlayerItemProvider?.item.userData?.playbackPositionTicks != 0 {
                Button(L10n.playFromBeginning, systemImage: "gobackward") {
                    play(fromBeginning: true)
                }
            }
        }
        .disabled(provider.mediaPlayerItemProvider == nil)
    }
}
