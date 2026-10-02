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
            // L'invitation passe par le plugin ; rejoindre et lire ensemble, non.
            if EnhancedFinClient.isAvailable {
                NavigationLink(SyncPlayStrings.invite) {
                    SyncPlayInviteList(manager: manager)
                }
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

/// SweetFin : installe le bandeau d'invitation dans sa propre fenêtre, au-dessus de tout.
///
/// Posé sur `MainTabView`, le bandeau restait **sous** le lecteur (présenté par-dessus) : le
/// minuteur refusait l'invitation sans qu'on l'ait vue. Une fenêtre à part, comme une
/// bannière de notification, reste visible sur tous les écrans, lecteur compris.
struct SyncPlayInviteBanner: ViewModifier {

    let manager: SyncPlayManager

    /// Seule référence à la fenêtre : elle est libérée avec la vue (déconnexion, changement
    /// de compte). ❌ Pas d'`onDisappear` pour la retirer : le lecteur, présenté en plein
    /// écran, fait « disparaître » `MainTabView`, et le bandeau partait avec.
    @State
    private var window: BannerWindow?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: installWindow)
    }

    /// Crée la fenêtre du bandeau, juste au-dessus de celle de l'app. Elle ne devient
    /// jamais la fenêtre principale : clavier et orientation restent ceux de l'app.
    private func installWindow() {
        guard window == nil,
              let appWindow = UIApplication.shared.keyWindow,
              let scene = appWindow.windowScene
        else { return }

        let window = BannerWindow(windowScene: scene)
        let host = BannerHostingController(rootView: SyncPlayInviteBannerView(manager: manager) { [weak window] frame in
            window?.bannerFrame = frame
        })
        host.appWindow = appWindow
        host.view.backgroundColor = .clear

        window.rootViewController = host
        window.windowLevel = appWindow.windowLevel + 1
        window.overrideUserInterfaceStyle = appWindow.overrideUserInterfaceStyle
        window.tintColor = appWindow.tintColor
        window.isHidden = false
        self.window = window
    }
}

/// Contrôleur du bandeau : il recopie l'orientation et la barre d'état de l'écran au
/// premier plan de l'app.
///
/// Plein écran et au-dessus de l'app, la fenêtre du bandeau pilote la barre d'état : avec
/// un `UIHostingController` ordinaire (toutes orientations), la barre d'état passait en
/// paysage quand on tournait le téléphone, l'app restant en portrait.
private final class BannerHostingController<Content: View>: UIHostingController<Content> {

    weak var appWindow: UIWindow?

    /// L'écran au premier plan de l'app : le lecteur s'il est ouvert (paysage permis),
    /// sinon la racine (portrait sur iPhone).
    private var appTopController: UIViewController? {
        var controller = appWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        appTopController?.supportedInterfaceOrientations ?? .portrait
    }

    override var prefersStatusBarHidden: Bool {
        appTopController?.prefersStatusBarHidden ?? false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        appTopController?.preferredStatusBarStyle ?? .default
    }
}

/// Fenêtre qui ne capte que les touchers tombant **sur** le bandeau : le reste passe à
/// l'app en dessous.
///
/// Le cadre vient de SwiftUI : depuis iOS 18, la vue touchée est toujours la vue racine du
/// `UIHostingController`, même sur un bouton, donc elle ne dit pas si l'on vise le bandeau.
private final class BannerWindow: UIWindow {

    /// Cadre du bandeau, `.zero` sans invitation.
    var bannerFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        bannerFrame.contains(point) ? super.hitTest(point, with: event) : nil
    }
}

/// Le bandeau « X t'invite à regarder ensemble », Rejoindre en vert, Refuser en rouge.
///
/// À la place d'une alerte système, qui ne sait colorer qu'une action destructrice.
/// Se ferme seul au bout de 15 s, comme le message que le serveur envoie aux autres clients.
private struct SyncPlayInviteBannerView: View {

    /// Comme le message que le serveur affiche sur les autres clients.
    private static let duration: Duration = .seconds(15)

    @ObservedObject
    var manager: SyncPlayManager

    /// Reçoit le cadre du bandeau (dans la fenêtre), `.zero` quand il disparaît.
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if let invite = manager.pendingInvite {
                banner(invite)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: onFrameChange)
                    .onDisappear { onFrameChange(.zero) }
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
