//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

/// SweetFin : « Passer l'intro », « Épisode suivant »… pendant les segments de média
/// (écrits par Intro Skipper dans les segments natifs de Jellyfin 10.10+).
///
/// Visible pendant **tout** le segment, commandes affichées ou non, comme Netflix.
/// Jamais de saut automatique (décision de Gabriel).
///
/// - intro, résumé, aperçu, pub : saut à la fin du segment **moins 2 s**, pour voir la fin
///   du générique ;
/// - générique de fin : épisode suivant **directement** s'il y en a un, sinon même saut.
struct SkipSegmentButton: View {

    /// Marge avant la fin du segment : on voit la fin du générique.
    private static let endMargin: Duration = .seconds(2)

    @EnvironmentObject
    private var manager: MediaPlayerManager

    @State
    private var segments: [MediaSegmentDto] = []
    /// Le segment en cours, recalculé à chaque position mais publié seulement quand il
    /// change : la position arrive ~50 fois par seconde.
    @State
    private var currentSegment: MediaSegmentDto?
    /// Le segment qu'on vient de passer : on y reste encore `endMargin`, sans bouton.
    @State
    private var skippedSegmentID: String?

    var body: some View {
        ZStack {
            if let currentSegment, currentSegment.id != skippedSegmentID {
                Button {
                    skip(currentSegment)
                } label: {
                    Text(title(of: currentSegment))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentSegment?.id)
        .task(id: manager.item.id) {
            await loadSegments()
        }
        .onReceive(manager.secondsBox.$value) { seconds in
            let segment = segments.first { $0.contains(seconds) }
            if segment?.id != currentSegment?.id {
                currentSegment = segment
            }
        }
    }

    /// Les segments de l'item en cours. Sans réseau (lecture hors ligne) ou sans segment :
    /// liste vide, donc jamais de bouton.
    private func loadSegments() async {
        segments = []
        currentSegment = nil
        skippedSegmentID = nil

        guard let itemID = manager.item.id,
              let client = Container.shared.currentUserSession()?.client
        else { return }

        let request = Paths.getItemSegments(itemID: itemID)
        let items = (try? await client.send(request).value.items) ?? []

        guard !Task.isCancelled else { return }
        segments = items.filter { $0.type != .unknown && $0.endTicks != nil }
    }

    /// Passe le segment : épisode suivant pour un générique de fin s'il y en a un, sinon
    /// saut à la fin du segment moins `endMargin`.
    ///
    /// Parametres :
    /// - segment (MediaSegmentDto) : le segment en cours
    private func skip(_ segment: MediaSegmentDto) {
        if segment.type == .outro, let nextItem = manager.queue?.nextItem {
            manager.playNewItem(provider: nextItem)
            return
        }

        guard let endTicks = segment.endTicks else { return }

        skippedSegmentID = segment.id
        let start = Duration.ticks(segment.startTicks ?? 0)
        manager.proxy?.setSeconds(max(start, .ticks(endTicks) - Self.endMargin))
    }

    /// Le libellé selon le type de segment.
    ///
    /// Parametres :
    /// - segment (MediaSegmentDto) : le segment en cours
    ///
    /// Output :
    /// - title (String) : le libellé du bouton
    private func title(of segment: MediaSegmentDto) -> String {
        switch segment.type {
        case .intro:
            PlayerStrings.skipIntro
        case .recap:
            PlayerStrings.skipRecap
        case .outro:
            manager.queue?.nextItem == nil ? PlayerStrings.skipCredits : PlayerStrings.nextEpisode
        default:
            PlayerStrings.skip
        }
    }
}

private extension MediaSegmentDto {

    /// Vrai si la position est dans le segment (début inclus, fin exclue).
    func contains(_ seconds: Duration) -> Bool {
        guard let startTicks, let endTicks else { return false }
        let ticks = seconds.ticks

        return ticks >= startTicks && ticks < endTicks
    }
}
