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

/// SweetFin : télécharger d'un coup la suite d'une série, depuis le menu « … » de sa fiche
/// (série de la médiathèque ou connue par sa clé).
///
/// Bannière de la série, deux raccourcis (« Fin de saison », « Toute la suite »), puis les
/// épisodes à venir groupés par saison, chacun cochable ; « Télécharger (N) » en haut à
/// droite (❌ un gros bouton fixe en bas : jugé trop lourd). Par défaut, la fin de la
/// saison de l'épisode à suivre est cochée. Les saisons arrivent une à une
/// (`DownloadManager.remainingEpisodes`). Épisodes déjà présents dans l'onglet (en cours,
/// terminés ou en échec) : absents — un échec se relance depuis la fiche.
struct SeasonDownloadView: View {

    @Router
    private var router

    @StateObject
    private var viewModel: SeasonDownloadViewModel

    init(series: BaseItemDto) {
        _viewModel = StateObject(wrappedValue: SeasonDownloadViewModel(series: series))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                banner

                if viewModel.showsPresets {
                    presets

                    if let size = viewModel.selectedSize {
                        Text(DownloadStrings.size(size))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(viewModel.seasons) { season in
                    Text(season.title)
                        .font(.title3.weight(.semibold))
                        .padding(.top, 8)

                    ForEach(season.episodes) { episode in
                        row(episode)
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if viewModel.seasons.isEmpty {
                    Text(DownloadStrings.nothingToDownload)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .edgePadding(.horizontal)
            .padding(.bottom, 12)
        }
        .navigationTitle(viewModel.series.name ?? DownloadStrings.downloadNext)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
        .topBarTrailing {
            Button(DownloadStrings.downloadCount(viewModel.selected.count)) {
                if viewModel.send() {
                    router.dismiss()
                }
            }
            .backport
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(viewModel.selected.isEmpty)
        }
        .task {
            await viewModel.load()
        }
        .errorMessage($viewModel.error)
    }

    // MARK: - En-tête

    private var banner: some View {
        let series = viewModel.series
        let title = series.name ?? ""

        return DownloadBanner(height: 160) {
            ImageView(series.imageSource(.backdrop, environment: ImageSourceOptions(maxWidth: 1280)))
                .image { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .failure {
                    BannerBackdrop(image: nil)
                }
        } logo: {
            ImageView(series.imageSource(.logo, environment: ImageSourceOptions(maxWidth: 360)))
                .image { image in
                    BannerLogo(image: image, title: title)
                }
                .placeholder { _ in
                    EmptyView()
                }
                .failure {
                    BannerLogo(image: nil, title: title)
                }
        } content: {
            EmptyView()
        }
    }

    /// « Fin de saison », « Toute la suite » : cochent d'un coup. Chacun n'apparaît que s'il
    /// coche autre chose que l'autre.
    private var presets: some View {
        HStack(spacing: 8) {
            if viewModel.showsEndOfSeason {
                presetButton(DownloadStrings.endOfSeason, isSelected: viewModel.isEndOfSeasonSelected) {
                    viewModel.selectEndOfSeason()
                }
            }
            if viewModel.showsAllRemaining {
                presetButton(DownloadStrings.allRemaining, isSelected: viewModel.isAllSelected) {
                    viewModel.selectAll()
                }
            }
        }
    }

    private func presetButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(0.1)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Épisodes

    /// Un épisode : miniature, « E5 · Titre », durée, case. Tap = cocher / décocher.
    ///
    /// Parametres :
    /// - episode (EpisodeDownload) : épisode proposé
    private func row(_ episode: EpisodeDownload) -> some View {
        let item = episode.item
        let isSelected = viewModel.selection.contains(episode.id)

        return Button {
            viewModel.toggle(episode)
        } label: {
            HStack(spacing: 12) {
                ImageView(item.imageSource(.primary, environment: ImageSourceOptions(maxWidth: 240)))
                    .image { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .failure {
                        Color.white.opacity(0.06)
                    }
                    .frame(width: 112, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.episodeShortTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let runtime = item.runtime {
                        Text(runtime, format: .hourMinuteAbbreviated)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// SweetFin : l'état de la feuille « Télécharger la suite » : saisons reçues, sélection,
/// raccourcis.
@MainActor
final class SeasonDownloadViewModel: ObservableObject {

    /// Une saison et ses épisodes proposés.
    struct Season: Identifiable {
        let number: Int
        let title: String
        let episodes: [EpisodeDownload]

        var id: Int { number }
    }

    let series: BaseItemDto

    @Published
    private(set) var seasons: [Season] = []
    @Published
    private(set) var selection: Set<String> = []
    @Published
    private(set) var isLoading = true
    @Published
    var error: Error?

    /// « Toute la suite » choisie : les saisons qui arrivent ensuite sont cochées aussi.
    private var selectsAll = false
    /// La saison de l'épisode à suivre (1ʳᵉ reçue), celle de « Fin de saison ».
    private var nextUpSeason: Int?

    private let manager = Container.shared.downloadManager()
    private let userSession = Container.shared.currentUserSession()

    init(series: BaseItemDto) {
        self.series = series
    }

    /// Les épisodes cochés, dans l'ordre.
    var selected: [EpisodeDownload] {
        seasons.flatMap(\.episodes).filter { selection.contains($0.id) }
    }

    /// Taille des épisodes cochés, `nil` si l'une est inconnue (série connue par sa clé : la
    /// taille arrive avec la fiche complète, au téléchargement).
    var selectedSize: Int64? {
        let sizes = selected.compactMap(\.size)
        guard sizes.isNotEmpty, sizes.count == selected.count else { return nil }
        return sizes.reduce(0) { $0 + Int64($1) }
    }

    /// La fin de la saison de l'épisode à suivre ; vide si elle est déjà dans l'onglet.
    /// ❌ « La 1ʳᵉ saison affichée » : cochait toute la saison suivante quand la fin de la
    /// saison en cours était déjà téléchargée.
    private var endOfSeasonIDs: Set<String> {
        Set(seasons.first { $0.number == nextUpSeason }?.episodes.map(\.id) ?? [])
    }

    private var allIDs: Set<String> {
        Set(seasons.flatMap(\.episodes).map(\.id))
    }

    var showsEndOfSeason: Bool {
        endOfSeasonIDs.isNotEmpty
    }

    /// « Toute la suite » seulement si elle va au-delà de la fin de saison.
    var showsAllRemaining: Bool {
        allIDs != endOfSeasonIDs
    }

    var showsPresets: Bool {
        showsEndOfSeason || showsAllRemaining
    }

    var isEndOfSeasonSelected: Bool {
        !selection.isEmpty && selection == endOfSeasonIDs
    }

    var isAllSelected: Bool {
        !selection.isEmpty && selection == allIDs
    }

    /// Reçoit les saisons une à une ; la fin de la saison de l'épisode à suivre est cochée,
    /// les suivantes aussi si « Toute la suite » est choisie.
    func load() async {
        defer { isLoading = false }
        guard let userSession else { return }
        let userID = userSession.user.id

        do {
            for try await remaining in manager.remainingEpisodes(of: series, userSession: userSession) {
                if nextUpSeason == nil {
                    nextUpSeason = remaining.number
                }
                let pending = remaining.episodes.filter { manager.state(of: $0.id, userID: userID) == .none }
                guard let first = pending.first else { continue }

                let title = first.item.seasonName ?? "\(L10n.season) \(remaining.number)"
                seasons.append(Season(number: remaining.number, title: title, episodes: pending))

                if remaining.number == nextUpSeason || selectsAll {
                    selection.formUnion(pending.map(\.id))
                }
            }
        } catch {
            self.error = error
        }
    }

    /// Coche la fin de la saison de l'épisode à suivre, seule.
    func selectEndOfSeason() {
        selectsAll = false
        selection = endOfSeasonIDs
    }

    /// Coche toute la suite, y compris les saisons encore en chargement.
    func selectAll() {
        selectsAll = true
        selection = allIDs
    }

    /// Coche ou décoche un épisode. « Toute la suite » reste choisie tant que tout est coché.
    ///
    /// Parametres :
    /// - episode (EpisodeDownload) : épisode touché
    func toggle(_ episode: EpisodeDownload) {
        if selection.contains(episode.id) {
            selection.remove(episode.id)
        } else {
            selection.insert(episode.id)
        }
        selectsAll = isAllSelected
    }

    /// Lance les épisodes cochés : ils apparaissent aussitôt dans l'onglet
    /// Téléchargements, qui prend le relais.
    ///
    /// Output :
    /// - didStart (Bool) : vrai si lancé ; faux sur erreur (espace insuffisant), affichée
    func send() -> Bool {
        guard let userSession else { return false }

        do {
            try manager.start(selected, userSession: userSession)
            return true
        } catch {
            self.error = error
            return false
        }
    }
}
