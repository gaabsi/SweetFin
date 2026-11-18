//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

/// SweetFin : la page d'une série téléchargée, ouverte depuis sa bannière dans l'onglet
/// Téléchargements : grande bannière, puis ses épisodes par saison (miniature, coche « vu »,
/// durée · taille, barre de visionnage). Tap = lecture, avec la file de la série.
///
/// Tout vient du disque : elle fonctionne sans réseau. Se referme d'elle-même quand le
/// dernier épisode est supprimé.
struct DownloadedSeriesView: View {

    @ObservedObject
    private var manager = Container.shared.downloadManager()

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    /// La série (`DownloadedItem.seriesKey`).
    let seriesKey: String

    private var userID: String {
        userSession?.user.id ?? ""
    }

    private var episodes: [DownloadedItem] {
        manager.downloads(of: userID)
            .filter { $0.seriesKey == seriesKey }
            .sorted { $0.episodeOrder < $1.episodeOrder }
    }

    var body: some View {
        let episodes = episodes
        let seasons = Dictionary(grouping: episodes) { $0.item.parentIndexNumber ?? 0 }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if episodes.isNotEmpty {
                    DownloadBanner(
                        title: episodes.seriesTitle,
                        backdrop: manager.seriesBackdrop(of: episodes, userID: userID),
                        logo: manager.seriesLogo(of: episodes, userID: userID),
                        height: 220
                    ) {
                        Text(episodes.seriesSummary)
                            .font(.subheadline)
                    }
                }

                ForEach(seasons.keys.sorted(), id: \.self) { season in
                    let seasonEpisodes = seasons[season] ?? []

                    Text(seasonEpisodes.first?.item.seasonName ?? "\(L10n.season) \(season)")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 8)

                    ForEach(seasonEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
            .edgePadding(.horizontal)
            .padding(.top, 12)
        }
        .navigationTitle(episodes.seriesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: episodes.isEmpty) {
            if episodes.isEmpty {
                router.dismiss()
            }
        }
    }

    /// Un épisode : miniature, « E4 · Titre », état, menu. Tap = lecture d'un fichier complet.
    ///
    /// Parametres :
    /// - episode (DownloadedItem) : l'épisode téléchargé
    private func episodeRow(_ episode: DownloadedItem) -> some View {
        let state = manager.state(of: episode.id, userID: userID)

        return HStack(alignment: .top, spacing: 12) {
            EpisodeThumbnail(
                image: manager.thumbnail(of: episode.id, userID: userID),
                isPlayed: episode.item.userData?.isPlayed == true
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(episode.item.episodeShortTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                DownloadStatus(download: episode, state: state)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            DownloadMenu(state: state) {
                manager.remove(itemID: episode.id, userID: userID)
            }
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture {
            guard state == .done else { return }
            router.route(to: manager.videoPlayerRoute(for: episode, userID: userID))
        }
    }
}
