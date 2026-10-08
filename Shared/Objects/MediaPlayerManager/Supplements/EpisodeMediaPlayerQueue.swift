//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import CollectionVGrid
import Combine
import Defaults
import Foundation
import IdentifiedCollections
import JellyfinAPI
import SwiftUI

@MainActor
class EpisodeMediaPlayerQueue: ViewModel, MediaPlayerQueue {

    weak var manager: MediaPlayerManager? {
        didSet {
            cancellables = []
            guard let manager else { return }
            manager.$playbackItem
                .sink { [weak self] newItem in
                    self?.didReceive(newItem: newItem)
                }
                .store(in: &cancellables)
        }
    }

    let displayTitle: String = L10n.episodes
    let id: String = "EpisodeMediaPlayerQueue"

    @Published
    var nextItem: MediaPlayerItemProvider? = nil
    @Published
    var previousItem: MediaPlayerItemProvider? = nil

    @Published
    var hasNextItem: Bool = false
    @Published
    var hasPreviousItem: Bool = false

    lazy var hasNextItemPublisher: Published<Bool>.Publisher = $hasNextItem
    lazy var hasPreviousItemPublisher: Published<Bool>.Publisher = $hasPreviousItem
    lazy var nextItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $nextItem
    lazy var previousItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $previousItem

    private var currentAdjacentEpisodesTask: AnyCancellable?
    private let seasonsViewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

    /// SweetFin : clé de la série quand elle est **hors bibliothèque** (l'épisode lu
    /// n'a alors pas de `seriesID`) : saisons et épisodes viennent du plugin, et un
    /// épisode se lance par `MediaPlayerItemProvider.episode`. `nil` = série du serveur.
    private let mediaKey: String?

    /// Parametres :
    /// - episode (BaseItemDto) : l'épisode lancé
    /// - seriesKey (String?) : clé de la série, connue du point de lancement ; ne sert
    ///   que si l'épisode n'a pas de série sur le serveur
    init(episode: BaseItemDto, seriesKey: String? = nil) {
        self.mediaKey = episode.seriesID == nil ? seriesKey : nil
        let seriesID = episode.seriesID ?? seriesKey.map { EnhancedFinSyntheticItem.id(for: $0) }
        self.seasonsViewModel = PagingLibraryViewModel(
            library: SeasonViewModelLibrary(
                parent: BaseItemDto(id: seriesID, name: episode.seriesName)
            ),
            pageSize: 100
        )
        super.init()

        seasonsViewModel.refresh()
    }

    var videoPlayerBody: some PlatformView {
        EpisodeOverlay(viewModel: seasonsViewModel, mediaKey: mediaKey)
    }

    /// SweetFin : l'épisode en cours d'une série hors bibliothèque n'a pas l'id de sa
    /// carte (il porte celui du serveur qui le lit) : on compare saison et numéro.
    static func isCurrent(_ episode: BaseItemDto, playing: BaseItemDto) -> Bool {
        guard EnhancedFinSyntheticItem.isSynthetic(episode.id) else { return playing.id == episode.id }
        return playing.parentIndexNumber == episode.parentIndexNumber && playing.indexNumber == episode.indexNumber
    }

    private func didReceive(newItem: MediaPlayerItem?) {
        self.currentAdjacentEpisodesTask = Task {
            await MainActor.run {
                self.nextItem = nil
                self.previousItem = nil
                self.hasNextItem = false
                self.hasPreviousItem = false
            }

            try await self.getAdjacentEpisodes(for: newItem?.baseItem)
        }
        .asAnyCancellable()
    }

    private func getAdjacentEpisodes(for item: BaseItemDto?) async throws {
        guard let item else { return }
        if let mediaKey {
            try await getAdjacentEnhancedFinEpisodes(for: item, mediaKey: mediaKey)
            return
        }
        guard let seriesID = item.seriesID, item.type == .episode else { return }

        let parameters = try Paths.GetEpisodesParameters(
            userID: authenticatedUser.id,
            adjacentTo: item.id!,
            limit: 3
        )
        let request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
        let response = try await send(request)

        // 4 possible states:
        //  1 - only current episode
        //  2 - two episodes with next episode
        //  3 - two episodes with previous episode
        //  4 - three episodes with current in middle

        // 1
        guard let items = response.value.items, items.count > 1 else { return }

        var previousItem: BaseItemDto?
        var nextItem: BaseItemDto?

        if items.count == 2 {
            if items[0].id == item.id {
                // 2
                nextItem = items[1]

            } else {
                // 3
                previousItem = items[0]
            }
        } else {
            nextItem = items[2]
            previousItem = items[0]
        }

        var nextProvider: MediaPlayerItemProvider?
        var previousProvider: MediaPlayerItemProvider?

        if let nextItem {
            nextProvider = MediaPlayerItemProvider(item: nextItem) { item, modifyItem in
                try await MediaPlayerItem.build(for: item) { item in
                    item.userData?.playbackPositionTicks = .zero
                    modifyItem?(&item)
                }
            }
        }

        if let previousItem {
            previousProvider = MediaPlayerItemProvider(item: previousItem) { item, modifyItem in
                try await MediaPlayerItem.build(for: item) { item in
                    item.userData?.playbackPositionTicks = .zero
                    modifyItem?(&item)
                }
            }
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            self.nextItem = nextProvider
            self.previousItem = previousProvider
            self.hasNextItem = nextProvider != nil
            self.hasPreviousItem = previousProvider != nil
        }
    }
}

extension EpisodeMediaPlayerQueue {

    /// SweetFin : précédent et suivant d'un épisode hors bibliothèque, d'après les
    /// saisons TMDB du plugin (dernier épisode → premier de la saison suivante).
    /// Rien n'est résolu d'avance : chacun se résout quand on le lance.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'épisode en cours
    /// - mediaKey (String) : clé de la série
    private func getAdjacentEnhancedFinEpisodes(for item: BaseItemDto, mediaKey: String) async throws {
        guard let season = item.parentIndexNumber, let number = item.indexNumber,
              let client = userSession?.enhancedFinClient
        else { return }

        let seasons = try await client.seasons(mediaKey).map(\.number).sorted()
        let current = try await client.season(mediaKey, number: season).episodes.map(\.number).sorted()

        func episodeItem(_ season: Int, _ episode: Int) -> BaseItemDto {
            EnhancedFinSyntheticItem.makeEpisode(mediaKey: mediaKey, seriesTitle: item.seriesName, season: season, episode: episode, name: nil)
        }

        var previous = current.last(where: { $0 < number }).map { episodeItem(season, $0) }
        var next = current.first(where: { $0 > number }).map { episodeItem(season, $0) }

        if previous == nil, let earlier = seasons.last(where: { $0 < season }),
           let last = try await client.season(mediaKey, number: earlier).episodes.map(\.number).max()
        {
            previous = episodeItem(earlier, last)
        }
        if next == nil, let later = seasons.first(where: { $0 > season }),
           let first = try await client.season(mediaKey, number: later).episodes.map(\.number).min()
        {
            next = episodeItem(later, first)
        }

        guard !Task.isCancelled else { return }

        // Préchauffage de n+1 : demander dès maintenant s'il est lisible fait préparer
        // au serveur release, lien et sondage, qu'il garde. « Suivant » et
        // l'enchaînement partiront de ce cache.
        if let next, let nextSeason = next.parentIndexNumber, let nextEpisode = next.indexNumber {
            Task { _ = try? await client.playable(mediaKey, season: nextSeason, episode: nextEpisode) }
        }

        let nextProvider = next.map { MediaPlayerItemProvider.episode($0, mediaKey: mediaKey, fromStart: true) }
        let previousProvider = previous.map { MediaPlayerItemProvider.episode($0, mediaKey: mediaKey, fromStart: true) }

        await MainActor.run {
            self.nextItem = nextProvider
            self.previousItem = previousProvider
            self.hasNextItem = nextProvider != nil
            self.hasPreviousItem = previousProvider != nil
        }
    }

    private struct EpisodeOverlay: PlatformView {

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @ObservedObject
        var viewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        /// SweetFin : clé de la série hors bibliothèque, `nil` pour une série du serveur.
        let mediaKey: String?

        @State
        private var selection: PagingLibraryViewModel<EpisodeLibrary>.ID?

        private var selectionViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            guard let selection else { return nil }
            return viewModel.elements[id: selection]
        }

        private func select(episode: BaseItemDto) {
            // SweetFin : hors bibliothèque, l'épisode est résolu à l'ouverture (roue).
            if mediaKey != nil {
                manager.playNewItem(provider: .episode(episode, mediaKey: mediaKey))
                return
            }

            let provider = MediaPlayerItemProvider(item: episode) { item, modifyItem in
                try await MediaPlayerItem.build(for: item, modifyItem: modifyItem)
            }

            manager.playNewItem(provider: provider)
        }

        private func selectInitialSeason() {
            // SweetFin : hors bibliothèque, la saison se retrouve par son numéro.
            let seasonID = manager.item.seasonID
                ?? mediaKey.map { EnhancedFinSyntheticItem.id(for: $0, season: manager.item.parentIndexNumber) }
            if let seasonID, let season = viewModel.elements[id: seasonID] {
                if season.elements.isEmpty {
                    season.refresh()
                }
                selection = season.id
            } else {
                selection = viewModel.elements.first?.id
            }
        }

        private func setSelectionIfNeeded(seasons: IdentifiedArrayOf<PagingLibraryViewModel<EpisodeLibrary>>) {
            guard selection == nil, !seasons.isEmpty else { return }
            selection = seasons.first?.id
            seasons.first?.refresh()
        }

        var iOSView: some View {
            CompactOrRegularView(
                isCompact: containerState.isCompact
            ) {
                CompactSeasonStackObserver(
                    selection: $selection,
                    action: select
                )
            } regularView: {
                RegularSeasonStackObserver(
                    selection: $selection,
                    action: select
                )
            }
            .onAppear { selectInitialSeason() }
            .onReceive(viewModel.$elements) { newSeasons in
                setSelectionIfNeeded(seasons: newSeasons)
            }
            .environmentObject(viewModel)
        }

        var tvOSView: some View {
            RegularSeasonStackObserver(
                selection: $selection,
                action: select
            )
            .onFirstAppear {
                selectInitialSeason()
            }
            .onReceive(viewModel.$elements) { newSeasons in
                setSelectionIfNeeded(seasons: newSeasons)
            }
            .environmentObject(viewModel)
        }
    }

    private struct CompactSeasonStackObserver: View {

        @EnvironmentObject
        private var seasonsViewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        let selection: Binding<PagingLibraryViewModel<EpisodeLibrary>.ID?>
        let action: (BaseItemDto) -> Void

        private var selectionViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            guard let id = selection.wrappedValue else { return nil }
            return seasonsViewModel.elements[id: id]
        }

        private struct _Body: View {

            // SweetFin : lu ici et passé à `EpisodeRow`, voir la note d'`EpisodeButton`.
            @EnvironmentObject
            private var manager: MediaPlayerManager

            @ObservedObject
            var selectionViewModel: PagingLibraryViewModel<EpisodeLibrary>

            let action: (BaseItemDto) -> Void

            var body: some View {
                switch selectionViewModel.state {
                case .content:
                    if selectionViewModel.elements.isNotEmpty {
                        CollectionVGrid(
                            uniqueElements: selectionViewModel.elements,
                            layout: .columns(
                                1,
                                insets: .edgeInsets
                            )
                        ) { item in
                            EpisodeRow(episode: item, isSelected: EpisodeMediaPlayerQueue.isCurrent(item, playing: manager.item)) {
                                action(item)
                            }
                        }
                    }
                case .initial, .refreshing:
                    EmptyView()
                case .error:
                    ErrorView(error: ErrorMessage(L10n.unknownError))
                }
            }
        }

        var body: some View {
            if let selectionViewModel {
                _Body(
                    selectionViewModel: selectionViewModel,
                    action: action
                )
            }
        }
    }

    private struct RegularSeasonStackObserver: View {

        @EnvironmentObject
        private var seasonsViewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        let selection: Binding<PagingLibraryViewModel<EpisodeLibrary>.ID?>
        let action: (BaseItemDto) -> Void

        private var selectionViewModel: PagingLibraryViewModel<EpisodeLibrary>? {
            guard let id = selection.wrappedValue else { return nil }
            return seasonsViewModel.elements[id: id]
        }

        private struct _Body: View {

            #if !os(tvOS)
            @Environment(\.safeAreaInsets)
            private var safeAreaInsets: EdgeInsets
            #endif

            // SweetFin : lu ici et passé à `EpisodeButton`, voir sa note.
            @EnvironmentObject
            private var manager: MediaPlayerManager

            @ObservedObject
            var selectionViewModel: PagingLibraryViewModel<EpisodeLibrary>

            let action: (BaseItemDto) -> Void

            @ViewBuilder
            private var contentView: some View {
                #if os(tvOS)
                CollectionHStack(
                    uniqueElements: selectionViewModel.elements,
                    id: \.id,
                    layout: .grid(columns: 5, rows: 1, columnTrailingInset: 0)
                ) { episode in
                    EpisodeButton(episode: episode, isSelected: EpisodeMediaPlayerQueue.isCurrent(episode, playing: manager.item)) {
                        action(episode)
                    }
                }
                .ignoresSafeArea(.container, edges: .horizontal)
                .focusSection()
                #else
                CollectionHStack(
                    uniqueElements: selectionViewModel.elements,
                    id: \.id,
                    layout: .minimumWidth(columnWidth: 170, rows: 1)
                ) { item in
                    EpisodeButton(episode: item, isSelected: EpisodeMediaPlayerQueue.isCurrent(item, playing: manager.item)) {
                        action(item)
                    }
                }
                .clipsToBounds(false)
                .insets(horizontal: max(safeAreaInsets.leading, safeAreaInsets.trailing) + EdgeInsets.edgePadding)
                .itemSpacing(EdgeInsets.edgePadding / 2)
                .scrollBehavior(.continuousLeadingEdge)
                #endif
            }

            var body: some View {
                switch selectionViewModel.state {
                case .content:
                    if selectionViewModel.elements.isNotEmpty {
                        contentView
                    }
                case .initial, .refreshing:
                    EmptyView()
                case .error:
                    SeasonErrorView(viewModel: selectionViewModel)
                }
            }
        }

        var body: some View {
            if let selectionViewModel {
                _Body(
                    selectionViewModel: selectionViewModel,
                    action: action
                )
            }
        }
    }

    private struct SeasonErrorView: View {

        @FocusState
        private var isRetryButtonFocused: Bool

        @ObservedObject
        var viewModel: PagingLibraryViewModel<EpisodeLibrary>

        // TODO: Supplements are dismissed on retry, probably due to focus change
        @ViewBuilder
        private var retryButton: some View {
            AlternateLayoutView {
                Label(L10n.retry, systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding()
                    .edgePadding(.horizontal)
                    .frame(height: UIDevice.isTV ? 80 : 40)
            } content: {
                Button {
                    viewModel.refresh()
                } label: {
                    Label(L10n.retry, systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding()
                        .edgePadding(.horizontal)
                }
                .buttonStyle(.supplementAction)
                .focused($isRetryButtonFocused)
                .frame(height: UIDevice.isTV ? 80 : 50)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: EdgeInsets.edgePadding / 2) {
                Text(L10n.unknownError)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                retryButton
            }
            .edgePadding(.horizontal)
            .padding(.vertical, EdgeInsets.edgePadding / 2)
            .background {
                RoundedRectangle(cornerRadius: 32)
                    .fill(Material.thin)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .edgePadding()
            .focusSection()
        }
    }

    private struct EpisodePreview: View {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.isSelected)
        private var isSelected

        let episode: BaseItemDto

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(.complexSecondary)

                ImageView(episode.imageSource(.primary, environment: ImageSourceOptions(maxWidth: 200)))
                    .failure {
                        SystemImageContentView(systemName: episode.systemImage)
                    }
            }
            .overlay {
                if isSelected {
                    ContainerRelativeShape()
                        .stroke(
                            accentColor,
                            lineWidth: UIDevice.isTV ? 12 : 8
                        )
                        .clipped()
                }
            }
            .posterStyle(.landscape)
            .subtleShadow()
            .hoverEffect(.highlight)
        }
    }

    private struct EpisodeDescription: View {

        let episode: BaseItemDto

        var body: some View {
            DotHStack {
                if let seasonEpisodeLabel = episode.seasonEpisodeLabel {
                    Text(seasonEpisodeLabel)
                }

                if let runtime = episode.runTimeLabel {
                    Text(runtime)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // SweetFin : même correctif qu'`EpisodeButton`, pour `CollectionVGrid`.
    private struct EpisodeRow: View {

        let episode: BaseItemDto
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            ListRow(insets: .init(horizontal: EdgeInsets.edgePadding)) {
                EpisodePreview(episode: episode)
                    .frame(width: 110)
                    .padding(.vertical, 8)
            } content: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    EpisodeDescription(episode: episode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } action: {
                action()
            }
            .isSelected(isSelected)
        }
    }

    // SweetFin : plus de `@EnvironmentObject` ici. `CollectionHStack` et
    // `CollectionVGrid` mesurent la première cellule dans un `UIHostingController`
    // vierge, sans environnement : lire le manager y faisait planter l'ouverture du
    // panneau « Épisodes » (depuis la mise à jour des paquets upstream `a1c5abb5`).
    // Le parent passe `isSelected`.
    private struct EpisodeButton: View {

        let episode: BaseItemDto
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            PosterButton(
                item: episode._withLandscapeImages { environment in
                    [
                        episode.imageSource(
                            .primary,
                            environment: environment
                        )
                    ]
                },
                displayType: .landscape
            ) { _ in
                action()
            }
            .isSelected(isSelected)
            // SweetFin : pas de nom de série sous la tuile, on est déjà dans la série. Posé
            // ici et non autour de la cellule : `CollectionHStack` la mesure sans environnement.
            .withViewContext(.isInParent)
        }
    }
}
