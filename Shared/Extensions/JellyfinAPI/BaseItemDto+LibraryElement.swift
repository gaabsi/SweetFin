//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: consolidate width constants


extension BaseItemDto: LibraryElement {

    var supportedLibraryStyleOptions: LibraryStyleOptions {
        switch type {
        case .collectionFolder, .folder, .userView:
            return BaseItemKind.libraryStyleOptions(for: supportedItemTypes)
        default:
            break
        }

        return type.map { BaseItemKind.libraryStyleOptions(for: [$0]) } ?? .default
    }

    func libraryDidSelectElement(
        router: Router.Wrapper,
        in namespace: Namespace.ID
    ) {
        switch type {
        case .collectionFolder, .folder, .userView:
            router.route(
                to: .library(library: ItemLibrary(parent: self, filters: .default)),
                in: namespace
            )
        default:
            router.route(to: .item(item: self), in: namespace)
        }
    }

    @ViewBuilder
    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        BaseItemDtoLibraryGridElement(item: self, libraryStyle: libraryStyle)
    }
}

private struct BaseItemDtoLibraryGridElement: View {

    @Namespace
    private var namespace

    @Router
    private var router

    let item: BaseItemDto
    let libraryStyle: LibraryStyle

    private var resolvedLibraryStyle: LibraryStyle {
        item.resolvedLibraryStyle(libraryStyle)
    }

    var body: some View {
        PosterButton(
            item: item,
            displayType: resolvedLibraryStyle.posterDisplayType
        ) { namespace in
            item.libraryDidSelectElement(router: router, in: namespace)
        }
    }
}

