//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import JellyfinAPI
import SwiftUI

@MainActor
struct ItemLibrary: PagingLibrary, SearchablePagingLibrary {

    struct Environment: WithDefaultValue {
        var grouping: BaseItemDto.Grouping?
        var filters: ItemFilterCollection

        static let `default`: Self = .init(
            grouping: nil,
            filters: .default
        )
    }

    let environment: Environment?
    let filterViewModel: FilterViewModel
    let parent: BaseItemDto

    init(
        parent: BaseItemDto,
        filters: ItemFilterCollection? = nil
    ) {
        let environment = Environment(
            grouping: parent.groupings?.defaultSelection,
            filters: filters ?? .default
        )

        self.environment = environment
        self.filterViewModel = .init(currentFilters: environment.filters)
        self.parent = parent
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        ItemLibraryBody(
            filterViewModel: filterViewModel,
            viewModel: viewModel,
            content: content
        )
        .eraseToAnyView()
    }

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        let itemTypes = environment.filters.itemTypes.isEmpty ?
            parent.supportedItemTypes(for: environment.grouping) :
            environment.filters.itemTypes

        return BaseItemKind.libraryStyleOptions(for: itemTypes)
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = attachPage(
            to: attachFilters(
                to: makeBaseItemParameters(environment: environment),
                using: environment.filters
            ),
            pageState: pageState
        )
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return normalize(response.value.items ?? [])
    }

    func retrieveSearchPage(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = attachPage(
            to: attachFilters(
                to: makeBaseItemParameters(environment: environment),
                using: environment.filters,
                isLetterFilterIncluded: false
            ),
            pageState: pageState
        )
        parameters.searchTerm = query
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return normalize(response.value.items ?? [])
    }

    private func makeBaseItemParameters(environment: Environment) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.includeItemTypes = parent.supportedItemTypes(for: environment.grouping)
        parameters.isRecursive = parent.isRecursiveCollection(for: environment.grouping)
        parameters.sortBy = [.name]
        parameters.sortOrder = [.ascending]

        guard let parentID = parent.id else { return parameters }

        switch parent.libraryType {
        case .folder:
            parameters.parentID = parentID
            parameters.isRecursive = nil
        case .person:
            parameters.personIDs = [parentID]
        case .studio:
            parameters.studioIDs = [parentID]
        default:
            parameters.parentID = parentID
        }

        return parameters
    }

    private func normalize(_ items: [BaseItemDto]) -> [BaseItemDto] {
        items
            .filter { item in
                if let collectionType = item.collectionType {
                    return CollectionType.supportedCases.contains(collectionType)
                }

                return true
            }
            .map { item in
                if parent.libraryType == .folder, item.type == .collectionFolder {
                    return item.mutating(\.type, with: .folder)
                }

                return item
            }
    }

    private func attachFilters(
        to parameters: Paths.GetItemsParameters,
        using filters: ItemFilterCollection,
        isLetterFilterIncluded: Bool = true
    ) -> Paths.GetItemsParameters {
        var parameters = parameters
        parameters.audioLanguages = filters.audioLanguages.map(\.value)
        parameters.filters = filters.traits
        parameters.genres = filters.genres.map(\.value)
        parameters.officialRatings = filters.officialRatings.map(\.value)
        parameters.sortBy = filters.sortBy
        parameters.sortOrder = filters.sortOrder
        parameters.subtitleLanguages = filters.subtitleLanguages.map(\.value)
        parameters.tags = filters.tags.map(\.value)
        parameters.years = filters.years.compactMap { Int($0.value) }

        parameters.isMovie = filters.categories.contains(.movies) ? true : nil
        parameters.isSeries = filters.categories.contains(.series) ? true : nil
        parameters.isNews = filters.categories.contains(.news) ? true : nil
        parameters.isKids = filters.categories.contains(.kids) ? true : nil
        parameters.isSports = filters.categories.contains(.sports) ? true : nil

        if let query = filters.query {
            parameters.searchTerm = query
        }

        if filters.itemTypes.isNotEmpty {
            parameters.includeItemTypes = filters.itemTypes
        }

        guard isLetterFilterIncluded else { return parameters }

        if filters.letter.first?.value == "#" {
            parameters.nameLessThan = "A"
        } else {
            parameters.nameStartsWith = filters.letter
                .map(\.value)
                .filter { $0 != "#" }
                .first
        }

        return parameters
    }

    private func attachPage(
        to parameters: Paths.GetItemsParameters,
        pageState: LibraryPageState
    ) -> Paths.GetItemsParameters {
        var parameters = parameters
        parameters.limit = pageState.pageSize
        parameters.startIndex = pageState.pageOffset
        return parameters
    }
}

private struct ItemLibraryBody<Content: View>: View {

    @Router
    private var router

    @ObservedObject
    private var viewModel: PagingLibraryViewModel<ItemLibrary>

    private let content: Content
    private let filterViewModel: FilterViewModel

    init(
        filterViewModel: FilterViewModel,
        viewModel: PagingLibraryViewModel<ItemLibrary>,
        @ViewBuilder content: () -> Content
    ) {
        self.filterViewModel = filterViewModel
        self.viewModel = viewModel
        self.content = content()
    }

    var body: some View {
        content
            .letterPickerBar(filterViewModel: filterViewModel)
            .onReceive(
                // SweetFin : plus d'attente d'1 s (`debounce`). Elle groupait les clics du
                // tiroir de filtres, supprimé au lot 4 ; seule reste la lettre (un tap), qui
                // attendait 1 s pour rien avant sa requête.
                filterViewModel.$currentFilters
                    .dropFirst()
                    .removeDuplicates()
            ) { filters in
                viewModel.environment.filters = filters
            }
            #if os(tvOS)
            .background(alignment: .top) {
                if !router.isRootOfPath {
                    FocusedPosterCinematicBackgroundView()
                }
            }
            #endif
    }

}
