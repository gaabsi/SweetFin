//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// `internal` et non `private` : le bouton de note EnhancedFin le repose avec la
// couleur de la note en cours, que `ItemActionButton.activeColor` ne peut pas
// connaître puisqu'elle est statique sur le cas de l'enum.
struct ItemActionButtonLabelStyle: LabelStyle {

    @Environment(\.isSelected)
    private var isSelected

    var activeColor: Color?

    private var iconSize: CGFloat {
        UIDevice.isTV ? 40 : 24
    }

    private var tint: Color {
        guard isSelected, let activeColor else {
            return .gray.opacity(0.15)
        }

        return activeColor
    }

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .font(UIDevice.isTV ? .system(size: 30) : .title3)
            .frame(width: iconSize, height: iconSize)
            .padding(UIDevice.isTV ? 16 : 8)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: tint,
                    foregroundColor: .primary
                ),
                in: .capsule
            )
    }
}

struct ItemActionButtons: View {

    static let maximumButtons = 4

    @ObservedObject
    var provider: ItemContentGroupProvider

    let buttons: [ItemActionButton]
    let overflowButtons: [ItemActionButton]
    let menuButtons: [ItemActionButton]
    let focusedButton: FocusState<String?>.Binding

    private static func isAvailable(
        _ button: ItemActionButton,
        for provider: ItemContentGroupProvider
    ) -> Bool {
        switch button {
        case .played:
            // EnhancedFin : un film de découverte se marque vu aussi, dans le plugin
            // (voir `ItemContentGroupProvider.setIsPlayed`).
            provider.item.canBePlayed
                || (EnhancedFinSyntheticItem.isSynthetic(provider.item.id) && provider.item.type == .movie)
        case .playback:
            provider.item.presentPlayButton && provider.mediaPlayerItemProvider?.mediaSource != nil
        case .refresh:
            provider.item.canEditMetadata
        case .subtitles:
            provider.item.canEditSubtitles
        case .delete:
            provider.item.canDelete == true
        #if os(iOS)
        case .editMetadata:
            provider.item.canEditMetadata
        #endif
        case .enhancedFinRating, .enhancedFinWatchlist:
            provider.item.enhancedFinMediaKey != nil
        case .enhancedFinFollow:
            // Films compris : le plugin enregistre la date de sortie d'un film au
            // calendrier, comme une série y enregistre ses épisodes.
            provider.item.enhancedFinMediaKey != nil
        #if os(iOS)
        case .download:
            // V1 : un fichier = un film ou un épisode. Un item synthétique n'a pas de
            // `canDownload`, donc pas de bouton.
            provider.item.canBeDownloaded && [.movie, .episode].contains(provider.item.type)
        #endif
        }
    }

    private static func availableButtons(
        _ buttons: [ItemActionButton],
        for provider: ItemContentGroupProvider
    ) -> [ItemActionButton] {
        buttons.filter { isAvailable($0, for: provider) }
    }

    static func resolvedButtons(
        bar: [ItemActionButton],
        menu: [ItemActionButton],
        for provider: ItemContentGroupProvider
    ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
        let bar = availableButtons(bar, for: provider)
        let menu = availableButtons(menu, for: provider)

        let hasBarMenu = UIDevice.isTV && (menu.isNotEmpty || bar.count > maximumButtons)
        let visible = Array(bar.prefix(hasBarMenu ? maximumButtons - 1 : maximumButtons))
        let overflow = Array(bar.dropFirst(visible.count))

        return (
            visible: visible,
            overflow: overflow,
            menu: menu.subtracting(overflow)
        )
    }

    @ViewBuilder
    static func view(for button: ItemActionButton) -> some View {
        Group {
            switch button {
            case .played:
                Played()
            case .playback:
                Playback()
            case .refresh:
                Refresh()
            case .subtitles:
                Subtitles()
            case .delete:
                Delete()
            #if os(iOS)
            case .editMetadata:
                Edit()
            #endif
            case .enhancedFinRating, .enhancedFinWatchlist, .enhancedFinFollow:
                EnhancedFinButton(button: button)
            #if os(iOS)
            case .download:
                Download()
            #endif
            }
        }
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.primary, .secondary)
    }

    var body: some View {
        let hasBarMenu = UIDevice.isTV && (overflowButtons.isNotEmpty || menuButtons.isNotEmpty)

        if buttons.isNotEmpty || hasBarMenu {
            HStack(alignment: .center, spacing: UIDevice.isTV ? 24 : 8) {
                ForEach(buttons) { button in
                    Self.view(for: button)
                        .labelStyle(ItemActionButtonLabelStyle(activeColor: button.activeColor))
                        .focused(focusedButton, equals: button.id)
                }

                if hasBarMenu {
                    Menu {
                        MenuContent(
                            provider: provider,
                            buttons: overflowButtons,
                            menuButtons: menuButtons
                        )
                    } label: {
                        Label(L10n.menu, systemImage: "ellipsis")
                    }
                    .menuStyle(.button)
                    .labelStyle(ItemActionButtonLabelStyle())
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary, .secondary)
                    .focused(focusedButton, equals: ItemView.Component.menu)
                }
            }
            .frame(height: UIDevice.isTV ? 75 : 44)
            .environmentObject(provider)
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .font(.title3)
            .fontWeight(.semibold)
        }
    }
}

extension ItemActionButtons {

    struct Configuration: DynamicProperty {

        func resolvedButtons(
            for provider: ItemContentGroupProvider
        ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
            // EnhancedFin : listes imposées, pas de réglage par compte.
            ItemActionButtons.resolvedButtons(
                bar: ItemActionButton.barButtons,
                menu: ItemActionButton.menuButtons,
                for: provider
            )
        }
    }

    struct MenuContent: View {

        @Router
        private var router

        @ObservedObject
        var provider: ItemContentGroupProvider

        let buttons: [ItemActionButton]
        let menuButtons: [ItemActionButton]

        var body: some View {
            Group {
                ForEach(
                    buttons,
                    content: ItemActionButtons.view(for:)
                )

                if buttons.isNotEmpty, menuButtons.isNotEmpty {
                    Divider()
                }

                ForEach(
                    menuButtons,
                    content: ItemActionButtons.view(for:)
                )

                // EnhancedFin : demander le média sur Seerr, quand la fiche est
                // incomplète ou de découverte. Hors de la liste configurable des
                // boutons : ce n'est pas une préférence, c'est une situation.
                if let media = provider.enhancedFinMedia, media.canRequestOnSeerr {
                    Divider()

                    Button(SeerrStrings.requestOnSeerr, systemImage: "arrow.down.circle") {
                        router.route(to: .seerrRequest(media: media))
                    }
                }
            }
            .environmentObject(provider)
            .withViewContext(.isInMenu)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
        }
    }
}
