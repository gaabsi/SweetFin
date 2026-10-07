//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI

typealias MediaPlayerItemProviderResolver = @Sendable (BaseItemDto, (@Sendable (inout BaseItemDto) -> Void)?) async throws
    -> MediaPlayerItem

struct MediaPlayerItemProvider {

    let item: BaseItemDto
    let mediaSource: MediaSourceInfo?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    private var modifyItem: (@Sendable (inout BaseItemDto) -> Void)?
    private let resolver: MediaPlayerItemProviderResolver

    init(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        resolver: @escaping MediaPlayerItemProviderResolver
    ) {
        self.item = item
        self.mediaSource = mediaSource
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.modifyItem = nil
        self.resolver = resolver
    }

    func modifyingItem(
        _ modifier: @escaping @Sendable (inout BaseItemDto) -> Void
    ) -> Self {
        var copy = self
        let currentModifier = modifyItem

        copy.modifyItem = { item in
            currentModifier?(&item)
            modifier(&item)
        }

        return copy
    }

    func callAsFunction() async throws -> MediaPlayerItem {
        try await resolver(item, modifyItem)
    }
}

extension MediaPlayerItemProvider {

    /// SweetFin : lecture d'un épisode désigné par sa série et son numéro, **résolue à
    /// l'ouverture** : le lecteur s'affiche aussitôt sur `placeholder`. L'item à lancer
    /// est celui déjà connu (`itemID`), sinon celui que le serveur désigne pour cet
    /// épisode seul (`playable`).
    ///
    /// Commun à la feuille des épisodes et au panneau du lecteur (tap, suivant,
    /// précédent) : une seule façon de lancer un épisode hors bibliothèque.
    ///
    /// Parametres :
    /// - placeholder (BaseItemDto) : de quoi afficher le lecteur pendant la résolution
    /// - mediaKey (String?) : clé de la série
    /// - itemID (String?) : item déjà connu (natif, ou réponse d'une saison)
    /// - fromStart (Bool) : vrai pour ignorer la reprise (suivant, précédent)
    ///
    /// Output :
    /// - provider (MediaPlayerItemProvider) : lecture à résoudre
    static func episode(
        _ placeholder: BaseItemDto,
        mediaKey: String?,
        itemID: String? = nil,
        fromStart: Bool = false
    ) -> MediaPlayerItemProvider {
        let season = placeholder.parentIndexNumber
        let episode = placeholder.indexNumber

        return MediaPlayerItemProvider(item: placeholder) { _, modifyItem in
            var resolvedID = itemID
            if resolvedID == nil, let mediaKey, let season, let episode,
               let client = Container.shared.currentUserSession()?.enhancedFinClient
            {
                resolvedID = try? await client.playable(mediaKey, season: season, episode: episode).itemId
            }
            guard let resolvedID else { throw ErrorMessage(PlayerStrings.nothingToPlay) }

            return try await MediaPlayerItem.build(for: BaseItemDto(id: resolvedID)) { item in
                if fromStart { item.userData?.playbackPositionTicks = .zero }
                modifyItem?(&item)
            }
        }
    }
}
