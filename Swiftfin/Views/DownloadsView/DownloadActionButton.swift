//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI

extension ItemActionButtons {

    /// EnhancedFin : télécharger l'item pour le lire hors connexion.
    ///
    /// Vit dans le menu « ⋯ » de la fiche : un seul emplacement, quatre états — absent
    /// (télécharger), en cours (pourcentage, sous-menu pour annuler), terminé (sous-menu
    /// pour supprimer), échec (sous-menu pour réessayer ou supprimer). Un menu n'affiche
    /// que du texte et des symboles système : pas d'anneau de progression ici.
    struct Download: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider
        @EnvironmentObject
        private var toastProxy: ToastProxy

        @ObservedObject
        private var manager = Container.shared.downloadManager()

        @Injected(\.currentUserSession)
        private var userSession

        var body: some View {
            if let itemID = provider.item.id, let userSession {
                switch manager.state(of: itemID, userID: userSession.user.id) {
                case .none:
                    Button(DownloadStrings.download, systemImage: ItemActionButton.download.secondarySystemImage) {
                        start(userSession: userSession)
                    }
                case let .downloading(progress):
                    Menu {
                        removeButton(DownloadStrings.cancelDownload, itemID: itemID, userID: userSession.user.id)
                    } label: {
                        Label(DownloadStrings.downloading(progress), systemImage: "arrow.down.circle.dotted")
                    }
                case .done:
                    Menu {
                        removeButton(DownloadStrings.deleteDownload, itemID: itemID, userID: userSession.user.id)
                    } label: {
                        Label(DownloadStrings.downloaded, systemImage: ItemActionButton.download.systemImage)
                    }
                    .isSelected(true)
                case .failed:
                    Menu {
                        Button(DownloadStrings.retryDownload, systemImage: "arrow.clockwise") {
                            start(userSession: userSession)
                        }
                        removeButton(DownloadStrings.deleteDownload, itemID: itemID, userID: userSession.user.id)
                    } label: {
                        Label(DownloadStrings.retryDownload, systemImage: "exclamationmark.arrow.circlepath")
                    }
                }
            }
        }

        /// Lance le téléchargement ; une erreur (espace insuffisant, source absente)
        /// s'affiche en toast, rien n'est lancé.
        ///
        /// Parametres :
        /// - userSession (UserSession) : compte connecté
        private func start(userSession: UserSession) {
            Task {
                do {
                    try await manager.start(provider.item, userSession: userSession)
                } catch {
                    toastProxy.present(error.localizedDescription, systemName: "exclamationmark.triangle")
                }
            }
        }

        private func removeButton(_ title: String, itemID: String, userID: String) -> some View {
            Button(title, systemImage: "trash", role: .destructive) {
                manager.remove(itemID: itemID, userID: userID)
            }
        }
    }
}
