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

    // SweetFin : pas de temps restant dans un rail de reprise, voir plus bas.
    @Environment(\.viewContext)
    private var viewContext

    let item: BaseItemDto
    let posterDisplayType: PosterDisplayType

    private var indicatorSize: CGFloat {
        UIDevice.isTV ? 45 : 25
    }

    // SweetFin : indicateurs imposés — progression et « vu », jamais « non vu ».
    private var showsProgressIndicator: Bool {
        item.progressLabel != nil &&
            item.userData?.isPlayed != true
    }

    private var isInContinueWatching: Bool {
        viewContext.contains(.isInContinueWatching)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 5) {
                    if item.canBePlayed,
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
                    // SweetFin : pas de temps restant dans un rail de reprise, la
                    // barre suffit à dire où on en est.
                    title: viewContext.contains(.isInResume) ? nil : item.progressLabel,
                    progress: item.progressPercentage ?? 0,
                    posterDisplayType: posterDisplayType,
                    barColor: isInContinueWatching ? .white : nil
                )
                .zIndex(5)
            }
        }
        // SweetFin : dans « Continuer de regarder », toucher la tuile lance la lecture
        // (sauf reprise externe, qui ouvre sa fiche). Centré sur toute la tuile, barre ou
        // non : le rond est au même endroit sur un épisode entamé et sur le suivant.
        .overlay {
            if isInContinueWatching, !EnhancedFinSyntheticItem.isSynthetic(item.id) {
                ResumePlayIndicator()
            }
        }
    }
}

/// SweetFin : rond de lecture translucide, lisible sur une image claire comme sombre.
private struct ResumePlayIndicator: View {

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            // Le triangle est plus lourd à gauche : décalé pour paraître centré.
            .offset(x: 1.5)
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.35), in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
            .accessibilityHidden(true)
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
