//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

// SweetFin : toute l'interface SyncPlay. La logique (requêtes, état du groupe) vit dans
// `SyncPlayManager` ; les vues ne font qu'afficher et appeler ses fonctions.

// MARK: - Bouton de l'Accueil

/// SweetFin : bouton SyncPlay, à gauche de la photo de profil. Coloré dans un groupe.
struct SyncPlayBarButton: View {

    @ObservedObject
    var manager: SyncPlayManager

    @State
    private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // L'icône `Groups` de jellyfin-web : les silhouettes de derrière plus sombres.
            Image(systemName: "person.3.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(manager.group == nil ? Color.primary : Color.accentColor)
                .frame(width: 32, height: 32)
                .modifier(SmallGlassCircle())
                // L'espace d'iOS entre deux éléments de barre (`ToolbarSpacer`) fait 2 pt de
                // plus que la marge du bord de l'écran (mesuré : 18,3 contre 16,3 pt).
                .offset(x: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SyncPlayStrings.title)
        .sheet(isPresented: $isPresented) {
            SyncPlaySheet(manager: manager)
        }
    }
}

/// Petite bulle de verre (« o » à côté du « O » de la photo de profil) : garde l'icône
/// lisible sur les images claires de la media bar. La barre ne dessine plus la sienne.
private struct SmallGlassCircle: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.regularMaterial, in: .circle)
        }
    }
}

// MARK: - Feuille

struct SyncPlaySheet: View {

    @ObservedObject
    var manager: SyncPlayManager

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var groups: [GroupInfoDto] = []

    var body: some View {
        NavigationStack {
            Form {
                if let group = manager.group {
                    inGroup(group)
                } else {
                    outOfGroup
                }
            }
            .navigationTitle(manager.group?.groupName ?? SyncPlayStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(SyncPlayStrings.close) { dismiss() }
                }
            }
            // Relu à chaque sortie de groupe : la liste change avec.
            .task(id: manager.groupID) {
                guard manager.group == nil else { return }
                groups = (try? await manager.groups()) ?? []
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func inGroup(_ group: GroupInfoDto) -> some View {
        Section(SyncPlayStrings.participants) {
            ForEach(group.participants ?? [], id: \.self) { name in
                Label(name, systemImage: "person.fill")
            }
        }

        Section {
            NavigationLink(SyncPlayStrings.invite) {
                SyncPlayInviteList(manager: manager)
            }

            Button(SyncPlayStrings.leave, role: .destructive) {
                manager.leave()
            }
        }
    }

    @ViewBuilder
    private var outOfGroup: some View {
        Section {
            Button(SyncPlayStrings.createGroup, systemImage: "plus") {
                Task { try? await manager.createGroup() }
            }
        }

        Section(SyncPlayStrings.groups) {
            if groups.isEmpty {
                Text(SyncPlayStrings.noGroups)
                    .foregroundStyle(.secondary)
            }

            ForEach(groups, id: \.groupID) { group in
                Button {
                    if let groupID = group.groupID {
                        manager.join(groupID: groupID)
                    }
                } label: {
                    LabeledContent(
                        group.groupName ?? "",
                        value: SyncPlayStrings.members(group.participants?.count ?? 0)
                    )
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Inviter

/// Les utilisateurs du serveur, sauf soi et ceux déjà dans le groupe. ➕ → ✓ une fois invité.
struct SyncPlayInviteList: View {

    private enum InviteState {
        case sent
        case offline
    }

    @ObservedObject
    var manager: SyncPlayManager

    @Injected(\.currentUserSession)
    private var userSession

    @State
    private var users: [UserDto] = []
    @State
    private var states: [String: InviteState] = [:]

    /// Filtrée à chaque rendu : quelqu'un qui rejoint le groupe disparaît de la liste.
    private var invitableUsers: [UserDto] {
        let participants = manager.group?.participants ?? []
        return users.filter { user in
            user.id != userSession?.user.id && !participants.contains(user.name ?? "")
        }
    }

    var body: some View {
        List {
            if invitableUsers.isEmpty {
                Text(SyncPlayStrings.noUsers)
                    .foregroundStyle(.secondary)
            }

            ForEach(invitableUsers, id: \.id) { user in
                row(user)
            }
        }
        .navigationTitle(SyncPlayStrings.invite)
        .task {
            users = (try? await manager.users()) ?? []
        }
    }

    private func row(_ user: UserDto) -> some View {
        HStack(spacing: 12) {
            if let client = userSession?.client {
                UserProfileImage(userID: user.id, source: user.profileImageSource(client: client))
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            }

            Text(user.name ?? "")

            Spacer()

            switch user.id.flatMap({ states[$0] }) {
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .offline:
                Text(SyncPlayStrings.offline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case nil:
                Button {
                    invite(user)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func invite(_ user: UserDto) {
        guard let userID = user.id else { return }

        Task {
            guard let delivered = try? await manager.sendInvite(to: userID) else { return }
            states[userID] = delivered ? .sent : .offline
        }
    }
}

// MARK: - Invitation reçue

/// SweetFin : bandeau « X t'invite à regarder ensemble », Rejoindre en vert, Refuser en rouge.
///
/// À la place d'une alerte système, qui ne sait colorer qu'une action destructrice.
/// Se ferme seul au bout de 15 s, comme le message que le serveur envoie aux autres clients.
struct SyncPlayInviteBanner: ViewModifier {

    /// Comme le message que le serveur affiche sur les autres clients.
    private static let duration: Duration = .seconds(15)

    @ObservedObject
    var manager: SyncPlayManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let invite = manager.pendingInvite {
                    banner(invite)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: invite.id) {
                            try? await Task.sleep(for: Self.duration)
                            guard !Task.isCancelled else { return }
                            manager.declineInvite()
                        }
                }
            }
            .animation(.spring, value: manager.pendingInvite?.id)
    }

    private func banner(_ invite: SyncPlayInvite) -> some View {
        VStack(spacing: 14) {
            Label(SyncPlayStrings.invited(by: invite.from), systemImage: "person.3.fill")
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    manager.declineInvite()
                } label: {
                    Text(SyncPlayStrings.decline)
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)

                Button {
                    manager.join(groupID: invite.groupID)
                } label: {
                    Text(SyncPlayStrings.join)
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}
