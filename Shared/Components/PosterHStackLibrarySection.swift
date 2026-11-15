//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct PosterHStackLibrarySection<Library: PagingLibrary>: View
    where Library.Element: LibraryElement, Library.Element: Poster
{

    private enum FocusSection {
        case header
        case content
    }

    @FocusState
    private var focusedSection: FocusSection?

    @ObservedObject
    var viewModel: PagingLibraryViewModel<Library>

    @Router
    private var router

    let group: PosterGroup<Library>

    private func routeToLibrary() {
        router.route(to: .library(library: viewModel.library))
    }

    private var headerTitle: some View {
        Text(viewModel.library.parent.displayTitle)
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
    }

    @ViewBuilder
    private var header: some View {
        if group.environment.isHeaderButtonEnabled {
            SectionHeaderButton(action: routeToLibrary) {
                headerTitle
            }
            .accessibilityAction(named: Text(L10n.openLibrary), routeToLibrary)
        } else {
            headerTitle
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if group.environment.isHeaderButtonEnabled {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                .focused($focusedSection, equals: .header)
        } else {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        if viewModel.elements.isNotEmpty {
            ContentGroupSection {
                PosterHStack(
                    elements: viewModel.elements.elements,
                    displayType: group.posterDisplayType,
                    size: group.posterSize
                ) { element, namespace in
                    element.libraryDidSelectElement(router: router, in: namespace)
                }
                .withViewContext(.isThumb)
                .focusSection()
                .focused($focusedSection, equals: .content)
            } header: {
                sectionHeader
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
            .focusSection()
            .defaultFocus(
                $focusedSection,
                .content,
                priority: .userInitiated
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(viewModel.library.parent.displayTitle)
        }
    }
}
