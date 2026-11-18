//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import JellyfinAPI
import SwiftUI

/// SweetFin : la file d'un épisode lu depuis les téléchargements : précédent / suivant
/// parmi les **épisodes téléchargés de la même série**, dans l'ordre saison puis épisode,
/// et leur liste dans le panneau ▤.
///
/// Sans elle, une lecture locale n'avait pas de file : ni ⏮ ⏭, ni enchaînement (vécu le
/// 2026-11-16). `EpisodeMediaPlayerQueue` ne convient pas : elle demande les épisodes au
/// serveur.
@MainActor
final class DownloadedEpisodeQueue: MediaPlayerQueue {

    weak var manager: MediaPlayerManager? {
        didSet {
            cancellable = manager?.$playbackItem
                .sink { [weak self] newItem in
                    self?.didReceive(newItem: newItem)
                }
        }
    }

    let displayTitle: String = L10n.episodes
    let id: String = "DownloadedEpisodeQueue"

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

    /// Les épisodes téléchargés de la série, dans l'ordre ; relus à chaque épisode lancé
    /// (coche « vu » et barre à jour dans le panneau).
    @Published
    private(set) var episodes: [DownloadedItem]
    private let userID: String
    private var cancellable: AnyCancellable?

    /// Parametres :
    /// - episodes ([DownloadedItem]) : épisodes téléchargés de la série, dans l'ordre
    /// - userID (String) : compte propriétaire des téléchargements
    init(episodes: [DownloadedItem], userID: String) {
        self.episodes = episodes
        self.userID = userID
    }

    var videoPlayerBody: some PlatformView {
        DownloadedEpisodeList(queue: self)
    }

    /// Le fournisseur de lecture locale d'un épisode.
    ///
    /// Parametres :
    /// - episode (DownloadedItem) : épisode téléchargé
    ///
    /// Output :
    /// - provider (MediaPlayerItemProvider) : à passer au lecteur
    func provider(for episode: DownloadedItem) -> MediaPlayerItemProvider {
        Container.shared.downloadManager().playbackProvider(for: episode, userID: userID)
    }

    /// La miniature enregistrée d'un épisode.
    ///
    /// Parametres :
    /// - episode (DownloadedItem) : épisode téléchargé
    ///
    /// Output :
    /// - image (UIImage?) : la miniature, `nil` si elle manque
    func thumbnail(of episode: DownloadedItem) -> UIImage? {
        Container.shared.downloadManager().thumbnail(of: episode.id, userID: userID)
    }

    /// Vrai si l'item lu est cet épisode : même id, la lecture locale et la file lisant le
    /// même `item.json`. ❌ Par saison et numéro : deux épisodes spéciaux sans numéro
    /// étaient confondus.
    ///
    /// Parametres :
    /// - episode (DownloadedItem) : épisode téléchargé
    /// - item (BaseItemDto?) : l'item en lecture
    ///
    /// Output :
    /// - isCurrent (Bool) : vrai si c'est le même épisode
    static func isCurrent(_ episode: DownloadedItem, playing item: BaseItemDto?) -> Bool {
        episode.item.id != nil && episode.item.id == item?.id
    }

    /// Relit les fiches : la position notée pendant l'épisode qui vient de finir y est
    /// recopiée d'abord (pas d'arrêt du lecteur entre deux épisodes enchaînés). ❌ Sans :
    /// coches et barres du panneau figées à l'ouverture du lecteur.
    private func refreshEpisodes() {
        let manager = Container.shared.downloadManager()
        episodes.forEach { manager.applyLocalProgress(of: $0, userID: userID) }

        let fresh = Dictionary(manager.downloads(of: userID).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        episodes = episodes.compactMap { fresh[$0.id] }
    }

    /// Recalcule précédent et suivant autour de l'épisode qui démarre.
    ///
    /// Parametres :
    /// - newItem (MediaPlayerItem?) : l'item lancé
    private func didReceive(newItem: MediaPlayerItem?) {
        refreshEpisodes()
        let index = episodes.firstIndex { Self.isCurrent($0, playing: newItem?.baseItem) }

        nextItem = index.flatMap { episodes[safe: $0 + 1] }.map(provider)
        previousItem = index.flatMap { $0 > 0 ? episodes[$0 - 1] : nil }.map(provider)
        hasNextItem = nextItem != nil
        hasPreviousItem = previousItem != nil
    }
}

/// Le panneau ▤ hors ligne, au rendu du panneau en ligne (`EpisodeMediaPlayerQueue`) :
/// une rangée de cartes 16:9 — miniature enregistrée, coche « vu », barre de visionnage,
/// « E8 · Titre » dessous —, l'épisode en cours encadré. Un tap lance l'épisode.
/// ❌ 1ʳᵉ version : une liste de textes collée au bord de l'écran, sans fond ni marges.
private struct DownloadedEpisodeList: PlatformView {

    private static let cardWidth: CGFloat = 170

    @Environment(\.safeAreaInsets)
    private var safeAreaInsets

    @EnvironmentObject
    private var manager: MediaPlayerManager

    @ObservedObject
    var queue: DownloadedEpisodeQueue

    var iOSView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: EdgeInsets.edgePadding / 2) {
                    ForEach(queue.episodes) { episode in
                        card(episode)
                            .id(episode.id)
                    }
                }
                .padding(.horizontal, max(safeAreaInsets.leading, safeAreaInsets.trailing) + EdgeInsets.edgePadding)
            }
            .onAppear {
                // L'épisode en cours à l'écran, comme en ligne ; un tour plus tard, une fois
                // la rangée mise en page.
                guard let id = queue.episodes.first(where: { DownloadedEpisodeQueue.isCurrent($0, playing: manager.item) })?.id else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .leading)
                }
            }
        }
    }

    var tvOSView: some View {
        EmptyView()
    }

    /// Une carte : miniature, puis « E8 · Titre ».
    ///
    /// Parametres :
    /// - episode (DownloadedItem) : épisode téléchargé
    private func card(_ episode: DownloadedItem) -> some View {
        let isCurrent = DownloadedEpisodeQueue.isCurrent(episode, playing: manager.item)

        return Button {
            manager.playNewItem(provider: queue.provider(for: episode))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                EpisodeThumbnail(
                    image: queue.thumbnail(of: episode),
                    isPlayed: episode.item.userData?.isPlayed == true,
                    width: Self.cardWidth,
                    progress: episode.progress
                )
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white, lineWidth: 3)
                    }
                }

                Text(episode.item.episodeShortTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: Self.cardWidth, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
