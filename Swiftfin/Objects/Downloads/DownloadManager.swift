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
import UIKit

extension Container {

    var downloadManager: Factory<DownloadManager> {
        self { DownloadManager() }
            .singleton
    }
}

/// SweetFin : téléchargement des médias pour la lecture hors connexion.
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
    static let sessionIdentifier = "com.gaabsi.sweetfin.downloads"

    private static let metadataFileName = "item.json"
    private static let posterFileName = "poster.jpg"
    private static let subtitlesFolderName = "subtitles"
    private static let progressFileName = "progress.json"

    /// État de chaque téléchargement connu, par clé `"<compte>/<item>"`.
    @Published
    private(set) var states: [String: DownloadState] = [:]

    /// Fourni par iOS quand il relance l'app pour la session : à appeler une fois ses
    /// événements traités, pour qu'il puisse rendormir l'app.
    var backgroundCompletionHandler: (() -> Void)?

    /// Synchro en cours avec le serveur, partagée par tous ceux qui la demandent.
    private var syncTask: Task<Bool, Never>?

    /// Listes lues sur le disque, par compte. L'onglet se redessine à chaque pour-cent
    /// d'un téléchargement : relire tous les `item.json` à chaque fois serait du gâchis.
    /// Vidée quand la liste change vraiment (lancement, suppression, position recopiée) ;
    /// une progression ne la touche pas. Lue et écrite sur le fil principal.
    private var cachedDownloads: [String: [DownloadedItem]] = [:]

    /// Affiches décodées, pour la même raison.
    private let posters = NSCache<NSString, UIImage>()

    private let logger = Logger.swiftfin()
    private let root = URL.downloadsDirectory

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

    /// Téléchargements d'un compte — en cours, terminés ou en échec —, le plus récent
    /// d'abord. Lu sur le disque : aucun réseau, donc disponible hors connexion.
    ///
    /// Parametres :
    /// - userID (String) : compte dont on liste les téléchargements
    ///
    /// Output :
    /// - downloads ([DownloadedItem]) : un élément par dossier d'item lisible
    func downloads(of userID: String) -> [DownloadedItem] {
        if let cached = cachedDownloads[userID] { return cached }

        let folders = Self.subfolders(of: root.appending(path: Self.pathComponent(userID), directoryHint: .isDirectory))
        let creation: (URL) -> Date = { folder in
            (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }

        let downloads = folders
            .sorted { creation($0) > creation($1) }
            .compactMap(Self.read)
        cachedDownloads[userID] = downloads
        return downloads
    }

    /// Affiche enregistrée avec l'item, si elle a pu être téléchargée. Gardée en mémoire
    /// une fois lue ; une absence ne l'est pas, l'affiche arrivant après le lancement.
    ///
    /// Parametres :
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - image (UIImage?) : l'affiche, `nil` si elle n'existe pas (encore)
    func poster(of itemID: String, userID: String) -> UIImage? {
        let key = Self.key(userID, itemID) as NSString
        if let image = posters.object(forKey: key) { return image }

        let file = folder(key as String).appending(path: Self.posterFileName)
        guard let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) else { return nil }

        posters.setObject(image, forKey: key)
        return image
    }

    // MARK: - Lecture locale

    /// Ce qu'il faut au lecteur pour lire un téléchargement terminé, sans réseau.
    ///
    /// Chaque demande du lecteur reconstruit l'item à partir des fichiers : rien n'est
    /// partagé d'une lecture à l'autre.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : téléchargement terminé
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - provider (MediaPlayerItemProvider) : à passer à la route `.videoPlayer`
    func playbackProvider(for download: DownloadedItem, userID: String) -> MediaPlayerItemProvider {
        let folder = folder(Self.key(userID, download.id))
        let save: (Duration) -> Void = { [weak self] seconds in
            self?.saveOfflineProgress(seconds, itemID: download.id, userID: userID)
        }

        return MediaPlayerItemProvider(item: download.item, mediaSource: download.mediaSource) { _, _ in
            await Self.localPlayerItem(for: download, in: folder, save: save)
        }
    }

    /// Le 2ᵉ builder de `MediaPlayerItem`, à côté de celui en ligne : URL `file://`,
    /// sous-titres externes repointés vers `subtitles/`, reprise à la dernière position
    /// notée hors connexion, et un observateur qui note la suivante. Le manager et les
    /// proxys du lecteur ne voient pas la différence.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : téléchargement terminé
    /// - folder (URL) : dossier de l'item
    /// - save ((Duration) -> Void) : écrit la position atteinte sans réseau
    ///
    /// Output :
    /// - item (MediaPlayerItem) : item prêt pour VLC
    @MainActor
    private static func localPlayerItem(
        for download: DownloadedItem,
        in folder: URL,
        save: @escaping (Duration) -> Void
    ) -> MediaPlayerItem {
        var baseItem = download.item
        if let progress = readProgress(folder.appending(path: progressFileName)) {
            var userData = baseItem.userData ?? UserItemDataDto(key: download.id)
            userData.playbackPositionTicks = progress.positionTicks
            baseItem.userData = userData
        }

        var mediaSource = download.mediaSource
        mediaSource.mediaStreams = mediaSource.mediaStreams?.map { localizingSubtitle($0, in: folder) }

        let item = MediaPlayerItem(
            baseItem: baseItem,
            mediaSource: mediaSource,
            playSessionID: UUID().uuidString,
            url: folder.appending(path: download.fileName),
            deviceProfile: DeviceProfile.build()
        )
        item.observers.append(OfflineProgressObserver(save: save))
        return item
    }

    /// Un sous-titre externe téléchargé devient un « sidecar » qui pointe sur son fichier
    /// local ; les autres pistes (intégrées au fichier) restent telles quelles.
    ///
    /// Parametres :
    /// - stream (MediaStream) : piste de la source
    /// - folder (URL) : dossier de l'item
    ///
    /// Output :
    /// - stream (MediaStream) : la piste, repointée si son fichier existe
    private static func localizingSubtitle(_ stream: MediaStream, in folder: URL) -> MediaStream {
        guard stream.type == .subtitle, stream.isExternal == true,
              let index = stream.index, let codec = stream.codec
        else { return stream }

        let file = folder.appending(path: subtitlesFolderName).appending(path: subtitleFileName(index: index, codec: codec))
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return stream }

        var stream = stream
        stream.deliveryMethod = .external
        stream.deliveryURL = file.absoluteString
        return stream
    }

    // MARK: - Progression hors connexion

    /// Envoie à Jellyfin les positions notées hors connexion, **puis** recopie en local
    /// celles qu'il connaît : dans cet ordre, pour ne pas écraser ce qu'on vient
    /// d'envoyer.
    ///
    /// **Un seul passage à la fois** : le lancement, le retour du réseau et l'onglet
    /// Téléchargements peuvent la demander ensemble. Un second appel attend le passage
    /// en cours au lieu d'en lancer un autre, qui enverrait deux fois la même position.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - didSync (Bool) : vrai si au moins une position a été envoyée
    @MainActor
    @discardableResult
    func syncWithServer(userSession: UserSession) async -> Bool {
        if let syncTask { return await syncTask.value }

        let task = Task {
            let didSync = await syncOfflineProgress(userSession: userSession)
            await refreshStoredProgress(userSession: userSession)
            return didSync
        }
        syncTask = task
        defer { syncTask = nil }

        return await task.value
    }

    /// Note la position atteinte sans réseau ; écrase la précédente.
    ///
    /// Parametres :
    /// - seconds (Duration) : position de lecture
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    func saveOfflineProgress(_ seconds: Duration, itemID: String, userID: String) {
        let progress = DownloadProgress(positionTicks: seconds.ticks, date: .now)
        let file = progressFile(of: itemID, userID: userID)
        try? JSONEncoder().encode(progress).write(to: file)
    }

    /// Envoie à Jellyfin les positions notées hors connexion, puis les oublie. Le local
    /// gagne toujours. Au-delà de 90 %, l'item est marqué vu. Un envoi qui échoue garde son
    /// fichier pour la prochaine fois.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - didSync (Bool) : vrai si au moins une position a été envoyée
    private func syncOfflineProgress(userSession: UserSession) async -> Bool {
        let userID = userSession.user.id
        var didSync = false

        for download in downloads(of: userID) {
            let file = progressFile(of: download.id, userID: userID)
            guard let progress = Self.readProgress(file) else { continue }

            let runtime = download.item.runTimeTicks ?? 0
            let isPlayed = runtime > 0 && Double(progress.positionTicks) >= Double(runtime) * 0.9
            let body = UpdateUserItemDataDto(
                isPlayed: isPlayed,
                lastPlayedDate: progress.date,
                playbackPositionTicks: isPlayed ? 0 : progress.positionTicks
            )

            do {
                _ = try await userSession.client.send(Paths.updateItemUserData(itemID: download.id, userID: userID, body))
                try? FileManager.default.removeItem(at: file)
                didSync = true
            } catch {
                logger.warning("Offline progress not synced for \(download.id): \(error.localizedDescription)")
            }
        }

        return didSync
    }

    /// Recopie dans `item.json` la position que Jellyfin connaît pour chaque
    /// téléchargement : hors connexion, on reprendra là où on s'était arrêté en ligne, et
    /// non au jour du téléchargement. Un item qui attend encore l'envoi de sa position
    /// locale est laissé tel quel — elle est plus récente.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    private func refreshStoredProgress(userSession: UserSession) async {
        let userID = userSession.user.id

        for download in downloads(of: userID) {
            let folder = folder(Self.key(userID, download.id))
            guard Self.readProgress(progressFile(of: download.id, userID: userID)) == nil,
                  let userData = try? await userSession.client
                  .send(Paths.getItemUserData(itemID: download.id, userID: userID)).value
            else { continue }

            var item = download.item
            item.userData = userData
            let refreshed = DownloadedItem(item: item, mediaSource: download.mediaSource, fileName: download.fileName)
            try? JSONEncoder().encode(refreshed).write(to: folder.appending(path: Self.metadataFileName))
        }

        cachedDownloads[userID] = nil
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

        try checkSpace(needed: source.size.map(Int64.init))

        let userID = userSession.user.id
        let folder = folder(Self.key(userID, itemID))
        let downloaded = DownloadedItem(item: fullItem, mediaSource: source, fileName: Self.fileName(for: source))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(downloaded).write(to: folder.appending(path: Self.metadataFileName))
        cachedDownloads[userID] = nil

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

    /// Les épisodes qu'il reste à voir dans la saison en cours : de l'épisode « à
    /// suivre » (Next Up, S1E1 si rien n'est commencé) jusqu'à la fin de sa saison.
    /// Vide si la série est finie.
    ///
    /// Parametres :
    /// - series (BaseItemDto) : série du serveur
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - episodes ([BaseItemDto]) : épisodes dans l'ordre, avec leurs sources (tailles)
    func remainingEpisodes(of series: BaseItemDto, userSession: UserSession) async throws -> [BaseItemDto] {
        guard let seriesID = series.id else { return [] }

        var nextUpParameters = Paths.GetNextUpParameters()
        nextUpParameters.userID = userSession.user.id
        nextUpParameters.seriesID = seriesID
        let nextUp = try await userSession.client.send(Paths.getNextUp(parameters: nextUpParameters)).value.items?.first

        guard let nextUpID = nextUp?.id, let seasonID = nextUp?.seasonID else { return [] }

        var parameters = Paths.GetEpisodesParameters()
        parameters.userID = userSession.user.id
        parameters.seasonID = seasonID
        parameters.isMissing = false
        parameters.fields = [.mediaSources, .canDownload]
        let episodes = try await userSession.client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).value.items ?? []

        return Array(episodes.drop { $0.id != nextUpID })
    }

    /// Lance plusieurs épisodes d'un coup, en sautant ceux déjà téléchargés ou en
    /// cours. L'espace est vérifié pour le **total** avant de lancer quoi que ce soit.
    ///
    /// Parametres :
    /// - episodes ([BaseItemDto]) : épisodes à télécharger, avec leurs sources
    /// - userSession (UserSession) : compte connecté
    @MainActor
    func start(_ episodes: [BaseItemDto], userSession: UserSession) async throws {
        let pending = episodes.filter { state(of: $0.id ?? "", userID: userSession.user.id) == .none }
        try checkSpace(needed: pending.compactMap { $0.mediaSources?.first?.size }.reduce(0) { $0 + Int64($1) })

        for episode in pending {
            try await start(episode, userSession: userSession)
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
        cachedDownloads[userID] = nil
        posters.removeObject(forKey: key as NSString)
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
            let isComplete = FileManager.default.fileExists(atPath: folder(key).appending(path: downloaded.fileName).path(percentEncoded: false))
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

    /// Refuse de lancer ce qui ne tiendrait pas dans l'espace libre.
    ///
    /// Parametres :
    /// - needed (Int64?) : octets à télécharger ; inconnu = pas de refus
    private func checkSpace(needed: Int64?) throws {
        guard let needed,
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
                try? data.write(to: subtitles.appending(path: Self.subtitleFileName(index: index, codec: codec)))
            }
        }
    }

    private func folder(_ key: String) -> URL {
        root.appending(path: key, directoryHint: .isDirectory)
    }

    /// Position notée hors connexion, en attente d'envoi.
    private func progressFile(of itemID: String, userID: String) -> URL {
        folder(Self.key(userID, itemID)).appending(path: Self.progressFileName)
    }

    private func publish(_ state: DownloadState, for key: String) {
        DispatchQueue.main.async { [weak self] in
            self?.states[key] = state
        }
    }

    // MARK: - Utilitaires

    private static func key(_ userID: String, _ itemID: String) -> String {
        "\(pathComponent(userID))/\(pathComponent(itemID))"
    }

    /// Les identifiants et les codecs viennent du serveur et finissent dans un chemin :
    /// on ne garde que lettres ASCII, chiffres et tirets, pour qu'un `..` ou un `/` ne
    /// fasse jamais sortir du dossier des téléchargements. Vide après filtrage = `_`,
    /// sinon la clé désignerait le dossier du compte entier.
    ///
    /// Parametres :
    /// - value (String) : valeur reçue du serveur
    ///
    /// Output :
    /// - component (String) : nom de fichier ou de dossier sans danger
    private static func pathComponent(_ value: String) -> String {
        let safe = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return safe.isEmpty ? "_" : safe
    }

    private static func subtitleFileName(index: Int, codec: String) -> String {
        "\(index).\(pathComponent(codec))"
    }

    /// Garde l'extension du fichier d'origine : VLC sonde le contenu, mais une extension
    /// juste évite toute hésitation sur le conteneur.
    private static func fileName(for source: MediaSourceInfo) -> String {
        let fileExtension = source.path.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        return fileExtension.isEmpty ? "media" : "media.\(pathComponent(fileExtension))"
    }

    private static func readProgress(_ file: URL) -> DownloadProgress? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(DownloadProgress.self, from: data)
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
