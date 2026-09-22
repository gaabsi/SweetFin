//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Les sorties d'un jour, présentées **par-dessus** l'agenda.
///
/// Transposition de `_open_day_modal` du front web. Un `.sheet` en `presentationDetents
/// ([.medium])` plutôt qu'un calque maison : il monte du bas, laisse la grille visible
/// au-dessus, se ferme au glissement ou en tapant à côté — tout ce que la modale web
/// implémente à la main, et que les gens attendent déjà sur iOS.
struct CalendarDaySheet: View {

    @Router
    private var router

    @Environment(\.dismiss)
    private var dismiss

    /// Espace de la transition vers la fiche. La feuille étant sa propre
    /// présentation, elle n'hérite d'aucun espace de l'agenda.
    @Namespace
    private var namespace

    let day: Date
    let entries: [CalendarEntry]

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    // Fermer d'abord : router depuis une feuille encore présentée
                    // empile la fiche derrière elle.
                    dismiss()
                    open(entry.release)
                } label: {
                    CalendarReleaseRow(entry: entry)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Même règle que partout : en bibliothèque la fiche native, sinon la fiche de
    /// découverte.
    ///
    /// Le routage est différé d'un tour de boucle, le temps que la feuille se ferme —
    /// sans quoi la navigation part pendant la transition et la fiche s'ouvre sous
    /// elle.
    private func open(_ release: EnhancedFinRelease) {
        Task { @MainActor in
            router.openEnhancedFin(release, in: namespace)
        }
    }
}

/// Une ligne de sortie : l'affiche, le titre, et ce qui sort ce jour-là.
struct CalendarReleaseRow: View {

    let entry: CalendarEntry

    private var release: EnhancedFinRelease { entry.release }

    var body: some View {
        HStack(spacing: 12) {
            ImageView(ImageSource(url: URL.enhancedFinImage(release.posterUrl)))
                .failure {
                    ZStack {
                        Color.secondarySystemFill
                        Image(systemName: release.systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 66)
                .clipShape(.rect(cornerRadius: 6))

            // Le nom du média, et rien de plus : ni saison, ni épisode, ni titre
            // d'épisode. TMDB remplit d'ailleurs ce dernier par « Épisode N » dans
            // 11 % des cas, ce qui ne faisait que répéter le numéro.
            Text(release.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

}
