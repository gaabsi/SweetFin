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

    // EnhancedFin : pas de temps restant dans un rail de reprise, voir plus bas.
    @Environment(\.viewContext)
    private var viewContext

    let item: BaseItemDto
    let posterDisplayType: PosterDisplayType

    private var indicatorSize: CGFloat {
        UIDevice.isTV ? 45 : 25
    }

    // EnhancedFin : indicateurs imposés — progression et « vu », jamais « non vu ».
    private var showsProgressIndicator: Bool {
        item.progressLabel != nil &&
            item.userData?.isPlayed != true
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
