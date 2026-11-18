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

extension ItemActionButtons {

    /// SweetFin : le téléchargement dans le menu « ⋯ » de la fiche.
    struct Download: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        var body: some View {
            if let target = provider.downloadTarget {
                DownloadButton(item: target.item, storageID: target.storageID)
            }
        }
    }
}

extension ItemContentGroupProvider {

    /// SweetFin : ce que le bouton Télécharger de la fiche télécharge, seule règle du bouton
    /// et de sa présence. V1 : un fichier = un film ou un épisode. Fiche hors médiathèque
    /// (synthétique, sans `canDownload`) : l'item lisible renvoyé par le serveur, s'il
    /// l'autorise, rangé sous l'id de la fiche (stable, contrairement au sien).
    ///
    /// Output :
    /// - target ((item: BaseItemDto, storageID: String?)?) : `nil` si rien à télécharger
    var downloadTarget: (item: BaseItemDto, storageID: String?)? {
        guard [.movie, .episode].contains(item.type) else { return nil }
        if item.canBeDownloaded { return (item, nil) }
        if let playable = mediaPlayerItemProvider?.item, playable.canBeDownloaded { return (playable, item.id) }
        return nil
    }
}

extension ItemContentGroupProvider {

    /// SweetFin : « Télécharger la suite » est proposé pour une série, compte
    /// autorisé à télécharger : de la médiathèque, ou connue par sa clé **si le serveur sait
    /// la lire** (`mediaPlayerItemProvider`). Sinon rien à télécharger : pas de bouton, en
    /// particulier sur un serveur qui n'a pas ce contenu.
    var canDownloadSeason: Bool {
        guard item.type == .series,
              Container.shared.currentUserSession()?.user.data.policy?.enableContentDownloading == true
        else { return false }

        return !EnhancedFinSyntheticItem.isSynthetic(item.id) || mediaPlayerItemProvider != nil
    }
}

/// SweetFin : télécharger un item pour le lire hors connexion, depuis n'importe quel
/// menu (« ⋯ » de la fiche, appui long sur un épisode ou une affiche).
///
/// Un seul emplacement, cinq états — absent (télécharger), en préparation et en cours
/// (sous-menu pour annuler), terminé (sous-menu pour supprimer), échec (sous-menu pour
/// réessayer ou supprimer). Un menu n'affiche que du texte et des symboles système :
/// pas d'anneau de progression ici. L'item peut n'avoir que son identifiant :
/// `DownloadManager.start` recharge la fiche complète.
struct DownloadButton: View {

    let item: BaseItemDto
    /// Id sous lequel le téléchargement est rangé, si celui de l'item est éphémère.
    var storageID: String?
    /// Item à demander au serveur au moment du tap (épisode hors médiathèque, désigné au
    /// tap) ; sinon `item`.
    var resolve: (() async throws -> BaseItemDto)?

    @EnvironmentObject
    private var toastProxy: ToastProxy

    @ObservedObject
    private var manager = Container.shared.downloadManager()

    @Injected(\.currentUserSession)
    private var userSession

    var body: some View {
        if let itemID = storageID ?? item.id, let userSession {
            switch manager.state(of: itemID, userID: userSession.user.id) {
            case .none:
                Button(DownloadStrings.download, systemImage: ItemActionButton.download.secondarySystemImage) {
                    start(userSession: userSession)
                }
            case .preparing:
                Menu {
                    removeButton(DownloadStrings.cancelDownload, itemID: itemID, userID: userSession.user.id)
                } label: {
                    Label(DownloadStrings.preparing, systemImage: "arrow.down.app.dashed")
                }
            case let .downloading(progress):
                Menu {
                    removeButton(DownloadStrings.cancelDownload, itemID: itemID, userID: userSession.user.id)
                } label: {
                    Label(DownloadStrings.downloading(progress), systemImage: "arrow.down.app.dashed")
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

    /// Lance le téléchargement ; une erreur s'affiche en toast, et il reste en échec dans
    /// l'onglet, à réessayer ou supprimer.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    private func start(userSession: UserSession) {
        Task {
            do {
                try await manager.start(item, userSession: userSession, storageID: storageID, resolve: resolve)
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
