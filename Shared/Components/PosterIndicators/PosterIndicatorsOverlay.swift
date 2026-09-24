//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct PosterIndicatorsOverlay: View {

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    // EnhancedFin : voir `showsUnplayedIndicator`.
    @Environment(\.viewContext)
    private var viewContext

    let item: BaseItemDto
    let posterDisplayType: PosterDisplayType

    private var indicators: PosterIndicator {
        posterConfiguration.indicators
    }

    private var indicatorSize: CGFloat {
        UIDevice.isTV ? 45 : 25
    }

    /// ⚠️ EnhancedFin : **jamais dans un rail de reprise.**
    ///
    /// « Continuer de regarder » propose l'épisode suivant d'une série en cours. Cet
    /// épisode n'a évidemment pas été lu, donc la pastille « nouveau » s'allumait sur
    /// *chaque* tuile du rail — elle ne distinguait plus rien et contredisait le titre
    /// de la section. Ailleurs (ajouts récents, bibliothèques) elle garde tout son sens.
    private var showsUnplayedIndicator: Bool {
        !viewContext.contains(.isInResume) &&
            indicators.contains(.unplayed) &&
            item.canBePlayed &&
            !item.isLiveStream &&
            item.userData?.isPlayed == false &&
            (item.userData?.playbackPositionTicks ?? 0) == 0
    }

    private var showsProgressIndicator: Bool {
        indicators.contains(.progress) &&
            item.progressLabel != nil &&
            item.userData?.isPlayed != true
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsUnplayedIndicator {
                    UnplayedIndicator(
                        count: posterConfiguration.unplayedStyle == .count ? item.userData?.unplayedItemCount : nil
                    )
                    .frame(height: indicatorSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                HStack(spacing: 5) {
                    // EnhancedFin : pas d'indicateur favori, quel que soit le réglage
                    // enregistré du compte.

                    if indicators.contains(.played),
                       item.canBePlayed,
                       !item.isLiveStream,
                       item.userData?.isPlayed == true
                    {
                        PlayedIndicator()
                            .frame(width: indicatorSize, height: indicatorSize)
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsProgressIndicator {
                ProgressIndicator(
                    // EnhancedFin : pas de temps restant dans un rail de reprise, la
                    // barre suffit à dire où on en est.
                    title: viewContext.contains(.isInResume) ? nil : item.progressLabel,
                    progress: item.progressPercentage ?? 0,
                    posterDisplayType: posterDisplayType
                )
                .zIndex(5)
            }
        }
    }
}

struct PosterSelectionOverlay: View {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.isSelected)
    private var isSelected

    var body: some View {
        if isSelected {
            ContainerRelativeShape()
                .stroke(accentColor, lineWidth: UIDevice.isTV ? 12 : 8)
                .clipped()
        }
    }
}
