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

    var body: some View {
        // SweetFin : les tuiles de « Continuer de regarder » ont leur propre habillage.
        if viewContext.contains(.isInContinueWatching) {
            ResumeTileOverlay(
                progress: showsProgressIndicator ? item.progressPercentage ?? 0 : nil,
                // Toucher la tuile lance la lecture, sauf reprise externe (fiche).
                showsPlay: !EnhancedFinSyntheticItem.isSynthetic(item.id)
            )
        } else {
            standardOverlay
        }
    }

    private var standardOverlay: some View {
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
                    posterDisplayType: posterDisplayType
                )
                .zIndex(5)
            }
        }
    }
}

/// SweetFin : habillage d'une tuile de « Continuer de regarder », neutre quel que soit
/// le thème — barre gris clair sur une ombre courte, rond de lecture centré sur toute la
/// tuile (même place, barre ou non) et contour en surbrillance.
private struct ResumeTileOverlay: View {

    /// Avancement, `nil` = pas de barre (épisode suivant).
    let progress: Double?
    let showsPlay: Bool

    var body: some View {
        ZStack {
            if let progress {
                ResumeProgressBar(progress: progress)
            }

            if showsPlay {
                ResumePlayIndicator()
            }

            ContainerRelativeShape()
                .inset(by: 0.5)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }
}

/// Barre fine cernée de sombre, sur une ombre courte qui la détache de l'image.
private struct ResumeProgressBar: View {

    let progress: Double

    /// `#D1D1D6` : neutre comme le blanc, moins vif.
    private let fill = Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255)

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.35))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * clamp(progress, min: 0, max: 1))
                }
            }
            .frame(height: 5)
            .padding(1)
            .background(.black.opacity(0.35), in: .capsule)
            .padding([.horizontal, .bottom], 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 14)
            }
    }
}

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
