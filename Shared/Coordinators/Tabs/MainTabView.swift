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

    init() {
        _tabCoordinator = StateObject(wrappedValue: Self.defaultTabCoordinator)
    }

    private static var defaultTabCoordinator: TabCoordinator {
        #if os(iOS)
        TabCoordinator {
            // EnhancedFin : Accueil du fork — carrousel, bibliothèques, reprise
            // fusionnée, ajouts récents. `DefaultContentGroupProvider` reste intact
            // et sert toujours tvOS ; le remplacer ici plutôt que le modifier garde
            // le rebase indolore.
            // EnhancedFin : `.home` = cet Accueil + le fond que son thème demande (GlassFin).
            TabItem.home
            // EnhancedFin : `TabItem.search` retiré — l'Explorer porte la recherche,
            // et cherche plus large (référentiel + TMDB + bibliothèque, là où la
            // recherche native ne voit que la bibliothèque). Deux onglets à la loupe
            // n'auraient rien apporté.
            //
            // ⚠️ Effet de bord : le rôle iOS 26 est attribué par identifiant plus bas
            // (`tab.item.id == TabItem.search.id ? .search : nil`). Sans cet onglet,
            // plus aucune tuile ne porte `.search`, donc la capsule de recherche
            // flottante disparaît de la barre.
            TabItem.media
            TabItem.calendar
            // EnhancedFin : iPhone seulement — une TV ne part pas en voyage.
            TabItem.downloads
        }
        #else
        // EnhancedFin : les onglets d'iOS, plus Réglages — tvOS n'a pas le bouton de
        // profil en haut à droite qui les ouvre sur iOS. Séries, Films et Recherche
        // d'upstream retirés pour les mêmes raisons que sur iOS (« Mes médias » sur
        // l'Accueil, l'Explorer porte la recherche). `DefaultContentGroupProvider`
        // reste intact.
        TabCoordinator {
            TabItem.contentGroup(provider: HomeContentGroupProvider())
            TabItem.media
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
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                Tab(
                    value: tab.item.id,
                    role: tab.item.id == TabItem.search.id ? .search : nil
                ) {
                    NavigationInjectionView(
                        coordinator: tab.coordinator
                    ) {
                        tab.item.content
                            #if os(iOS)
                                .if(tabCoordinator.tabs.first?.item.id == tab.item.id) { view in
                                    view.topBarTrailing {
                                        FirstTabSettingsBarButton()
                                    }
                                }
                            #endif
                    }
                    .environmentObject(tabCoordinator)
                    .environment(\.tabItemSelected, tab.publisher)
                } label: {
                    #if os(iOS)
                    // EnhancedFin : icônes seules sur iPhone — la barre reste compacte avec
                    // « Téléchargements », trop long. Le titre reste annoncé par VoiceOver.
                    // tvOS garde ses libellés (barre latérale lue à distance).
                    Image(systemName: tab.item.systemImage)
                        .symbolRenderingMode(.monochrome)
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
            // EnhancedFin : au lancement et au retour du réseau, envoyer la progression
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
    /// EnhancedFin : envoie à Jellyfin les positions des téléchargements lus sans réseau,
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
