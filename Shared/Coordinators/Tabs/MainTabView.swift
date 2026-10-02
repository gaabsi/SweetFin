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
import SwiftUI

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    #if os(tvOS)
    @Default(.Customization.tabBarPlacement)
    private var tabBarPlacement
    #endif

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    #if os(iOS)
    @InjectedObject(\.offlineMonitor)
    private var offlineMonitor
    #endif

    @StateObject
    private var tabCoordinator: TabCoordinator

    // Observée : un changement redessine la barre (lue par `EnhancedFinClient.isAvailable`).
    @Default(.enhancedFinAvailable)
    private var enhancedFinAvailable

    /// SweetFin : les onglets à afficher selon le plugin. Tous sont créés une fois,
    /// chacun garde sa navigation pendant qu'il est masqué.
    private var visibleTabs: [TabCoordinator.TabData] {
        tabCoordinator.tabs.filter {
            $0.item.availability.isVisible(pluginAvailable: EnhancedFinClient.isAvailable)
        }
    }

    init() {
        _tabCoordinator = StateObject(wrappedValue: Self.defaultTabCoordinator)
    }

    private static var defaultTabCoordinator: TabCoordinator {
        #if os(iOS)
        TabCoordinator {
            // SweetFin : Accueil du fork — carrousel, bibliothèques, reprise
            // fusionnée, ajouts récents — avec le fond que son thème demande (backdrop de la media bar).
            TabItem.home
            // SweetFin : l'Explorer porte la recherche (référentiel + TMDB +
            // bibliothèque) ; sans le plugin, la Recherche native prend sa place.
            TabItem.media
            TabItem.search
            TabItem.calendar
            // SweetFin : iPhone seulement — une TV ne part pas en voyage.
            TabItem.downloads
        }
        #else
        // SweetFin : les onglets d'iOS, plus Réglages — tvOS n'a pas le bouton de
        // profil en haut à droite qui les ouvre sur iOS. Séries et Films d'upstream
        // retirés pour les mêmes raisons que sur iOS (« Mes médias » sur l'Accueil).
        TabCoordinator {
            TabItem.contentGroup(provider: HomeContentGroupProvider())
            TabItem.media
            TabItem.search
            TabItem.calendar
            TabItem.settings
        }
        #endif
    }

    private func routePendingDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        Task { @MainActor in
            let route = deepLink.route()
            await tabCoordinator.route(to: route)
        }
    }

    @ViewBuilder
    private func tabView() -> some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(visibleTabs, id: \.item.id) { tab in
                Tab(value: tab.item.id) {
                    NavigationInjectionView(
                        coordinator: tab.coordinator
                    ) {
                        tab.item.content
                            #if os(iOS)
                                .if(tabCoordinator.tabs.first?.item.id == tab.item.id) { view in
                                    view.toolbar {
                                        firstTabToolbar()
                                    }
                                }
                            #endif
                    }
                    .environmentObject(tabCoordinator)
                    .environment(\.tabItemSelected, tab.publisher)
                } label: {
                    #if os(iOS)
                    // SweetFin : icônes seules sur iPhone — la barre reste compacte avec
                    // « Téléchargements », trop long. Le titre reste annoncé par VoiceOver.
                    // tvOS garde ses libellés (barre latérale lue à distance).
                    // Variante imposée par le nom : iOS remplirait `arrow.down.app`, voulu en
                    // contour ; une icône pleine l'écrit elle-même (`house.fill`).
                    Image(systemName: tab.item.systemImage)
                        .symbolRenderingMode(.monochrome)
                        .environment(\.symbolVariants, .none)
                        .accessibilityLabel(tab.item.displayTitle)
                    #else
                    Label(
                        tab.item.displayTitle,
                        systemImage: tab.item.systemImage
                    )
                    .symbolRenderingMode(.monochrome)
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private func tabContent() -> some View {
        #if os(tvOS)
        switch tabBarPlacement {
        case .sidebar:
            tabView()
                .tabViewStyle(.sidebarAdaptable)
        case .tabBar:
            tabView()
                .tabViewStyle(.tabBarOnly)
        }
        #else
        tabView()
        #endif
    }

    var body: some View {
        tabContent()
            // SweetFin : l'onglet affiché vient de disparaître (plugin installé ou
            // retiré) : retour au premier, l'Accueil.
            .onChange(of: enhancedFinAvailable) {
                guard !visibleTabs.contains(where: { $0.item.id == tabCoordinator.selectedTabID }) else { return }
                tabCoordinator.selectedTabID = visibleTabs.first?.item.id
            }
            .onChange(of: userSessionManager.pendingDeepLink) {
                routePendingDeepLink(userSessionManager.consumePendingDeepLink())
            }
            .onReceive(userSessionManager.routePublisher) { route in
                Task { @MainActor in
                    await tabCoordinator.route(to: route)
                }
            }
            #if os(tvOS)
            .background(alignment: .top) {
                FocusedPosterCinematicBackgroundView()
            }
            #else
            // SweetFin : invitation SyncPlay reçue, quel que soit l'onglet.
            .ifLet(userSessionManager.currentSession?.syncPlayManager) { view, manager in
                view.modifier(SyncPlayInviteBanner(manager: manager))
            }
            // SweetFin : au lancement et au retour du réseau, envoyer la progression
            // notée hors connexion ; au retour du réseau, recharger aussi les onglets
            // restés en erreur. Pas de bascule automatique vers les téléchargements
            // (retirée, jugée inutile).
            // ⚠️ Tâche détachée, pas `.task` : SwiftUI annulait l'envoi quand la vue se
            // reconstruisait au lancement (« annulé » dans les logs), et rien ne le relançait
            // avant le prochain changement de réseau.
            .onAppear {
                Task {
                    if await syncOfflineProgress() {
                        Notifications[.didRequestGlobalRefresh].post()
                    }
                }
            }
            .onChange(of: offlineMonitor.isOffline) { wasOffline, isOffline in
                guard wasOffline, !isOffline else { return }
                Task {
                    await syncOfflineProgress()
                    Notifications[.didRequestGlobalRefresh].post()
                }
            }
            #endif
    }

    #if os(iOS)
    /// SweetFin : envoie à Jellyfin les positions des téléchargements lus sans réseau,
    /// **puis** recopie en local celles qu'il connaît (dans cet ordre, pour ne pas écraser
    /// ce qu'on vient d'envoyer).
    ///
    /// Output :
    /// - didSync (Bool) : vrai si au moins une position a été envoyée
    @discardableResult
    private func syncOfflineProgress() async -> Bool {
        guard let session = userSessionManager.currentSession else { return false }
        let manager = Container.shared.downloadManager()
        let didSync = await manager.syncOfflineProgress(userSession: session)
        await manager.refreshStoredProgress(userSession: session)
        return didSync
    }
    #endif
}

#if os(iOS)
extension MainTabView {

    /// SweetFin : « o O » — petit bouton SyncPlay, puis la photo de profil dans sa propre
    /// bulle. Sous iOS 26, des éléments d'un même groupe partagent une capsule de verre :
    /// le `ToolbarSpacer` les sépare, et le bouton SyncPlay dessine sa bulle, plus petite.
    @ToolbarContentBuilder
    func firstTabToolbar() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                FirstTabSyncPlayButton()
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                FirstTabSettingsBarButton()
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                FirstTabSyncPlayButton()
                FirstTabSettingsBarButton()
            }
        }
    }
}

private struct FirstTabSyncPlayButton: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    var body: some View {
        if router.isRootOfPath, let userSession {
            SyncPlayBarButton(manager: userSession.syncPlayManager)
        }
    }
}

private struct FirstTabSettingsBarButton: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    var body: some View {
        if router.isRootOfPath,
           let userSession
        {
            SettingsBarButton(
                server: userSession.server,
                user: userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }
}
#endif
