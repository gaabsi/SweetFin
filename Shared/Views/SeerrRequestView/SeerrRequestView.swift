//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// SweetFin : la fenêtre « Demander sur Seerr », ouverte depuis le menu « … » d'une
/// fiche incomplète ou de découverte (`EnhancedFinMedia.canRequestOnSeerr(isNative:)`).
///
/// Reprise de la modale du front web (`detail_page.js`, `_open_season_picker` /
/// `_open_movie_confirm`), **sans choix de langue** : il n'avait d'effet que par un
/// service de téléchargement absent d'EnhancedFin.
///
/// - série : les saisons à cocher ; celles déjà disponibles, en attente ou en cours
///   sont grisées avec leur statut ;
/// - film : une simple confirmation.
///
/// La demande part au nom de l'utilisateur connecté — le plugin le tire du jeton.
struct SeerrRequestView: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    let media: EnhancedFinMedia

    @State
    private var detail: EnhancedFinSeerrDetail?
    @State
    private var selection: Set<Int> = []
    @State
    private var isSending = false
    @State
    private var error: Error?
    /// Chargement des saisons en échec : un bouton « Réessayer » remplace la roue,
    /// qui sinon tournerait sans fin sous l'alerte d'erreur.
    @State
    private var didFailLoading = false

    private var isSeries: Bool {
        media.mediaType == EnhancedFinMediaType.tv.rawValue
    }

    /// Les saisons qu'on peut encore demander.
    private var requestableSeasons: [EnhancedFinSeerrSeason] {
        detail?.seasons.filter { !$0.isLocked } ?? []
    }

    private var canSend: Bool {
        !isSending && (isSeries ? selection.isNotEmpty : true)
    }

    var body: some View {
        Form {
            Section {
                header
            }
            .listRowInsets(.zero)

            if isSeries {
                seasonsSection
            } else {
                Section {
                    Text(SeerrStrings.confirmMovie(media.title))
                }
            }
        }
        .navigationTitle(isSeries ? SeerrStrings.requestSeries : SeerrStrings.requestMovie)
        .toolbarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSending)
        .navigationBarCloseButton(disabled: isSending) {
            router.dismiss()
        }
        .topBarTrailing {
            if isSending {
                ProgressView()
            } else {
                Button(SeerrStrings.request) {
                    Task { await send() }
                }
                .backport
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .enabled(canSend)
            }
        }
        .task {
            guard isSeries else { return }
            await loadSeasons()
        }
        .errorMessage($error)
    }

    // MARK: - En-tête

    /// Le fond du média, assombri sous son titre — comme l'en-tête de la modale web.
    private var header: some View {
        ImageView(URL.enhancedFinImage(media.backdropUrl))
            .image { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .failure {
                Color.secondarySystemFill
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)

                    if let year = media.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                }
            }
            .colorScheme(.dark)
    }

    // MARK: - Saisons

    @ViewBuilder
    private var seasonsSection: some View {
        if let detail {
            Section(SeerrStrings.seasons) {
                if requestableSeasons.count > 1 {
                    Toggle(SeerrStrings.selectAll, isOn: Binding(
                        get: { selection.count == requestableSeasons.count },
                        set: { selection = $0 ? Set(requestableSeasons.map(\.number)) : [] }
                    ))
                }

                ForEach(detail.seasons) { season in
                    seasonRow(season)
                }
            }
        } else {
            Section {
                if didFailLoading {
                    Button(L10n.retry) {
                        Task { await loadSeasons() }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func seasonRow(_ season: EnhancedFinSeerrSeason) -> some View {
        let isSelected = selection.contains(season.number)

        return Button {
            if isSelected {
                selection.remove(season.number)
            } else {
                selection.insert(season.number)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: season.isLocked || isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(season.isLocked ? Color.secondary : Color.accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(season.name ?? SeerrStrings.season(season.number))
                        .foregroundStyle(.primary)

                    Text(Self.meta(of: season))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Self.statusLabel(season.status))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(season.status == EnhancedFinSeerr.available ? .green : .secondary)
            }
        }
        .disabled(season.isLocked)
    }

    /// « 1999 · 9 ép. »
    private static func meta(of season: EnhancedFinSeerrSeason) -> String {
        let year = season.airDate.map { String($0.prefix(4)) }
        return [year, SeerrStrings.episodes(season.episodeCount)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// Le statut Seerr d'une saison, comme dans la modale web.
    private static func statusLabel(_ status: Int) -> String {
        switch status {
        case EnhancedFinSeerr.available: SeerrStrings.available
        case EnhancedFinSeerr.partiallyAvailable: SeerrStrings.partiallyAvailable
        case EnhancedFinSeerr.pending, EnhancedFinSeerr.processing: SeerrStrings.pending
        default: SeerrStrings.notRequested
        }
    }

    // MARK: - Réseau

    /// Les saisons et leur statut. Rien de pré-coché : on demande ce qu'on choisit.
    private func loadSeasons() async {
        guard let client = userSession?.enhancedFinClient else { return }

        didFailLoading = false
        do {
            detail = try await client.seerr(media.mediaKey)
        } catch {
            self.error = error
            didFailLoading = true
        }
    }

    /// Envoie la demande. Réussie : l'écran d'en dessous se reconstruit (le statut a
    /// changé, « Demander sur Seerr » peut disparaître) et la fenêtre se ferme.
    private func send() async {
        guard let client = userSession?.enhancedFinClient else { return }

        isSending = true
        defer { isSending = false }

        do {
            try await client.requestOnSeerr(media.mediaKey, seasons: selection.sorted())
            UIDevice.feedback(.success)
            Notifications[.didRequestGlobalRefresh].post()
            router.dismiss()
        } catch {
            self.error = error
        }
    }
}
