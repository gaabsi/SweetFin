//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import Get
import JellyfinAPI
import Logging

extension Container {

    var downloadManager: Factory<DownloadManager> {
        self { DownloadManager() }
            .singleton
    }
}

/// EnhancedFin : téléchargement des médias pour la lecture hors connexion.
///
/// **Au niveau de l'app, pas de la session** : la session d'arrière-plan a un identifiant
/// fixe, et iOS relance l'app pour elle quand un transfert finit app fermée — y compris
/// avant toute connexion au serveur.
///
/// **Le dossier fait foi**, sans index à côté :
/// `Application Support/Downloads/<compte>/<item>/` contient `item.json` (écrit au
/// lancement), le fichier média (présent une fois terminé), `poster.jpg` et
/// `subtitles/`. Tout le dossier est exclu de la sauvegarde iCloud.
///
/// `states` n'est modifié que sur le fil principal ; les rappels de la session arrivent
/// sur sa propre file et y sont renvoyés.
final class DownloadManager: NSObject, ObservableObject {

    /// Nom sous lequel iOS retrouve la session quand il relance l'app.
    static let sessionIdentifier = "com.gaabsi.enhancedfin.downloads"

    private static let metadataFileName = "item.json"
    private static let posterFileName = "poster.jpg"
    private static let subtitlesFolderName = "subtitles"

    /// État de chaque téléchargement connu, par clé `"<compte>/<item>"`.
    @Published
    private(set) var states: [String: DownloadState] = [:]

    /// Fourni par iOS quand il relance l'app pour la session : à appeler une fois ses
    /// événements traités, pour qu'il puisse rendormir l'app.
    var backgroundCompletionHandler: (() -> Void)?

    private let logger = Logger.swiftfin()
    private let root = URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        prepareRoot()
        restoreStates()
    }

    // MARK: - Lecture de l'état

    /// État du téléchargement d'un item pour un compte.
    ///
    /// Parametres :
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - state (DownloadState) : `.none` si l'item n'a jamais été téléchargé
    func state(of itemID: String, userID: String) -> DownloadState {
        states[Self.key(userID, itemID)] ?? .none
    }

    // MARK: - Actions

    /// Lance le téléchargement du fichier original d'un item.
    ///
    /// Écrit d'abord `item.json` (la fiche servira hors connexion), puis confie le fichier
    /// à la session d'arrière-plan, qui continue app fermée. Affiche et sous-titres
    /// externes suivent en parallèle, sans bloquer.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : film ou épisode à télécharger
    /// - userSession (UserSession) : compte connecté, dont on reprend le jeton
    @MainActor
    func start(_ item: BaseItemDto, userSession: UserSession) async throws {
        let fullItem = try await item.getFullItem(userSession: userSession)
        guard let itemID = fullItem.id,
              let source = fullItem.mediaSources?.first,
              let url = userSession.client.url(path: "/Items/\(itemID)/Download")
        else { throw DownloadError.missingSource }

        try checkSpace(for: source)

        let userID = userSession.user.id
        let folder = folder(Self.key(userID, itemID))
        let downloaded = DownloadedItem(item: fullItem, mediaSource: source, fileName: Self.fileName(for: source))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(downloaded).write(to: folder.appending(path: Self.metadataFileName))

        var request = URLRequest(url: url)
        request.setValue("MediaBrowser Token=\"\(userSession.user.accessToken)\"", forHTTPHeaderField: "Authorization")
        let task = session.downloadTask(with: request)
        task.taskDescription = Self.key(userID, itemID)
        task.resume()
        states[Self.key(userID, itemID)] = .downloading(progress: 0)

        Task {
            await downloadExtras(of: downloaded, into: folder, client: userSession.client)
        }
    }

    /// Retire un téléchargement, en cours ou terminé : la tâche est annulée et le dossier
    /// supprimé. Annuler et supprimer sont le même geste.
    ///
    /// Parametres :
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    @MainActor
    func remove(itemID: String, userID: String) {
        let key = Self.key(userID, itemID)
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == key }?.cancel()
        }
        try? FileManager.default.removeItem(at: folder(key))
        states[key] = nil
    }

    // MARK: - Stockage

    /// Crée la racine des téléchargements et l'exclut de la sauvegarde iCloud :
    /// plusieurs Go à resauvegarder à chaque film, c'est non.
    private func prepareRoot() {
        var root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    /// Reconstruit `states` au lancement : fichier présent = terminé, dossier sans fichier
    /// = échec, sauf si la session a encore la tâche (téléchargement toujours en cours).
    private func restoreStates() {
        for key in Self.subfolders(of: root).flatMap({ user in Self.subfolders(of: user).map { "\(user.lastPathComponent)/\($0.lastPathComponent)" } }) {
            guard let downloaded = Self.read(folder(key)) else { continue }
            let isComplete = FileManager.default.fileExists(atPath: folder(key).appending(path: downloaded.fileName).path())
            states[key] = isComplete ? .done : .failed
        }

        session.getAllTasks { tasks in
            let running = tasks.compactMap(\.taskDescription)
            DispatchQueue.main.async { [weak self] in
                for key in running {
                    self?.states[key] = .downloading(progress: 0)
                }
            }
        }
    }

    /// Refuse de lancer un fichier qui ne tiendrait pas dans l'espace libre.
    ///
    /// Parametres :
    /// - source (MediaSourceInfo) : source dont on connaît la taille
    private func checkSpace(for source: MediaSourceInfo) throws {
        guard let needed = source.size.map(Int64.init),
              let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
              .volumeAvailableCapacityForImportantUsage,
              needed > available
        else { return }

        throw DownloadError.notEnoughSpace(needed: needed, available: available)
    }

    /// Affiche et sous-titres externes, en mieux-disant : un échec ici ne doit jamais
    /// faire échouer le téléchargement du film. Les sous-titres intégrés au fichier
    /// n'ont pas besoin de ça.
    ///
    /// Parametres :
    /// - downloaded (DownloadedItem) : item dont on récupère les annexes
    /// - folder (URL) : dossier de l'item
    /// - client (JellyfinClient) : client authentifié du compte
    private func downloadExtras(of downloaded: DownloadedItem, into folder: URL, client: JellyfinClient) async {
        let posterRequest = Paths.getItemImage(itemID: downloaded.id, imageType: "Primary", parameters: .init(maxWidth: 600))
        if let poster = try? await client.send(posterRequest).value {
            try? poster.write(to: folder.appending(path: Self.posterFileName))
        }

        let externals = (downloaded.mediaSource.mediaStreams ?? []).filter { $0.type == .subtitle && $0.isExternal == true }
        guard let sourceID = downloaded.mediaSource.id, externals.isNotEmpty else { return }

        let subtitles = folder.appending(path: Self.subtitlesFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: subtitles, withIntermediateDirectories: true)

        for stream in externals {
            guard let index = stream.index, let codec = stream.codec else { continue }
            let request = Request<Data>(path: "/Videos/\(downloaded.id)/\(sourceID)/Subtitles/\(index)/Stream.\(codec)")
            if let data = try? await client.send(request).value {
                try? data.write(to: subtitles.appending(path: "\(index).\(codec)"))
            }
        }
    }

    private func folder(_ key: String) -> URL {
        root.appending(path: key, directoryHint: .isDirectory)
    }

    private func publish(_ state: DownloadState, for key: String) {
        DispatchQueue.main.async { [weak self] in
            self?.states[key] = state
        }
    }

    // MARK: - Utilitaires

    private static func key(_ userID: String, _ itemID: String) -> String {
        "\(userID)/\(itemID)"
    }

    /// Garde l'extension du fichier d'origine : VLC sonde le contenu, mais une extension
    /// juste évite toute hésitation sur le conteneur.
    private static func fileName(for source: MediaSourceInfo) -> String {
        let fileExtension = source.path.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        return fileExtension.isEmpty ? "media" : "media.\(fileExtension)"
    }

    private static func read(_ folder: URL) -> DownloadedItem? {
        guard let data = try? Data(contentsOf: folder.appending(path: metadataFileName)) else { return nil }
        return try? JSONDecoder().decode(DownloadedItem.self, from: data)
    }

    private static func subfolders(of folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}

// MARK: - Rappels de la session d'arrière-plan

extension DownloadManager: URLSessionDownloadDelegate {

    /// Le fichier temporaire est supprimé dès le retour de cette fonction : il faut le
    /// déplacer ici, de façon synchrone.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Sans `item.json`, l'item a été retiré entre-temps : rien à ranger.
        guard let key = downloadTask.taskDescription, let downloaded = Self.read(folder(key)) else { return }

        // Un 401 ou un 403 arrive aussi ici, avec le corps de l'erreur en guise de fichier.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            logger.error("Download failed for \(key): HTTP \(status)")
            publish(.failed, for: key)
            return
        }

        do {
            let destination = folder(key).appending(path: downloaded.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            publish(.done, for: key)
        } catch {
            logger.error("Download could not be stored for \(key): \(error.localizedDescription)")
            publish(.failed, for: key)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async { [weak self] in
            // Au centième près : un fichier de plusieurs Go s'écrit en milliers de blocs, et
            // chaque publication redessine la fiche. Un item retiré entre-temps reste retiré.
            guard let self, case let .downloading(current) = states[key], progress - current >= 0.01 else { return }
            states[key] = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let key = task.taskDescription else { return }

        // Annulé par `remove` : le dossier est déjà supprimé, il n'y a rien à signaler.
        if (error as? URLError)?.code == .cancelled { return }

        logger.error("Download failed for \(key): \(error.localizedDescription)")
        publish(.failed, for: key)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
