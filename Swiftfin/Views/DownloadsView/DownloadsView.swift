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

extension TabItem {

    /// SweetFin : 4ᵉ onglet, toujours affiché, même vide — la barre ne bouge jamais
    /// et on sait où chercher ses films quand on n'a plus de réseau.
    static var downloads: TabItem {
        TabItem(
            id: "enhancedfin-downloads",
            title: DownloadStrings.downloads,
            systemImage: "arrow.down.app"
        ) {
            DownloadsView()
        }
    }
}

/// SweetFin : les téléchargements du compte connecté.
///
/// Tout vient du disque, via le cache de `DownloadManager.downloads(of:)` : l'écran
/// fonctionne sans serveur. Se redessine à chaque changement d'état publié par le gestionnaire
/// (progression, fin, suppression). Film comme série : une bannière (fond + logo) ; celle
/// d'un film le lance, celle d'une série ouvre sa page (`DownloadedSeriesView`).
struct DownloadsView: View {

    @ObservedObject
    private var manager = Container.shared.downloadManager()

    @Injected(\.currentUserSession)
    private var userSession

    @InjectedObject(\.offlineMonitor)
    private var offlineMonitor

    @Router
    private var router

    var body: some View {
        content
            .safeAreaInset(edge: .top) {
                if offlineMonitor.isOffline {
                    offlineBanner
                }
            }
            .navigationTitle(DownloadStrings.downloads)
            .hidesNavigationTitle()
            // En ligne, reprendre la position connue du serveur : couvre « regardé en
            // streaming, puis plus de réseau sans relancer l'app ». Tâche détachée : la
            // vue ne doit pas pouvoir l'annuler.
            .onAppear {
                guard !offlineMonitor.isOffline, let userSession else { return }
                Task {
                    await manager.syncWithServer(userSession: userSession)
                }
            }
    }

    /// Rappelle que, sans réseau, seuls les téléchargements sont disponibles.
    private var offlineBanner: some View {
        Label(DownloadStrings.offlineBanner, systemImage: "wifi.slash")
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .infoCardStyle()
            .edgePadding(.horizontal)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        let userID = userSession?.user.id ?? ""
        let downloads = manager.downloads(of: userID)

        if downloads.isEmpty {
            ContentUnavailableView(
                DownloadStrings.emptyTitle,
                systemImage: "arrow.down.app",
                description: Text(DownloadStrings.emptyMessage)
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(DownloadStrings.totalSize(downloads.compactMap(\.mediaSource.size).reduce(0) { $0 + Int64($1) }))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(DownloadGroup.make(downloads)) { group in
                        switch group {
                        case let .single(download):
                            downloadRow(download, userID: userID)
                        case let .series(key, episodes):
                            seriesBanner(key: key, episodes: episodes, userID: userID)
                        }
                    }
                }
                .edgePadding(.horizontal)
                .padding(.top, 12)
            }
        }
    }

    /// Un film (ou un épisode sans série) : sa bannière, état et menu en bas. Tap = lecture,
    /// et rien d'autre : l'onglet sert hors connexion, où une fiche n'aurait rien à afficher.
    /// Seul un fichier complet se lit.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : le téléchargement
    /// - userID (String) : compte connecté
    private func downloadRow(_ download: DownloadedItem, userID: String) -> some View {
        let state = manager.state(of: download.id, userID: userID)

        return DownloadBanner(
            title: download.item.displayTitle,
            backdrop: manager.backdrop(of: download.id, userID: userID),
            logo: manager.logo(of: download.id, userID: userID),
            height: 150
        ) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    // Épisode sans série connue : saison et numéro en sous-titre.
                    if download.item.type == .episode, let label = download.item.seasonEpisodeLabel {
                        Text(label)
                            .font(.subheadline)
                            .lineLimit(1)
                    }

                    DownloadStatus(download: download, state: state)
                }

                Spacer(minLength: 0)

                DownloadMenu(state: state) {
                    manager.remove(itemID: download.id, userID: userID)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if download.item.userData?.isPlayed == true {
                PlayedIndicator()
                    .frame(width: 22, height: 22)
                    .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard state == .done else { return }
            router.route(to: manager.videoPlayerRoute(for: download, userID: userID))
        }
    }

    /// Une série : sa bannière, qui ouvre sa page.
    ///
    /// Parametres :
    /// - key (String) : la série (`DownloadedItem.seriesKey`)
    /// - episodes ([DownloadedItem]) : ses épisodes, dans l'ordre
    /// - userID (String) : compte connecté
    private func seriesBanner(key: String, episodes: [DownloadedItem], userID: String) -> some View {
        DownloadBanner(
            title: episodes.seriesTitle,
            backdrop: manager.seriesBackdrop(of: episodes, userID: userID),
            logo: manager.seriesLogo(of: episodes, userID: userID),
            height: 150
        ) {
            HStack {
                Text(episodes.seriesSummary)
                    .font(.subheadline)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            router.route(to: .downloadedSeries(seriesKey: key))
        }
    }
}

/// Une ligne de la liste : un film (ou un épisode sans série connue), ou une série.
private enum DownloadGroup: Identifiable {

    case single(DownloadedItem)
    case series(key: String, episodes: [DownloadedItem])

    var id: String {
        switch self {
        case let .single(download):
            download.id
        case let .series(key, _):
            "series-\(key)"
        }
    }

    /// Regroupe les épisodes par série, à la place de son épisode le plus récent (la liste
    /// arrive du plus récent au plus ancien) ; épisodes triés par saison puis numéro.
    ///
    /// Parametres :
    /// - downloads ([DownloadedItem]) : les téléchargements, du plus récent au plus ancien
    ///
    /// Output :
    /// - groups ([DownloadGroup]) : les lignes de la liste
    static func make(_ downloads: [DownloadedItem]) -> [DownloadGroup] {
        let bySeries = Dictionary(grouping: downloads, by: \.seriesKey)
        var seen: Set<String> = []

        return downloads.compactMap { download in
            guard let key = download.seriesKey else { return .single(download) }
            guard seen.insert(key).inserted else { return nil }

            let episodes = (bySeries[key] ?? []).sorted { $0.episodeOrder < $1.episodeOrder }
            return .series(key: key, episodes: episodes)
        }
    }
}

/// La bannière d'un téléchargement, film ou série : son fond, son logo (son nom à défaut),
/// et en bas le contenu de l'appelant (état, résumé, menu). Dans la liste et en en-tête de
/// la page d'une série.
struct DownloadBanner<Content: View>: View {

    let title: String
    let backdrop: UIImage?
    let logo: UIImage?
    let height: CGFloat
    @ViewBuilder
    let content: () -> Content

    var body: some View {
        // `Color.clear` donne la taille, l'image la remplit sans pousser la mise en page.
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                if let backdrop {
                    Image(uiImage: backdrop)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .overlay {
                // Plus sombre en bas, sous le logo et le texte.
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    titleView
                    content()
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var titleView: some View {
        if let logo {
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180, maxHeight: height * 0.35, alignment: .leading)
                .accessibilityLabel(title)
        } else {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
    }
}

extension [DownloadedItem] {

    /// Le nom de la série de ces épisodes.
    var seriesTitle: String {
        first?.item.seriesName ?? first?.item.displayTitle ?? ""
    }

    /// « 2 épisodes · 2,7 Go ».
    var seriesSummary: String {
        let bytes = compactMap(\.mediaSource.size).reduce(0) { $0 + Int64($1) }
        return DownloadStrings.episodeSummary(count: count, bytes: bytes)
    }
}

/// L'état d'un téléchargement : progression, échec, ou durée · taille une fois fini, avec
/// la barre de visionnage s'il est entamé.
struct DownloadStatus: View {

    let download: DownloadedItem
    let state: DownloadState

    private var details: String {
        let runtime = download.runtimeTicks.map { Duration.ticks($0).formatted(.hourMinuteAbbreviated) }
        let size = DownloadStrings.size(Int64(download.mediaSource.size ?? 0))
        return [runtime, size].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        switch state {
        case .preparing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(DownloadStrings.preparing)
                    .font(.caption)
            }
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text(DownloadStrings.downloading(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label(DownloadStrings.failed, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .done, .none:
            VStack(alignment: .leading, spacing: 6) {
                Text(details)
                    .font(.caption)

                if let progress = download.progress {
                    ProgressView(value: progress)
                        .tint(.white)
                }
            }
        }
    }
}

/// Le menu « ⋯ » d'un téléchargement : supprimer, ou annuler s'il est en cours.
struct DownloadMenu: View {

    let state: DownloadState
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(
                state == .done ? DownloadStrings.deleteDownload : DownloadStrings.cancelDownload,
                systemImage: "trash",
                role: .destructive,
                action: onRemove
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }
}

/// Miniature d'un épisode (16:9) lue sur le disque, sans réseau, coche « vu » en bas à
/// droite ; icône de repli si elle manque.
struct EpisodeThumbnail: View {

    let image: UIImage?
    let isPlayed: Bool

    var body: some View {
        Color.clear
            .frame(width: 128, height: 72)
            .background {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                if isPlayed {
                    PlayedIndicator()
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
            }
    }
}
