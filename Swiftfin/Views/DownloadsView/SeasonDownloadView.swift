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

/// SweetFin : télécharger d'un coup la suite de la saison en cours d'une série, depuis
/// le menu « … » de sa fiche.
///
/// Montre ce qui sera lancé (épisodes, taille totale) avant de lancer : de l'épisode
/// « à suivre » à la fin de sa saison, sans ce qui est déjà téléchargé ou en cours.
struct SeasonDownloadView: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    @ObservedObject
    private var manager = Container.shared.downloadManager()

    let series: BaseItemDto

    @State
    private var episodes: [BaseItemDto]?

    @State
    private var isSending = false

    @State
    private var error: Error?

    /// Les épisodes qui seront réellement lancés.
    private var pending: [BaseItemDto] {
        guard let episodes, let userID = userSession?.user.id else { return [] }

        return episodes.filter { $0.canBeDownloaded && manager.state(of: $0.id ?? "", userID: userID) == .none }
    }

    private var totalSize: Int64 {
        pending.compactMap { $0.mediaSources?.first?.size }.reduce(0) { $0 + Int64($1) }
    }

    var body: some View {
        Form {
            if episodes == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if pending.isEmpty {
                Text(DownloadStrings.nothingToDownload)
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(pending, id: \.id) { episode in
                        LabeledContent(episode.seasonEpisodeLabel ?? episode.displayTitle) {
                            Text(episode.mediaSources?.first?.size.map { DownloadStrings.size(Int64($0)) } ?? "")
                        }
                    }
                } header: {
                    Text([series.name, pending.first?.seasonName].compactMap(\.self).joined(separator: " · "))
                } footer: {
                    Text(DownloadStrings.seasonSummary(count: pending.count, bytes: totalSize))
                }
            }
        }
        .navigationTitle(DownloadStrings.downloadSeason)
        .toolbarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSending)
        .navigationBarCloseButton(disabled: isSending) {
            router.dismiss()
        }
        .topBarTrailing {
            if isSending {
                ProgressView()
            } else {
                Button(DownloadStrings.download) {
                    Task { await send() }
                }
                .backport
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .enabled(pending.isNotEmpty)
            }
        }
        .task {
            await load()
        }
        .errorMessage($error)
    }

    /// Charge la suite de la saison ; une erreur laisse la liste vide.
    private func load() async {
        guard let userSession else { return }

        do {
            episodes = try await manager.remainingEpisodes(of: series, userSession: userSession)
        } catch {
            episodes = []
            self.error = error
        }
    }

    /// Lance les téléchargements puis ferme la feuille ; l'onglet Téléchargements prend
    /// le relais. Une erreur (espace insuffisant) garde la feuille ouverte.
    private func send() async {
        guard let userSession else { return }

        isSending = true
        defer { isSending = false }

        do {
            try await manager.start(pending, userSession: userSession)
            router.dismiss()
        } catch {
            self.error = error
        }
    }
}
