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
/// lancement), le fichier média (présent une fois terminé), `backdrop.jpg` et
/// `logo.png` (de la série pour un épisode), `thumbnail.jpg` (épisode) et `subtitles/`. Tout le dossier est exclu de la sauvegarde iCloud.
///
/// `states` n'est modifié que sur le fil principal ; les rappels de la session arrivent
/// sur sa propre file et y sont renvoyés.
final class DownloadManager: NSObject, ObservableObject {

    /// Nom sous lequel iOS retrouve la session quand il relance l'app.
    static let sessionIdentifier = "com.gaabsi.sweetfin.downloads"

    private static let metadataFileName = "item.json"
    /// SweetFin : miniature d'un épisode.
    private static let thumbnailFileName = "thumbnail.jpg"
    /// SweetFin : fond et logo du film, ou de la série d'un épisode (bannières, hors ligne).
    private static let backdropFileName = "backdrop.jpg"
    private static let logoFileName = "logo.png"
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

    /// Images décodées (fonds, logos, miniatures), pour la même raison.
    private let imageCache = NSCache<NSString, UIImage>()
    /// SweetFin : la préparation en cours de chaque téléchargement. Un lancement annulé
    /// puis relancé pendant sa préparation n'aboutit qu'une fois, celui en cours.
    private var preparations: [String: UUID] = [:]

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

    /// Miniature d'un épisode, si elle a pu être téléchargée.
    ///
    /// Parametres :
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - image (UIImage?) : la miniature, `nil` si elle n'existe pas (encore)
    func thumbnail(of itemID: String, userID: String) -> UIImage? {
        image(Self.thumbnailFileName, of: itemID, userID: userID)
    }

    /// Fond du film ou de la série d'un épisode.
    ///
    /// Parametres :
    /// - itemID (String) : le téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - image (UIImage?) : le fond, `nil` s'il n'existe pas (encore)
    func backdrop(of itemID: String, userID: String) -> UIImage? {
        image(Self.backdropFileName, of: itemID, userID: userID)
    }

    /// Logo du film ou de la série d'un épisode.
    ///
    /// Parametres :
    /// - itemID (String) : le téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - image (UIImage?) : le logo, `nil` s'il n'existe pas (encore)
    func logo(of itemID: String, userID: String) -> UIImage? {
        image(Self.logoFileName, of: itemID, userID: userID)
    }

    /// Fond d'une série : celui du premier de ses épisodes qui en a un (le premier peut
    /// être encore en préparation).
    ///
    /// Parametres :
    /// - episodes ([DownloadedItem]) : épisodes téléchargés de la série
    /// - userID (String) : compte propriétaire des téléchargements
    ///
    /// Output :
    /// - image (UIImage?) : le fond, `nil` si aucun épisode n'en a
    func seriesBackdrop(of episodes: [DownloadedItem], userID: String) -> UIImage? {
        episodes.lazy.compactMap { self.backdrop(of: $0.id, userID: userID) }.first
    }

    /// Logo d'une série : celui du premier de ses épisodes qui en a un.
    ///
    /// Parametres :
    /// - episodes ([DownloadedItem]) : épisodes téléchargés de la série
    /// - userID (String) : compte propriétaire des téléchargements
    ///
    /// Output :
    /// - image (UIImage?) : le logo, `nil` si aucun épisode n'en a
    func seriesLogo(of episodes: [DownloadedItem], userID: String) -> UIImage? {
        episodes.lazy.compactMap { self.logo(of: $0.id, userID: userID) }.first
    }

    /// Une image du dossier d'un téléchargement, gardée en mémoire une fois lue ; une
    /// absence ne l'est pas, les images arrivant après le lancement.
    ///
    /// Parametres :
    /// - fileName (String) : nom du fichier image
    /// - itemID (String) : le téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - image (UIImage?) : l'image, `nil` si elle n'existe pas (encore)
    private func image(_ fileName: String, of itemID: String, userID: String) -> UIImage? {
        let file = folder(Self.key(userID, itemID)).appending(path: fileName)
        let key = file.path(percentEncoded: false) as NSString
        if let image = imageCache.object(forKey: key) { return image }

        guard let image = UIImage(contentsOfFile: key as String) else { return nil }

        imageCache.setObject(image, forKey: key)
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
        // Envoi dès l'arrêt ; sans réseau, la position attend le prochain (lancement, retour
        // du réseau, onglet).
        let sync: () -> Void = { [weak self] in
            Task { @MainActor in
                guard !Container.shared.offlineMonitor().isOffline,
                      let session = Container.shared.currentUserSession()
                else { return }
                await self?.syncWithServer(userSession: session)
            }
        }

        return MediaPlayerItemProvider(item: download.item, mediaSource: download.mediaSource) { _, _ in
            await Self.localPlayerItem(for: download, in: folder, save: save, onStop: sync)
        }
    }

    /// Le lecteur pour un téléchargement : lecture locale, et la file de sa série pour un
    /// épisode.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : téléchargement terminé
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - route (NavigationRoute) : à passer au routeur
    @MainActor
    func videoPlayerRoute(for download: DownloadedItem, userID: String) -> NavigationRoute {
        .videoPlayer(
            provider: playbackProvider(for: download, userID: userID),
            queue: episodeQueue(for: download, userID: userID)
        )
    }

    /// La file d'un épisode téléchargé : les épisodes complets de sa série, dans l'ordre.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : téléchargement lancé
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - queue (DownloadedEpisodeQueue?) : la file, `nil` pour un film
    @MainActor
    func episodeQueue(for download: DownloadedItem, userID: String) -> DownloadedEpisodeQueue? {
        guard let seriesKey = download.seriesKey else { return nil }

        let episodes = downloads(of: userID)
            .filter { $0.seriesKey == seriesKey && state(of: $0.id, userID: userID) == .done }
            .sorted { $0.episodeOrder < $1.episodeOrder }
        return DownloadedEpisodeQueue(episodes: episodes, userID: userID)
    }

    /// Le 2ᵉ builder de `MediaPlayerItem`, à côté de celui en ligne : URL `file://`,
    /// sous-titres externes repointés vers `subtitles/`, reprise à la dernière position
    /// notée, et un observateur qui note la suivante. Le manager et les
    /// proxys du lecteur ne voient pas la différence.
    ///
    /// Parametres :
    /// - download (DownloadedItem) : téléchargement terminé
    /// - folder (URL) : dossier de l'item
    /// - save ((Duration) -> Void) : écrit la position atteinte
    /// - onStop (() -> Void) : envoie la position au serveur à l'arrêt
    ///
    /// Output :
    /// - item (MediaPlayerItem) : item prêt pour VLC
    @MainActor
    private static func localPlayerItem(
        for download: DownloadedItem,
        in folder: URL,
        save: @escaping (Duration) -> Void,
        onStop: @escaping () -> Void
    ) -> MediaPlayerItem {
        // Relu sur le disque : la liste et la file gardent la fiche d'avant le dernier envoi
        // (❌ reprise à l'ancien timecode, vécu le 2026-11-16).
        let download = read(folder) ?? download
        var baseItem = download.item
        // SweetFin : seule la version téléchargée est sur l'appareil. La fiche enregistrée
        // liste toutes celles du serveur (1080p, 720p, 4K…) : sans ça, l'engrenage
        // proposerait d'en changer, donc de la lire en ligne (vécu le 2026-11-15).
        baseItem.mediaSources = [download.mediaSource]
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
        item.observers.append(OfflineProgressObserver(save: save, onStop: onStop))
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

    // MARK: - Progression des téléchargements

    /// Envoie au serveur les positions notées en lisant un téléchargement, **puis** recopie
    /// en local celles qu'il connaît (dans cet ordre, pour ne pas écraser ce qu'on vient
    /// d'envoyer), et rattrape les images manquantes.
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
            await downloadMissingImages(userSession: userSession)
            return didSync
        }
        syncTask = task
        defer { syncTask = nil }

        return await task.value
    }

    /// Note la position atteinte en lisant un téléchargement ; écrase la précédente.
    ///
    /// Parametres :
    /// - seconds (Duration) : position de lecture
    /// - itemID (String) : item Jellyfin
    /// - userID (String) : compte propriétaire du téléchargement
    func saveOfflineProgress(_ seconds: Duration, itemID: String, userID: String) {
        let progress = DownloadProgress(positionTicks: seconds.ticks, date: .now)
        let file = progressFile(of: itemID, userID: userID)
        try? JSONEncoder().encode(progress).write(to: file, options: .atomic)
    }

    /// Envoie les positions notées, puis les oublie : à Jellyfin pour un item
    /// de la médiathèque (au-delà de 90 %, marqué vu), au plugin pour un item hors
    /// médiathèque (il décide lui-même « vu »). Le local gagne toujours. Un envoi qui échoue
    /// garde son fichier pour la prochaine fois.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - didSync (Bool) : vrai si au moins une position a été envoyée
    @MainActor
    private func syncOfflineProgress(userSession: UserSession) async -> Bool {
        let userID = userSession.user.id
        var didSync = false

        for download in downloads(of: userID) {
            let file = progressFile(of: download.id, userID: userID)
            guard let progress = Self.readProgress(file) else { continue }

            let runtime = download.runtimeTicks ?? 0
            let isPlayed = EnhancedFinProgress.isFinished(positionTicks: progress.positionTicks, durationTicks: runtime)

            do {
                if let key = download.mediaKey {
                    // Jellyfin ne connaît pas l'item : sa progression vit dans le plugin. Sans
                    // durée, rien n'est envoyé (elle effacerait celle que le plugin connaît).
                    guard runtime > 0, let plugin = userSession.enhancedFinClient else { continue }
                    try await plugin.setProgress(
                        key,
                        season: download.item.parentIndexNumber ?? 0,
                        episode: download.item.indexNumber ?? 0,
                        positionTicks: progress.positionTicks,
                        durationTicks: runtime
                    )
                } else {
                    let body = UpdateUserItemDataDto(
                        isPlayed: isPlayed,
                        lastPlayedDate: progress.date,
                        playbackPositionTicks: isPlayed ? 0 : progress.positionTicks
                    )
                    _ = try await userSession.client.send(Paths.updateItemUserData(itemID: download.id, userID: userID, body))
                }
                try? FileManager.default.removeItem(at: file)
                // Reprise locale juste, même si le rafraîchissement qui suit échoue.
                storeProgress(progress.positionTicks, isPlayed: isPlayed, of: download, userID: userID)
                didSync = true
            } catch {
                logger.warning("Offline progress not synced for \(download.id): \(error.localizedDescription)")
            }
        }

        return didSync
    }

    /// Recopie une position dans `item.json` : la prochaine lecture locale reprend là (0 si
    /// vu). ❌ Sans : `progress.json` supprimé après l'envoi, la reprise revenait à la
    /// position du jour du téléchargement (vécu le 2026-11-16).
    ///
    /// Parametres :
    /// - positionTicks (Int) : position atteinte
    /// - isPlayed (Bool) : vu (90 % atteints)
    /// - download (DownloadedItem) : le téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - didChange (Bool) : vrai si la fiche a été réécrite
    @discardableResult
    private func storeProgress(_ positionTicks: Int, isPlayed: Bool, of download: DownloadedItem, userID: String) -> Bool {
        var userData = download.item.userData ?? UserItemDataDto(key: download.id)
        userData.playbackPositionTicks = isPlayed ? 0 : positionTicks
        userData.isPlayed = isPlayed
        return storeUserData(userData, of: download.id, userID: userID)
    }

    /// Réécrit position et état vu d'un téléchargement **terminé**, sur la fiche relue
    /// juste avant : ❌ une copie en mémoire, ou une fiche provisoire pendant un lancement,
    /// écrasait la vraie (fichier renommé `media`, pistes perdues). Rien n'est écrit si rien
    /// ne change.
    ///
    /// Parametres :
    /// - userData (UserItemDataDto) : position et état vu à garder
    /// - itemID (String) : le téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    ///
    /// Output :
    /// - didChange (Bool) : vrai si la fiche a été réécrite
    private func storeUserData(_ userData: UserItemDataDto, of itemID: String, userID: String) -> Bool {
        let folder = folder(Self.key(userID, itemID))
        guard state(of: itemID, userID: userID) == .done,
              var stored = Self.read(folder),
              stored.item.userData != userData
        else { return false }

        stored.item.userData = userData
        try? JSONEncoder().encode(stored).write(to: folder.appending(path: Self.metadataFileName), options: .atomic)
        cachedDownloads[userID] = nil
        return true
    }

    /// Recopie dans `item.json` la position que le serveur connaît pour chaque
    /// téléchargement terminé : on reprendra là où on s'était arrêté ailleurs, et non au
    /// jour du téléchargement. Un item qui attend encore l'envoi de sa position locale est
    /// laissé tel quel — elle est plus récente.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    @MainActor
    private func refreshStoredProgress(userSession: UserSession) async {
        let userID = userSession.user.id
        let waiting = downloads(of: userID).filter {
            state(of: $0.id, userID: userID) == .done && Self.readProgress(progressFile(of: $0.id, userID: userID)) == nil
        }

        let pluginChanged = await refreshPluginProgress(waiting.filter(\.isOutsideLibrary), userSession: userSession)
        let libraryChanged = await refreshLibraryProgress(waiting.filter { !$0.isOutsideLibrary }, userSession: userSession)

        // Le cache n'est pas publié : l'onglet relit les fiches (coche « vu »).
        if pluginChanged || libraryChanged {
            objectWillChange.send()
        }
    }

    /// Recopie la position que le plugin connaît pour les téléchargements hors médiathèque :
    /// une requête par œuvre (`GET me/progress/{clé}`). Un épisode jamais commencé n'y est
    /// pas : laissé tel quel.
    ///
    /// Parametres :
    /// - waiting ([DownloadedItem]) : téléchargements hors médiathèque sans envoi en attente
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - didChange (Bool) : vrai si une fiche a été réécrite
    @MainActor
    private func refreshPluginProgress(_ waiting: [DownloadedItem], userSession: UserSession) async -> Bool {
        guard let plugin = userSession.enhancedFinClient else { return false }
        var didChange = false

        for (mediaKey, downloads) in Dictionary(grouping: waiting, by: \.mediaKey) {
            guard let mediaKey, let entries = try? await plugin.progress(mediaKey) else { continue }

            for download in downloads {
                guard let entry = entries.first(where: {
                    $0.season == download.item.parentIndexNumber ?? 0 && $0.episode == download.item.indexNumber ?? 0
                }) else { continue }

                didChange = storeProgress(entry.positionTicks, isPlayed: entry.isWatched, of: download, userID: userSession.user.id) || didChange
            }
        }
        return didChange
    }

    /// Recopie la position que Jellyfin connaît pour les téléchargements de la médiathèque,
    /// en une seule requête.
    ///
    /// Parametres :
    /// - waiting ([DownloadedItem]) : téléchargements de la médiathèque sans envoi en attente
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - didChange (Bool) : vrai si une fiche a été réécrite
    @MainActor
    private func refreshLibraryProgress(_ waiting: [DownloadedItem], userSession: UserSession) async -> Bool {
        let userID = userSession.user.id
        guard waiting.isNotEmpty else { return false }

        // SweetFin : une seule requête pour tous les téléchargements, au lieu d'une par item.
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.ids = waiting.map(\.id)
        parameters.enableUserData = true
        guard let items = try? await userSession.client.send(Paths.getItems(parameters: parameters)).value.items else { return false }
        let userDataByID = Dictionary(items.compactMap { item in item.id.map { ($0, item.userData) } }, uniquingKeysWith: { first, _ in first })

        var didChange = false
        for download in waiting {
            guard let userData = userDataByID[download.id] ?? nil else { continue }
            didChange = storeUserData(userData, of: download.id, userID: userID) || didChange
        }
        return didChange
    }

    // MARK: - Actions

    /// Lance le téléchargement du fichier original d'un item.
    ///
    /// Écrit d'abord une fiche provisoire (« Préparation… », visible aussitôt), puis la
    /// fiche complète (`item.json`, qui servira hors connexion), et confie le fichier à la
    /// session d'arrière-plan, qui continue app fermée. Images et sous-titres externes
    /// suivent en parallèle, sans bloquer.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : film ou épisode à télécharger, tel que connu au tap
    /// - userSession (UserSession) : compte connecté, dont on reprend le jeton d'accès
    /// - storageID (String?) : identifiant sous lequel ranger le téléchargement, si celui de
    ///   l'item n'est pas stable (item hors médiathèque : son id est un identifiant
    ///   temporaire, on range sous l'id de sa fiche, pour la retrouver « téléchargée » à la
    ///   prochaine visite)
    /// - resolve ((() async throws -> BaseItemDto)?) : demande au serveur l'item à
    ///   télécharger, une fois « Préparation… » affiché ; sinon `item`
    @MainActor
    func start(
        _ item: BaseItemDto,
        userSession: UserSession,
        storageID: String? = nil,
        resolve: (() async throws -> BaseItemDto)? = nil
    ) async throws {
        let userID = userSession.user.id
        guard let itemID = storageID ?? item.id else { throw DownloadError.missingSource }
        let key = Self.key(userID, itemID)
        let folder = folder(key)

        // Visible tout de suite (onglet, menu) : le serveur peut mettre plus que le délai
        // d'une requête à rendre la fiche complète. ❌ Avant : rien d'affiché tant qu'elle
        // n'était pas là, et rien du tout si elle expirait (vécu le 2026-11-16).
        let attempt = UUID()
        preparations[key] = attempt
        states[key] = .preparing
        writeProvisional(item, storageID: storageID, into: folder, userID: userID)

        // Ni annulé, ni relancé entre-temps.
        func isCurrent() -> Bool {
            preparations[key] == attempt && states[key] == .preparing
        }

        let fullItem: BaseItemDto
        do {
            let target = try await resolve?() ?? item
            fullItem = try await fetchFullItem(target, userSession: userSession)
        } catch {
            // Annulé : pas d'erreur à montrer.
            guard isCurrent() else { return }
            preparations[key] = nil
            states[key] = .failed
            throw error
        }

        guard isCurrent() else { return }
        preparations[key] = nil

        // La source qui porte l'id de l'item : la version par défaut (hors médiathèque, celle
        // que le serveur envoie au téléchargement), à défaut la première.
        guard let fileID = fullItem.id,
              let source = fullItem.mediaSources?.first(where: { $0.id == fileID }) ?? fullItem.mediaSources?.first,
              let url = userSession.client.url(path: "/Items/\(fileID)/Download")
        else {
            remove(itemID: itemID, userID: userID)
            throw DownloadError.missingSource
        }

        do {
            try checkSpace(needed: source.size.map(Int64.init))
        } catch {
            remove(itemID: itemID, userID: userID)
            throw error
        }

        let downloaded = DownloadedItem(
            item: fullItem,
            mediaSource: source,
            fileName: Self.fileName(for: source),
            mediaKey: EnhancedFinSyntheticItem.mediaKey(from: storageID),
            storageID: Self.pathComponent(itemID)
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(downloaded).write(to: folder.appending(path: Self.metadataFileName), options: .atomic)
        cachedDownloads[userID] = nil

        var request = URLRequest(url: url)
        request.setValue("MediaBrowser Token=\"\(userSession.user.accessToken)\"", forHTTPHeaderField: "Authorization")
        let task = session.downloadTask(with: request)
        task.taskDescription = key
        task.resume()
        states[key] = .downloading(progress: 0)

        Task {
            await downloadExtras(of: downloaded, into: folder, userSession: userSession)
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

    /// Fiche provisoire, tant que la fiche complète n'est pas arrivée : le téléchargement
    /// apparaît aussitôt dans l'onglet (« Préparation… »). Une fiche déjà là (nouvel essai)
    /// est gardée.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item tel que connu au tap
    /// - storageID (String?) : id de rangement d'un item hors médiathèque
    /// - folder (URL) : dossier du téléchargement
    /// - userID (String) : compte propriétaire du téléchargement
    private func writeProvisional(_ item: BaseItemDto, storageID: String?, into folder: URL, userID: String) {
        let file = folder.appending(path: Self.metadataFileName)
        guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }

        let provisional = DownloadedItem(
            item: item,
            mediaSource: item.mediaSources?.first ?? MediaSourceInfo(),
            fileName: "media",
            mediaKey: EnhancedFinSyntheticItem.mediaKey(from: storageID),
            storageID: folder.lastPathComponent
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(provisional).write(to: file, options: .atomic)
        cachedDownloads[userID] = nil
    }

    /// La fiche complète, avec 2 nouveaux essais si le serveur tarde : il peut mettre plus
    /// que le délai d'une requête (20 s) à la rendre, et continue pendant ce temps — le
    /// nouvel essai la trouve en général prête.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item à recharger
    /// - userSession (UserSession) : compte connecté
    ///
    /// Output :
    /// - item (BaseItemDto) : la fiche complète, sources comprises
    private func fetchFullItem(_ item: BaseItemDto, userSession: UserSession) async throws -> BaseItemDto {
        var attempt = 1
        while true {
            do {
                return try await item.getFullItem(userSession: userSession)
            } catch let error as URLError where error.code == .timedOut && attempt < 3 {
                attempt += 1
            }
        }
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

        // Un épisode qui échoue n'arrête pas les suivants ; la 1ʳᵉ erreur est remontée.
        var firstError: Error?
        for episode in pending {
            do {
                try await start(episode, userSession: userSession)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
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
        imageCache.removeAllObjects()
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

    /// Images et sous-titres externes, en mieux-disant : un échec ici ne doit jamais
    /// faire échouer le téléchargement du film. Les sous-titres intégrés au fichier
    /// n'ont pas besoin de ça.
    ///
    /// Parametres :
    /// - downloaded (DownloadedItem) : item dont on récupère les annexes
    /// - folder (URL) : dossier de l'item
    /// - userSession (UserSession) : compte connecté
    private func downloadExtras(of downloaded: DownloadedItem, into folder: URL, userSession: UserSession) async {
        await downloadImages(of: downloaded, into: folder, userSession: userSession)

        let client = userSession.client
        // L'id de l'item pour le serveur (hors médiathèque : l'identifiant temporaire), pas
        // celui du dossier.
        let serverID = downloaded.item.id ?? downloaded.id
        let externals = (downloaded.mediaSource.mediaStreams ?? []).filter { $0.type == .subtitle && $0.isExternal == true }
        guard let sourceID = downloaded.mediaSource.id, externals.isNotEmpty else { return }

        let subtitles = folder.appending(path: Self.subtitlesFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: subtitles, withIntermediateDirectories: true)

        for stream in externals {
            guard let index = stream.index, let codec = stream.codec else { continue }
            let request = Request<Data>(path: "/Videos/\(serverID)/\(sourceID)/Subtitles/\(index)/Stream.\(codec)")
            if let data = try? await client.send(request).value {
                try? data.write(to: subtitles.appending(path: Self.subtitleFileName(index: index, codec: codec)), options: .atomic)
            }
        }
    }

    /// Les images d'un téléchargement : fond et logo du film, ou de la **série** d'un
    /// épisode, et la miniature d'un épisode.
    ///
    /// Médiathèque : images du film / de la série et de l'épisode sur Jellyfin. Hors
    /// médiathèque : URL TMDB du plugin (hôte vérifié), jamais l'item du serveur, dont
    /// l'identifiant temporaire expire.
    ///
    /// Parametres :
    /// - downloaded (DownloadedItem) : le téléchargement
    /// - folder (URL) : dossier de l'item
    /// - userSession (UserSession) : compte connecté
    private func downloadImages(of downloaded: DownloadedItem, into folder: URL, userSession: UserSession) async {
        let item = downloaded.item
        let serverID = item.id ?? downloaded.id
        let isEpisode = item.type == .episode
        let client = userSession.client
        let file = { (name: String) in folder.appending(path: name) }

        guard let mediaKey = downloaded.mediaKey else {
            let bannerID = isEpisode ? item.seriesID ?? serverID : serverID
            await saveImage(of: bannerID, "Backdrop", to: file(Self.backdropFileName), client: client)
            await saveImage(of: bannerID, "Logo", to: file(Self.logoFileName), client: client)
            if isEpisode {
                await saveImage(of: serverID, "Primary", to: file(Self.thumbnailFileName), client: client)
            }
            return
        }

        guard let plugin = userSession.enhancedFinClient,
              let media = try? await plugin.media(mediaKey)
        else { return }

        await saveImage(from: .enhancedFinBackdrop(media.backdropUrl), to: file(Self.backdropFileName))
        await saveImage(from: .enhancedFinImage(media.logoUrl), to: file(Self.logoFileName))

        if isEpisode, let season = item.parentIndexNumber, let detail = try? await plugin.season(mediaKey, number: season) {
            let still = detail.episodes.first { $0.number == item.indexNumber }?.stillUrl
            await saveImage(from: .enhancedFinImage(still), to: file(Self.thumbnailFileName))
        }
    }

    /// Une image d'un item du serveur, écrite dans `file` ; rien en cas d'échec.
    ///
    /// Parametres :
    /// - itemID (String) : item du serveur
    /// - imageType (String) : `Primary`, `Backdrop`, `Logo`
    /// - file (URL) : fichier à écrire
    /// - client (JellyfinClient) : client authentifié du compte
    private func saveImage(of itemID: String, _ imageType: String, to file: URL, client: JellyfinClient) async {
        let request = Paths.getItemImage(itemID: itemID, imageType: imageType, parameters: .init(maxWidth: imageType == "Backdrop" ? 1280 : 600))
        if let data = try? await client.send(request).value {
            writeImage(data, to: file)
        }
    }

    /// Une image TMDB (URL déjà vérifiée), écrite dans `file` ; rien en cas d'échec.
    ///
    /// Parametres :
    /// - url (URL?) : l'image, `nil` si absente ou refusée
    /// - file (URL) : fichier à écrire
    private func saveImage(from url: URL?, to file: URL) async {
        guard let url, let (data, response) = try? await URLSession.shared.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status)
        else { return }

        writeImage(data, to: file)
    }

    /// Écrit une image, seulement si c'en est une : ❌ une page d'erreur enregistrée comme
    /// image ne s'afficherait pas, et ne serait jamais redemandée (le fichier existe).
    ///
    /// Parametres :
    /// - data (Data) : la réponse reçue
    /// - file (URL) : fichier à écrire
    private func writeImage(_ data: Data, to file: URL) {
        guard UIImage(data: data) != nil else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Rattrape les images des téléchargements d'avant les bannières (2026-11-16) : fond,
    /// logo et miniature. Seulement pour ceux qui n'en ont **aucune** : ❌ une image absente
    /// côté serveur était redemandée à chaque synchro, donc à chaque arrêt du lecteur.
    ///
    /// Parametres :
    /// - userSession (UserSession) : compte connecté
    @MainActor
    private func downloadMissingImages(userSession: UserSession) async {
        let userID = userSession.user.id
        let missing = downloads(of: userID).filter { download in
            let folder = folder(Self.key(userID, download.id))
            let hasImage = [Self.backdropFileName, Self.logoFileName, Self.thumbnailFileName].contains {
                FileManager.default.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false))
            }
            return state(of: download.id, userID: userID) == .done && !hasImage
        }
        guard missing.isNotEmpty else { return }

        for download in missing {
            await downloadImages(of: download, into: folder(Self.key(userID, download.id)), userSession: userSession)
        }
        imageCache.removeAllObjects()
        objectWillChange.send()
    }

    private func folder(_ key: String) -> URL {
        root.appending(path: key, directoryHint: .isDirectory)
    }

    /// Position notée pendant une lecture, en attente d'envoi.
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
        guard let data = try? Data(contentsOf: folder.appending(path: metadataFileName)),
              var downloaded = try? JSONDecoder().decode(DownloadedItem.self, from: data)
        else { return nil }
        // SweetFin : le dossier fait foi (un item hors médiathèque est rangé sous l'id de sa
        // fiche, pas sous l'identifiant temporaire enregistré dans `item.json`).
        downloaded.storageID = folder.lastPathComponent
        return downloaded
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
