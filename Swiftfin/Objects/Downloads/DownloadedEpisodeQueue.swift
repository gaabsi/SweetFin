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

    /// Les épisodes téléchargés de la série, dans l'ordre.
    let episodes: [DownloadedItem]
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

    /// Recalcule précédent et suivant autour de l'épisode qui démarre.
    ///
    /// Parametres :
    /// - newItem (MediaPlayerItem?) : l'item lancé
    private func didReceive(newItem: MediaPlayerItem?) {
        let index = episodes.firstIndex { Self.isCurrent($0, playing: newItem?.baseItem) }

        nextItem = index.flatMap { episodes[safe: $0 + 1] }.map(provider)
        previousItem = index.flatMap { $0 > 0 ? episodes[$0 - 1] : nil }.map(provider)
        hasNextItem = nextItem != nil
        hasPreviousItem = previousItem != nil
    }
}

/// Le panneau ▤ hors ligne : les épisodes téléchargés de la série, l'épisode en cours
/// coché ; un tap lance l'épisode.
private struct DownloadedEpisodeList: PlatformView {

    @EnvironmentObject
    private var manager: MediaPlayerManager

    let queue: DownloadedEpisodeQueue

    var iOSView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(queue.episodes) { episode in
                    row(episode)
                }
            }
        }
        .foregroundStyle(.white)
    }

    var tvOSView: some View {
        EmptyView()
    }

    private func row(_ episode: DownloadedItem) -> some View {
        Button {
            manager.playNewItem(provider: queue.provider(for: episode))
        } label: {
            HStack(spacing: 12) {
                Text([episode.item.seasonEpisodeLabel, episode.item.displayTitle].compactMap(\.self).joined(separator: " · "))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if DownloadedEpisodeQueue.isCurrent(episode, playing: manager.item) {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
