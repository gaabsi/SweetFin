//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct EditServerConnectionView: View {

    @FocusState
    private var isNameFocused: Bool

    @ObservedObject
    var viewModel: ServerConnectionViewModel

    @Router
    private var router

    @State
    private var draft: ServerConnectionDraft

    private let initialConnection: ServerConnection
    private let initialDraft: ServerConnectionDraft

    private var existingConnection: ServerConnection? {
        viewModel.connections.first { $0.id == initialConnection.id }
    }

    private var connection: ServerConnection {
        existingConnection ?? initialConnection
    }

    private var isExistingConnection: Bool {
        existingConnection != nil
    }

    private var testState: ServerConnection.TestState {
        viewModel.testStates[initialConnection.id] ?? .idle
    }

    private var isTesting: Bool {
        if case .testing = testState {
            true
        } else {
            false
        }
    }

    private var isCurrentConnection: Bool {
        viewModel.activeConnection?.id == initialConnection.id
    }

    private var hasChanges: Bool {
        draft != initialDraft
    }

    private var isNameEmpty: Bool {
        draft.name.nilIfBlank == nil
    }

    private var isDuplicateConnection: Bool {
        guard let connection = try? draft.connection() else { return false }
        return ServerConnection.isDuplicate(connection, in: viewModel.connections)
    }

    private var isSaveDisabled: Bool {
        isTesting || !hasChanges || isNameEmpty || isDuplicateConnection
    }

    init(
        viewModel: ServerConnectionViewModel,
        connection: ServerConnection
    ) {
        self.viewModel = viewModel
        self.initialConnection = connection
        self.initialDraft = ServerConnectionDraft(connection: connection)

        self._draft = State(initialValue: ServerConnectionDraft(connection: connection))
    }

    private func save() async throws {
        guard !isNameEmpty else {
            throw ErrorMessage(L10n.invalidName)
        }

        let connection = try draft.connection()

        guard !isDuplicateConnection else {
            throw ErrorMessage(L10n.connectionAlreadyExists)
        }

        let state = await viewModel.saveConnection(connection)
        guard case .success = state else { return }

        router.dismiss()
    }

    private func testDraft() {
        guard let draftConnection = try? draft.connection() else { return }

        test(draftConnection)
    }

    private func test(_ connection: ServerConnection) {
        Task {
            _ = await viewModel.testConnection(connection)
        }
    }

    var body: some View {
        Form(systemImage: "network") {
            Section {
                TextField(L10n.name, text: $draft.name)
                    .focused($isNameFocused)
            } header: {
                Text(L10n.name)
            } footer: {
                if isNameEmpty {
                    Label(L10n.required, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }
            }

            Section {
                TextField(L10n.url, text: $draft.urlString)
                    #if !os(tvOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    #endif
            } header: {
                Text(L10n.url)
            } footer: {
                if isDuplicateConnection {
                    Label(L10n.connectionAlreadyExists, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }
            }

            Section(L10n.status) {
                if isCurrentConnection {
                    Label(L10n.active, systemImage: "circle.fill")
                        .foregroundStyle(.green)
                } else if isExistingConnection {
                    Button(L10n.use) {
                        Task {
                            await viewModel.setActiveConnectionIfValid(connection)
                        }
                    }
                    .disabled(isTesting || hasChanges)
                }

                Button(action: testDraft) {
                    LabeledContent {
                        switch testState {
                        case .idle, .failure:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .success:
                            Image(systemName: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } label: {
                        Text(L10n.test)
                    }
                }
                .disabled(isTesting)

                if case let .failure(message) = testState {
                    Text(message.nilIfBlank ?? L10n.connectionFailed)
                        .foregroundStyle(.red)
                }
            }

            if isExistingConnection {
                Button(L10n.delete, role: .destructive) {
                    viewModel.deleteConnection(connection)
                    router.dismiss()
                }
                .disabled(viewModel.connections.count <= 1 || isCurrentConnection)
            }
        }
        .navigationTitle(L10n.connection)
        .navigationBarCloseButton {
            router.dismiss()
        }
        .topBarTrailing {
            let saveAction: () -> Void = {
                Task { try? await save() }
            }

            Group {
                #if os(iOS)
                if #available(iOS 26, *) {
                    Button(L10n.save, role: .confirm, action: saveAction)
                } else {
                    Button(L10n.save, action: saveAction)
                        .backport
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
                #else
                Button(L10n.save, action: saveAction)
                #endif
            }
            .disabled(isSaveDisabled)
        }
        .onFirstAppear {
            isNameFocused = true
        }
    }
}

private struct ServerConnectionDraft: Equatable {
    let id: String
    var name: String
    var urlString: String
    var priority: Int

    init(connection: ServerConnection) {
        self.id = connection.id
        self.name = connection.name
        self.urlString = connection.url.absoluteString
        self.priority = connection.priority
    }

    var url: URL? {
        let resolvedURLString = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prepending("http://", if: !urlString.contains("://"))

        return URL(string: resolvedURLString)?.normalizedServerConnectionURL
    }

    func connection() throws -> ServerConnection {
        guard let url, url.host != nil else {
            throw ErrorMessage(L10n.invalidURL)
        }

        return ServerConnection(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            priority: priority
        )
    }
}
