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
            systemImage: "arrow.down.circle"
        ) {
            DownloadsView()
        }
    }
}

/// SweetFin : les téléchargements du compte connecté.
///
/// Tout vient du disque (`DownloadManager.downloads(of:)`) : l'écran fonctionne sans
/// serveur. Se redessine à chaque changement d'état publié par le gestionnaire
/// (progression, fin, suppression). Cartes au style du bloc « Infos » des fiches.
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
            // En ligne, reprendre la position connue de Jellyfin : couvre « regardé en
            // streaming, puis plus de réseau sans relancer l'app ». Tâche détachée : la
            // vue ne doit pas pouvoir l'annuler.
            .onAppear {
                guard !offlineMonitor.isOffline, let userSession else { return }
                Task {
                    await manager.refreshStoredProgress(userSession: userSession)
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
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
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
                systemImage: "arrow.down.circle",
                description: Text(DownloadStrings.emptyMessage)
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(DownloadStrings.totalSize(downloads.compactMap(\.mediaSource.size).reduce(0) { $0 + Int64($1) }))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(downloads) { download in
                        let state = manager.state(of: download.id, userID: userID)

                        DownloadCard(
                            download: download,
                            state: state,
                            posterURL: manager.posterURL(of: download.id, userID: userID)
                        ) {
                            manager.remove(itemID: download.id, userID: userID)
                        }
                        // Tap = lecture, et rien d'autre : l'onglet sert hors connexion, où
                        // une fiche n'aurait rien à afficher. Seul un fichier complet se lit.
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
                            guard state == .done else { return }
                            router.route(to: .videoPlayer(provider: manager.playbackProvider(for: download, userID: userID)))
                        }
                    }
                }
                .edgePadding(.horizontal)
                .padding(.top, 12)
            }
        }
    }
}

/// Une carte : affiche, titre, taille ou état, et un menu pour supprimer. Le tap (lecture)
/// est posé par la liste.
private struct DownloadCard: View {

    let download: DownloadedItem
    let state: DownloadState
    let posterURL: URL?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            poster

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                status
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

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
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    /// Film : son nom. Épisode : la série, le nom de l'épisode passant en sous-titre.
    private var title: String {
        download.item.seriesName ?? download.item.displayTitle
    }

    private var subtitle: String? {
        guard download.item.type == .episode else { return nil }
        return [download.item.seasonEpisodeLabel, download.item.name]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        switch state {
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
            Label(DownloadStrings.size(Int64(download.mediaSource.size ?? 0)), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Affiche lue sur le disque, sans réseau ; icône de repli si elle manque.
    @ViewBuilder
    private var poster: some View {
        let image = posterURL.flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }

        Group {
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
        .frame(width: 64, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
