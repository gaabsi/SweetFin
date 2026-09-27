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
import OrderedCollections
import SwiftUI

struct SelectUserView: View {

    typealias UserItem = (user: UserState, server: ServerState)

    @Default(.accentColor)
    private var accentColor
    @Default(.selectUserServerSelection)
    private var serverSelection

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    @Router
    private var router

    @State
    private var selectedUsers: Set<UserState> = []
    @State
    private var isEditing = false
    @State
    private var isPresentingConfirmDeleteUsers = false

    @StateObject
    private var viewModel = SelectUserViewModel()

    private var selectedServer: ServerState? {
        serverSelection.server(from: viewModel.servers.keys)
    }

    private var areAllUsersSelected: Bool {
        selectedUsers.count == userItems.count
    }

    private func toggleAllUsersSelected() {
        if areAllUsersSelected {
            selectedUsers.removeAll()
        } else {
            selectedUsers.insert(contentsOf: userItems.map(\.user))
        }
    }

    private var splashScreenImageSources: [ImageSource] {
        // EnhancedFin : fond illustré imposé, celui de tous les serveurs ou du serveur filtré.
        switch serverSelection {
        case .all:
            viewModel
                .servers
                .keys
                .shuffled()
                .map(\.splashScreenImageSource)

        case let .server(id):
            viewModel
                .servers
                .keys
                .first(where: { $0.id == id })
                .map { [$0.splashScreenImageSource] } ?? []
        }
    }

    private var userItems: [UserItem] {
        let items: [UserItem] = {
            switch serverSelection {
            case .all:
                return viewModel.servers
                    .map { server, users in
                        users.map { UserItem(user: $0, server: server) }
                    }
                    .flattened()
            case let .server(id: id):
                guard let server = viewModel.servers.keys.first(where: { $0.id == id }) else {
                    return []
                }
                return viewModel.servers[server]!
                    .map { UserItem(user: $0, server: server) }
            }
        }()

        return items.sorted(using: \.user.username)
    }

    private func addUser(server: ServerState) {
        UIDevice.impact(.light)
        router.route(to: .userSignIn(server: server))
    }

    private func delete(user: UserState) {
        selectedUsers.insert(user)
        isPresentingConfirmDeleteUsers = true
    }

    private func select(user: UserState) {
        viewModel.signIn(user)
    }

    @ViewBuilder
    private var splashScreenBackground: some View {
        if splashScreenImageSources.isNotEmpty {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(splashScreenImageSources)
                    .pipeline(.Swiftfin.local)
                    .aspectRatio(contentMode: .fill)
                    .id(splashScreenImageSources)
            }
            .overlay {
                Color.black
                    .opacity(0.9)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            ZStack {
                if userItems.isEmpty {
                    EmptyUserView {
                        if let selectedServer {
                            addUser(server: selectedServer)
                        }
                    }
                    .contextMenu {
                        if selectedServer == nil {
                            Text(L10n.selectServer)

                            ForEach(viewModel.servers.keys) { server in
                                Button {
                                    addUser(server: server)
                                } label: {
                                    Text(server.name)
                                    Text(server.effectiveServerURL.absoluteString)
                                }
                            }
                        }
                    }
                } else {
                    GridView(
                        userItems: userItems,
                        isEditing: $isEditing,
                        selectedUsers: $selectedUsers,
                        serverSelection: serverSelection,
                        action: { select(user: $0) },
                        onDelete: { delete(user: $0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
            .mask {
                VStack(spacing: 0) {
                    Color.white

                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                }
                .ignoresSafeArea(.all, edges: .horizontal)
            }

            Toolbar(
                servers: viewModel.servers.keys,
                allUsers: userItems,
                isEditing: $isEditing,
                selectedUsers: $selectedUsers,
                onDelete: {
                    isPresentingConfirmDeleteUsers = true
                }
            )
            .focusSection()
        }
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .initial, .loading:
                ProgressView()
            case .content:
                if viewModel.servers.isEmpty {
                    ConnectToJellyfinView()
                } else {
                    contentView
                }
            }
        }
        .animation(.linear(duration: 0.1), value: viewModel.state)
        .animation(.linear(duration: 0.1), value: selectedServer)
        .withViewContext(.isOverComplexContent)
        .isEditing(isEditing)
        .onFirstAppear {
            viewModel.getServers()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image(.jellyfinBlobBlue)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: UIDevice.isTV ? 100 : 30)
            }

            #if os(iOS)
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button(
                            areAllUsersSelected ? L10n.removeAll : L10n.selectAll,
                            action: toggleAllUsersSelected
                        )
                        .foregroundStyle(.primary, .secondary)
                        .if(true) { view in
                            if #available(iOS 26.0, *) {
                                view
                            } else {
                                view
                                    .backport
                                    .buttonStyle(.glass)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        Button(L10n.cancel, role: .cancel) {
                            isEditing = false
                        }
                        .foregroundStyle(.primary, .secondary)
                        .if(true) { view in
                            if #available(iOS 26.0, *) {
                                view
                            } else {
                                view
                                    .backport
                                    .buttonStyle(.glass)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        // EnhancedFin : plus de réglages ici, seule reste l'édition des comptes.
                        Button(L10n.editUsers, systemImage: "pencil") {
                            isEditing = true
                        }
                        .disabled(userItems.isEmpty)
                        .backport
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    if isEditing {
                        Button(L10n.delete, role: .destructive) {
                            isPresentingConfirmDeleteUsers = true
                        }
                        .backport
                        .buttonStyle(.glassProminent)
                        .disabled(selectedUsers.isEmpty)
                    }
                }
            }
            #endif
        }
        .background {
            splashScreenBackground
                .ignoresSafeArea()
        }
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
        .onChange(of: isEditing) {
            guard !isEditing, !isPresentingConfirmDeleteUsers else { return }
            selectedUsers.removeAll()
        }
        .onChange(of: viewModel.servers.keys) {
            let newValue = viewModel.servers.keys
            if case let SelectUserServerSelection.server(id: id) = serverSelection,
               !newValue.contains(where: { $0.id == id })
            {
                if newValue.count == 1, let firstServer = newValue.first {
                    let newSelection = SelectUserServerSelection.server(id: firstServer.id)
                    serverSelection = newSelection
                } else {
                    serverSelection = .all
                }
            }
        }
        .onReceive(viewModel.$error) { error in
            guard error != nil else { return }
            UIDevice.feedback(.error)
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .signedIn(user):
                Task { @MainActor in
                    do {
                        try await userSessionManager.signIn(userID: user.id)
                        UIDevice.feedback(.success)
                    } catch {
                        await viewModel.error(error)
                    }
                }
            }
        }
        .onNotification(.didConnectToServer) { server in
            viewModel.background.getServers()
            serverSelection = .server(id: server.id)
        }
        .onNotification(.didChangeServerConnection) { _ in
            viewModel.background.getServers()
        }
        .onNotification(.didDeleteServer) { _ in
            viewModel.background.getServers()
        }
        .alert(
            L10n.delete,
            isPresented: $isPresentingConfirmDeleteUsers
        ) {
            Button(L10n.delete, role: .destructive) {
                viewModel.deleteUsers(selectedUsers)
                selectedUsers.removeAll()
                isEditing = false
                UIDevice.feedback(.success)
            }
        } message: {
            if selectedUsers.count == 1, let first = selectedUsers.first {
                Text(L10n.deleteUserSingleConfirmation(first.username))
            } else {
                Text(L10n.deleteUserMultipleConfirmation(selectedUsers.count))
            }
        }
        .errorMessage($viewModel.error)
    }
}
