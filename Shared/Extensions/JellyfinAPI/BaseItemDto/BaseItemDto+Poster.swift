//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import SwiftUI

extension BaseItemDto: Poster {

    struct Environment: WithDefaultValue, WithImageSourceOptions, WithViewContext {

        var maxWidth: CGFloat?
        var maxHeight: CGFloat?
        var quality: Int?
        var useParent: Bool = false
        var viewContext: ViewContext = .init()

        static var `default`: Self {
            .init()
        }
    }

    func resolveEnvironment(_ environment: EnvironmentValues) -> Environment {
        let viewContext = environment.viewContext

        return .init(
            useParent: viewContext.contains(.isThumb),
            viewContext: viewContext
        )
    }

    var preferredPosterDisplayType: PosterDisplayType {
        type?.preferredPosterDisplayType ?? .portrait
    }

    var subtitle: String? {
        switch type {
        case .episode:
            seasonEpisodeLabel
        case .person:
            people?.first?.displayRole
        case .video:
            extraType?.displayTitle
        default:
            nil
        }
    }

    var systemImage: String {
        switch type {
        case .audio, .musicAlbum:
            "music.note"
        case .boxSet:
            "film.stack"
        case .channel, .tvChannel, .liveTvChannel, .program:
            "tv"
        case .episode, .movie, .season, .series, .video:
            "film"
        case .collectionFolder, .folder, .userView:
            "folder.fill"
        case .musicVideo:
            "music.note.tv.fill"
        case .person:
            "person.fill"
        default:
            "circle"
        }
    }

    @ViewBuilder
    var posterLabel: some View {
        BaseItemDtoPosterLabel(item: self)
    }

    @ViewBuilder
    var posterContextMenu: some View {
        BaseItemDtoPosterContextMenu(item: self)
    }

    @ViewBuilder
    func posterOverlay(for displayType: PosterDisplayType) -> some View {
        ZStack {
            PosterSelectionOverlay()

            PosterIndicatorsOverlay(
                item: self,
                posterDisplayType: displayType
            )
        }
    }

    @ImageSourceBuilder
    func portraitImageSources(
        environment: Environment
    ) -> [ImageSource] {
        switch type {
        case .episode:
            imageSource(
                itemID: seriesID,
                .primary,
                tag: seriesPrimaryImageTag,
                environment: environment
            )
        case .boxSet, .channel, .liveTvChannel, .liveTvProgram, .movie, .musicArtist, .person, .program, .series, .tvChannel:
            imageSource(
                .primary,
                environment: environment
            )
        case .season:
            imageSource(
                .primary,
                environment: environment
            )

            imageSource(
                itemID: seriesID,
                .primary,
                tag: seriesPrimaryImageTag,
                environment: environment
            )
        default:
            []
        }
    }

    @ImageSourceBuilder
    func landscapeImageSources(
        environment: Environment
    ) -> [ImageSource] {
        switch type {
        case .episode:
            if environment.useParent {
                if environment.viewContext.contains(.isThumb) {
                    imageSource(
                        itemID: seriesID,
                        .thumb,
                        tag: seriesThumbImageTag,
                        environment: environment
                    )
                }

                imageSource(
                    .primary,
                    environment: environment
                )
            } else {
                imageSource(
                    .primary,
                    environment: environment
                )
            }
        case .collectionFolder, .folder, .musicVideo, .userView, .video:
            if environment.viewContext.contains(.isThumb) {
                imageSource(
                    .thumb,
                    environment: environment
                )
            }

            imageSource(
                .primary,
                environment: environment
            )
        case .season:
            if environment.viewContext.contains(.isThumb) {
                imageSource(
                    itemID: seriesID,
                    .thumb,
                    tag: seriesThumbImageTag,
                    environment: environment
                )
            }

            imageSource(
                itemID: seriesID,
                .backdrop,
                tag: parentBackdropImageTags?.first,
                environment: environment
            )
        default:
            if environment.viewContext.contains(.isThumb) {
                imageSource(
                    .thumb,
                    environment: environment
                )
            }

            imageSource(
                .backdrop,
                tag: backdropImageTags?.first,
                environment: environment
            )
        }
    }

    @ImageSourceBuilder
    func squareImageSources(
        environment: Environment
    ) -> [ImageSource] {
        switch type {
        case .audio:
            imageSource(
                .primary,
                environment: environment
            )

            imageSource(
                itemID: albumID,
                .primary,
                tag: albumPrimaryImageTag,
                environment: environment
            )
        case .channel, .musicAlbum, .tvChannel:
            imageSource(
                .primary,
                environment: environment
            )
        case .program:
            if let channelID {
                imageSource(
                    itemID: channelID,
                    .primary,
                    tag: channelPrimaryImageTag,
                    environment: environment
                )
            }
        default:
            []
        }
    }

    @ViewBuilder
    func transform(image: Image, displayType: PosterDisplayType) -> some View {
        switch type {
        case .channel, .tvChannel:
            ContainerRelativeView(ratio: 0.95) {
                image
                    .aspectRatio(contentMode: .fit)
            }
        case .program:
            if displayType == .square {
                ContainerRelativeView(ratio: 0.95) {
                    image
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                image
                    .aspectRatio(contentMode: .fill)
            }
        default:
            image
                .aspectRatio(contentMode: .fill)
        }
    }
}

/// SweetFin : le menu d'appui long d'une affiche, **le même partout** — médiathèques,
/// rails, recherche. C'est une propriété de l'élément, pas de la zone.
///
/// - Aller à l'élément, et à la série pour un épisode ;
/// - Marquer comme vu / non vu ;
/// - Watchlist (pour un épisode : sa série).
///
/// Dans « Continuer de regarder », le menu suit la liste, qui est une liste de
/// **médias en cours** : un épisode y représente sa série, donc « Aller à l'élément »
/// ouvre la série (sans second bouton) ; pas de Watchlist, puisqu'on regarde déjà ;
/// et « Masquer », qui veut dire « retirer de cette liste ».
///
/// Plus de favoris : le fork ne s'en sert pas.
private struct BaseItemDtoPosterContextMenu: View {

    @ViewContextContains(.isInContinueWatching)
    private var isInContinueWatching

    @Router
    private var router

    @State
    private var item: BaseItemDto

    init(item: BaseItemDto) {
        self.item = item
    }

    private var isPlayed: Bool {
        item.userData?.isPlayed == true
    }

    /// Dans « Continuer de regarder », un épisode s'efface derrière sa série.
    private var representsSeries: Bool {
        isInContinueWatching && item.type == .episode && item.seriesID != nil
    }

    /// Une reprise externe (`enhancedfin:…`), inconnue de Jellyfin.
    private var isSynthetic: Bool {
        EnhancedFinSyntheticItem.isSynthetic(item.id)
    }

    /// Les types qui ont un équivalent TMDB : film, série, et épisode (via sa série).
    private var hasMediaKey: Bool {
        isSynthetic || [.movie, .series, .episode].contains(item.type)
    }

    /// Les actions du plugin (watchlist, masquer) : il faut qu'il soit installé.
    private var hasPluginActions: Bool {
        EnhancedFinClient.isAvailable && hasMediaKey
    }

    var body: some View {
        if let itemID = representsSeries ? item.seriesID : item.id {
            Button(L10n.goToItem, systemImage: "info.circle") {
                // Un item synthétique passe par l'item lui-même, comme au tap : son
                // identifiant enverrait Jellyfin chercher un item qui n'existe pas.
                router.route(to: isSynthetic ? .item(item: item) : .item(id: itemID))
            }
        }

        if item.type == .episode, !representsSeries, let seriesID = item.seriesID {
            Button(L10n.goToSeries, systemImage: "tv") {
                router.route(to: .item(id: seriesID))
            }
        }

        // Pas pour un item synthétique : Jellyfin ne le connaît pas.
        if item.canBePlayed, !isSynthetic {
            Button(isPlayed ? L10n.markAsUnplayed : L10n.markAsPlayed, systemImage: isPlayed ? "circle" : "checkmark.circle") {
                Task {
                    await toggleIsPlayed()
                }
            }
        }

        if hasPluginActions, !isInContinueWatching {
            Button(HomeStrings.watchlist, systemImage: ItemActionButton.enhancedFinWatchlist.secondarySystemImage) {
                Task {
                    await addToWatchlist()
                }
            }
        }

        // SweetFin : télécharger pour le hors-connexion (iPhone) — film ou épisode du
        // serveur ; pas une série représentée par un épisode, ni une reprise externe.
        #if os(iOS)
        if !isSynthetic, !representsSeries, [.movie, .episode].contains(item.type), item.canBeDownloaded {
            DownloadButton(item: item)
        }
        #endif

        if isInContinueWatching, hasPluginActions {
            Button(HomeStrings.hide, systemImage: "eye.slash") {
                Task {
                    await hide()
                }
            }
        }
    }

    /// Ajoute le média à la watchlist du plugin, via l'état partagé des fiches.
    ///
    /// Ajout seul, sans « Retirer » : connaître l'état demanderait d'interroger le
    /// plugin à chaque ouverture du menu.
    private func addToWatchlist() async {
        guard let userSession = Container.shared.currentUserSession(),
              userSession.enhancedFinClient != nil,
              let mediaKey = await resolvedMediaKey(userSession: userSession)
        else { return }

        await EnhancedFinItemStateStore.shared.state(for: mediaKey).addToWatchlist()
    }

    /// Masque le média de « Continuer de regarder », dans le plugin. Il revient de
    /// lui-même dès qu'on le relit (`ContinueWatchingLibrary`).
    private func hide() async {
        guard let userSession = Container.shared.currentUserSession(),
              let client = userSession.enhancedFinClient,
              let mediaKey = await resolvedMediaKey(userSession: userSession)
        else { return }

        // Échec silencieux : la tuile reste, ce qui dit déjà que rien n'a changé.
        guard (try? await client.hide(mediaKey)) != nil else { return }

        Notifications[.didHideContinueWatchingItem].post(mediaKey)
    }

    /// La clé EnhancedFin du **média** : celle de l'item, ou de sa série pour un
    /// épisode.
    ///
    /// Résolue au tap et non à l'affichage : les requêtes de liste (médiathèques…) ne
    /// demandent pas les `ProviderIds`, et les y ajouter toucherait du code upstream
    /// pour un bouton qu'on ne tape presque jamais.
    ///
    /// Parametres :
    /// - userSession (UserSession) : la session en cours
    ///
    /// Output :
    /// - mediaKey (String?) : `nil` si le média n'a pas d'identifiant TMDB
    private func resolvedMediaKey(userSession: UserSession) async -> String? {
        if let key = item.enhancedFinMediaKey { return key }

        guard let mediaID = item.type == .episode ? item.seriesID : item.id else { return nil }

        var parameters = Paths.GetItemsParameters()
        parameters.fields = [.providerIDs]
        parameters.ids = [mediaID]
        parameters.userID = userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let media = try? await userSession.client.send(request).value.items?.first

        return media?.enhancedFinMediaKey
    }

    @MainActor
    private func toggleIsPlayed() async {
        let beforeIsPlayed = item.userData?.isPlayed ?? false

        item.userData?.isPlayed = !beforeIsPlayed
        do {
            try await setIsPlayed(!beforeIsPlayed)
        } catch {
            item.userData?.isPlayed = beforeIsPlayed
        }
    }

    private func setIsPlayed(_ isPlayed: Bool) async throws {
        guard let itemID = item.id,
              let userSession = Container.shared.currentUserSession()
        else { return }

        let request: Request<UserItemDataDto> = if isPlayed {
            Paths.markPlayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        } else {
            Paths.markUnplayedItem(
                itemID: itemID,
                userID: userSession.user.id
            )
        }

        let response = try await userSession.client.send(request)
        item.userData = response.value
        Notifications[.itemUserDataDidChange].post(response.value)
        Notifications[.itemShouldRefreshMetadata].post(itemID)
    }
}

private struct BaseItemDtoPosterLabel: View {

    let item: BaseItemDto

    var body: some View {
        switch item.type {
        case .episode:
            Label {
                if let seriesName = item.seriesName {
                    Text(seriesName)
                }
                if let indexLabel = item.seasonEpisodeLabel {
                    Text(indexLabel)
                }

                Text(item.displayTitle)
            }
        case .season:
            Label {
                Text(item.parentTitle ?? item.displayTitle)
                Text(item.displayTitle)
            }
        case .program:
            Label {
                Text(item.displayTitle)

                if let startDate = item.startDate {
                    ViewThatFits {
                        SeparatorHStack {
                            Text(String.hyphen)
                        } content: {
                            if !Calendar.current.isDateInToday(startDate) {
                                Text(startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                            } else {
                                Text(startDate, style: .time)
                            }

                            if let endDate = item.endDate {
                                Text(endDate, style: .time)
                            }
                        }

                        if !Calendar.current.isDateInToday(startDate) {
                            Text(startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                        } else {
                            Text(startDate, style: .time)
                        }
                    }
                } else {
                    Text(String.emptyRuntime)
                }

                if let channelName = item.channelName {
                    Text(channelName)
                }
            }
        case .video where item.extraType != nil:
            Label {
                Text(item.displayTitle)

                if let extraType = item.extraType, extraType != .unknown {
                    Text(extraType.displayTitle)
                }

                if let runtime = item.runtime {
                    Text(runtime, format: .runtime)
                }
            }
        default:
            Label {
                Text(item.displayTitle)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                }
            }
        }
    }

    private struct Label: View {

        @Environment(\.posterDisplayType)
        private var posterDisplayType

        private let content: [AnyView]

        private var details: [AnyView] {
            let details = content.dropFirst()

            return posterDisplayType == .landscape ? details.asArray : details.prefix(1).asArray
        }

        @Default(.appearance)
        private var appearance

        init(@ArrayBuilder<any View> content: () -> [any View]) {
            self.content = content().map { AnyView($0) }
        }

        var body: some View {
            // SweetFin : alignement décidé par le thème (`ThemeTokens`), et non
            // plus câblé ici. Le fork centrait déjà ses propres libellés
            // (`EnhancedFinPosterLabel`) ; les aligner tous sur la même source a
            // supprimé la valeur d'environnement et le décorateur qui servaient à ne
            // le faire que sur l'Accueil — deux fichiers de moins à maintenir.
            let tokens = appearance.tokens

            AlternateLayoutView(alignment: .top) {
                VStack(spacing: 2) {
                    Text(String.space)
                    Text(String.space)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            } content: {
                VStack(alignment: tokens.posterLabelAlignment, spacing: 2) {
                    content.first
                        .font(.footnote)
                        .multilineTextAlignment(tokens.posterLabelTextAlignment)
                        .lineLimit(details.isEmpty ? 2 : 1, reservesSpace: true)

                    DotHStack {
                        ForEach(details.indices, id: \.self) { index in
                            details[index]
                                .layoutPriority(index == 0 ? 1 : 0)
                        }
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: tokens.posterLabelAlignment, vertical: .center))
            }
        }
    }
}
