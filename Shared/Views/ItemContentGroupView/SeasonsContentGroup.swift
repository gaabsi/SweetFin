//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// SweetFin : le rail des saisons d'une série, et la feuille de ses épisodes.
///
/// Même rendu pour une série du serveur et une série de découverte : la source est
/// cachée derrière ``SeasonEpisodesViewModel``. Un tap sur une saison ouvre la liste
/// verticale de ses épisodes, où l'on marque ce qu'on a vu — repris de la modale
/// `episode_modal_core.js` du front web.
struct SeasonsContentGroup: ContentGroup {

    let id: String
    let viewModel: SeasonEpisodesViewModel

    var _shouldBeResolved: Bool {
        viewModel.seasons.isNotEmpty
    }

    /// Parametres :
    /// - id (String) : identifiant de la série, pour distinguer les groupes
    /// - backend (SeasonEpisodesViewModel.Backend) : source des saisons
    init(id: String, backend: SeasonEpisodesViewModel.Backend) {
        self.id = "\(id)-seasons"
        self.viewModel = SeasonEpisodesViewModel(backend: backend)
    }

    func body(with viewModel: SeasonEpisodesViewModel) -> some View {
        SeasonsRail(viewModel: viewModel)
    }
}

// MARK: - Rail

private struct SeasonsRail: View {

    @ObservedObject
    var viewModel: SeasonEpisodesViewModel

    @State
    private var isPresentingEpisodes = false

    var body: some View {
        ContentGroupSection {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.seasons) { season in
                        Button {
                            isPresentingEpisodes = true
                            Task { await viewModel.select(season: season.number) }
                        } label: {
                            SeasonCard(season: season)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .edgePadding(.horizontal)
            }
        } header: {
            Text(L10n.seasons)
                .font(.title3)
                .fontWeight(.semibold)
                .edgePadding(.horizontal)
                .accessibilityAddTraits(.isHeader)
        }
        .seasonEpisodesSheet(isPresented: $isPresentingEpisodes, viewModel: viewModel)
    }
}

private struct SeasonCard: View {

    // Alignement du libellé décidé par le thème, comme sous les autres affiches.
    @Default(.appearance)
    private var appearance

    let season: SeasonRow

    var body: some View {
        VStack(alignment: appearance.tokens.posterLabelAlignment, spacing: 6) {
            FixedImage(source: season.poster, width: 120, height: 180)

            Text(season.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            if let count = season.episodeCount {
                Text(ItemStrings.watchedCount(season.watchedCount, of: count))
                    .font(.caption)
                    .foregroundStyle(season.watchedCount >= count && count > 0 ? .green : .secondary)
            }
        }
        .frame(width: 120)
    }
}

// MARK: - Feuille des épisodes

/// SweetFin : la feuille des épisodes, et la lecture qui en part.
///
/// Le lecteur ne s'ouvre qu'**une fois la feuille fermée** : SwiftUI refuse deux
/// présentations à la fois, et le lecteur est présenté par le coordinateur, sous la
/// feuille.
private struct SeasonEpisodesSheetModifier: ViewModifier {

    @Binding
    var isPresented: Bool

    let viewModel: SeasonEpisodesViewModel

    @Router
    private var router

    @State
    private var pendingPlayback: MediaPlayerItemProvider?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: playPending) {
                SeasonEpisodesSheet(viewModel: viewModel) { provider in
                    pendingPlayback = provider
                    isPresented = false
                }
            }
    }

    private func playPending() {
        guard let provider = pendingPlayback else { return }
        pendingPlayback = nil

        router.play(provider)
    }
}

private extension View {

    func seasonEpisodesSheet(isPresented: Binding<Bool>, viewModel: SeasonEpisodesViewModel) -> some View {
        modifier(SeasonEpisodesSheetModifier(isPresented: isPresented, viewModel: viewModel))
    }
}

private struct SeasonEpisodesSheet: View {

    @Default(.appearance)
    private var appearance

    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject
    var viewModel: SeasonEpisodesViewModel

    /// SweetFin : un épisode à lire est prêt ; celui qui présente la feuille la ferme
    /// puis ouvre le lecteur.
    let onPlay: (MediaPlayerItemProvider) -> Void

    @State
    private var isSelecting = false
    @State
    private var selection: Set<String> = []

    /// SweetFin : l'item à télécharger pour un épisode (iPhone, épisode du serveur,
    /// compte autorisé à télécharger) ; `nil` sinon.
    private func downloadableID(_ episode: EpisodeRow) -> String? {
        #if os(iOS)
        guard Container.shared.currentUserSession()?.user.data.policy?.enableContentDownloading == true else { return nil }
        return episode.jellyfinID
        #else
        return nil
        #endif
    }

    private var seasonIndex: Int? {
        viewModel.seasons.firstIndex { $0.number == viewModel.selectedSeason }
    }

    private var currentSeason: SeasonRow? {
        seasonIndex.map { viewModel.seasons[$0] }
    }

    private var watchedIDs: Set<String> {
        Set(viewModel.episodes.filter(\.isWatched).map(\.id))
    }

    /// Ce que « Valider » enverra : les coches ajoutées marquent vu, les coches
    /// retirées démarquent. Vide = rien n'a changé.
    private var changes: (toMark: Set<String>, toUnmark: Set<String>) {
        (selection.subtracting(watchedIDs), watchedIDs.subtracting(selection))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    controls
                        .padding(.bottom, 12)

                    if viewModel.isLoadingEpisodes {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeRowView(
                                episode: episode,
                                isSelecting: isSelecting,
                                isSelected: selection.contains(episode.id),
                                availability: viewModel.availability(of: episode),
                                toggleSelection: { toggleSelection(episode) },
                                play: { play(episode) },
                                downloadableID: downloadableID(episode)
                            )

                            Divider()
                        }
                    }
                }
                .edgePadding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    seasonSwitcher
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.close, systemImage: "xmark") { dismiss() }
                }
            }
            .themeContainerBackground(appearance.tokens.background)
        }
        // Changer de saison sort du mode sélection : la sélection ne vaut que pour
        // les épisodes affichés.
        .onChange(of: viewModel.selectedSeason) { _, _ in exitSelection() }
    }

    /// « ‹ Saison 1 › » : les flèches mènent aux saisons voisines, si elles existent.
    private var seasonSwitcher: some View {
        HStack(spacing: 16) {
            Button(L10n.previous, systemImage: "chevron.backward") { move(by: -1) }
                .disabled((seasonIndex ?? 0) == 0)

            Text(currentSeason?.name ?? "")
                .font(.headline)
                .lineLimit(1)

            Button(L10n.next, systemImage: "chevron.forward") { move(by: 1) }
                .disabled((seasonIndex ?? 0) >= viewModel.seasons.count - 1)
        }
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if isSelecting {
                Button(L10n.selectAll) {
                    // Les épisodes à venir ne se marquent pas : ils gardent leur coche actuelle.
                    selection.formUnion(viewModel.episodes.filter { !$0.isUpcoming }.map(\.id))
                }

                Spacer()

                Button(L10n.cancel, action: exitSelection)

                Button(ItemStrings.validate) {
                    let (toMark, toUnmark) = changes
                    exitSelection()
                    Task {
                        await viewModel.setWatched(toMark, watched: true)
                        await viewModel.setWatched(toUnmark, watched: false)
                    }
                }
                .buttonStyle(.borderedProminent)
                // SweetFin : le style système écrit en blanc, illisible sur un accent clair.
                .foregroundStyle(appearance.tokens.accent.overlayColor)
                .disabled(changes.toMark.isEmpty && changes.toUnmark.isEmpty)
            } else {
                Spacer()

                Button(ItemStrings.markAsWatched) {
                    // Comme le web : les épisodes déjà vus arrivent cochés. Les
                    // décocher les démarque — c'est le seul chemin pour ça.
                    selection = watchedIDs
                    isSelecting = true
                }
                .disabled(viewModel.episodes.isEmpty)
            }
        }
        .font(.subheadline)
    }

    private func move(by offset: Int) {
        guard let index = seasonIndex, viewModel.seasons.indices.contains(index + offset) else { return }

        Task { await viewModel.select(season: viewModel.seasons[index + offset].number) }
    }

    private func toggleSelection(_ episode: EpisodeRow) {
        if selection.contains(episode.id) {
            selection.remove(episode.id)
        } else {
            selection.insert(episode.id)
        }
    }

    /// Lit un épisode : la feuille se ferme et le lecteur s'ouvre tout de suite, la
    /// résolution se fait dedans.
    ///
    /// Parametres :
    /// - episode (EpisodeRow) : épisode touché
    private func play(_ episode: EpisodeRow) {
        onPlay(viewModel.playbackProvider(for: episode))
    }

    private func exitSelection() {
        isSelecting = false
        selection = []
    }
}

private struct EpisodeRowView: View {

    let episode: EpisodeRow
    let isSelecting: Bool
    let isSelected: Bool
    /// SweetFin : seul un épisode lisible ouvre le lecteur.
    let availability: EpisodeAvailability
    let toggleSelection: () -> Void
    let play: () -> Void
    /// SweetFin : item à proposer au téléchargement (appui long), `nil` = pas de menu.
    let downloadableID: String?

    @Default(.accentColor)
    private var accentColor

    /// « 24m », « 1h05 » : plus court que le format système (« 24 min »), la
    /// pastille tient dans le coin de la vignette.
    private var runtimeLabel: String? {
        guard let minutes = episode.runtime.map({ Int($0.components.seconds / 60) }), minutes > 0 else { return nil }

        return minutes < 60
            ? "\(minutes)m"
            : String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    /// Sorti mais non lisible : vignette en noir et blanc, titre atténué. Pas d'opacité,
    /// qui veut déjà dire « vu » ici ; un épisode à venir garde sa pastille de date.
    private var isGreyed: Bool {
        availability == .unavailable && !episode.isUpcoming
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }

            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                if let name = episode.name {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(isGreyed ? .secondary : .primary)
                }

                // SweetFin : pas encore diffusé, en couleur d'accent (l'atténuation veut
                // déjà dire « vu » dans cette feuille).
                if episode.isUpcoming, let airDate = episode.airDate {
                    Label(ItemStrings.upcoming(airDate.formatted(.dateTime.day().month())), systemImage: "calendar")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .padding(.bottom, 2)
                } else if let airDate = episode.airDate {
                    // En italique : à ne pas confondre avec le synopsis juste dessous.
                    Text(airDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }

                if let overview = episode.overview {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // Hors mode sélection, un tap ouvre le lecteur, seulement pour un épisode
        // lisible (`availability`) : jamais de lecteur ouvert
        // pour rien. Un épisode à venir ne se lit ni ne se marque, mais marqué vu par
        // erreur il doit pouvoir se décocher.
        .onTapGesture {
            if isSelecting {
                guard !episode.isUpcoming || episode.isWatched else { return }
                toggleSelection()
            } else {
                guard !episode.isUpcoming, availability == .playable else { return }
                play()
            }
        }
        #if os(iOS)
        // SweetFin : appui long → télécharger, comme sur les affiches.
        .contextMenu {
            if let downloadableID, !isSelecting, !episode.isUpcoming {
                DownloadButton(item: BaseItemDto(id: downloadableID, type: .episode))
            }
        }
        #endif
    }

    /// Vu : vignette atténuée et coche dans son coin. Sur la vignette et non en bout
    /// de ligne, pour ne rien prendre à la largeur du synopsis.
    private var thumbnail: some View {
        FixedImage(source: episode.thumbnail, width: 128, height: 72)
            .grayscale(isGreyed ? 1 : 0)
            .opacity(episode.isWatched && !isSelecting ? 0.6 : 1)
            .overlay(alignment: .topTrailing) {
                if episode.isWatched, !isSelecting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(accentColor.overlayColor, .tint)
                        .padding(4)
                        .accessibilityLabel(L10n.played)
                }
            }
            #if os(iOS)
            // SweetFin : disponible hors connexion.
            .overlay(alignment: .bottomLeading) {
                if let itemID = episode.jellyfinID, !isSelecting {
                    DownloadedBadge(itemID: itemID)
                }
            }
            #endif
            .overlay(alignment: .bottomTrailing) {
                if let runtimeLabel {
                    Text(runtimeLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                        .padding(4)
                }
            }
    }
}

#if os(iOS)
/// SweetFin : pastille « disponible hors connexion » d'un épisode.
///
/// Seule à observer le gestionnaire de téléchargements : la feuille entière se
/// redessinait sinon à chaque pour-cent d'un téléchargement en cours.
private struct DownloadedBadge: View {

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    private var manager = Container.shared.downloadManager()

    let itemID: String

    private var isDownloaded: Bool {
        guard let userID = Container.shared.currentUserSession()?.user.id else { return false }
        return manager.state(of: itemID, userID: userID) == .done
    }

    var body: some View {
        if isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(accentColor.overlayColor, .tint)
                .padding(4)
                .accessibilityLabel(DownloadStrings.downloaded)
        }
    }
}
#endif

/// Une image dans un cadre **fixe**, remplie et découpée.
///
/// ⚠️ Le cadre d'abord, l'image ensuite : avec `posterStyle` puis `.frame(width:)`,
/// une vignette au format inattendu (4:3 au lieu de 16:9) imposait sa propre taille
/// et débordait sous le texte voisin.
private struct FixedImage: View {

    let source: ImageSource?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.complexSecondary)
            .frame(width: width, height: height)
            .overlay {
                if let source {
                    ImageView(source)
                        .image { $0.aspectRatio(contentMode: .fill) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
