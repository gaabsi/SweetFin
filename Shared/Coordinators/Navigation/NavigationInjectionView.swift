//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import PreferencesView
import SwiftUI

struct NavigationInjectionView: View {

    // SweetFin : `\.appearance` est l'apparence **résolue** posée par
    // `RootCoordinator.applyAppearance`, et non le réglage brut — celui-ci diffère
    // selon qu'on est connecté ou non.
    @Default(.appearance)
    private var appearance

    @StateObject
    private var coordinator: NavigationCoordinator

    private let content: AnyView

    init(
        coordinator: @autoclosure @escaping () -> NavigationCoordinator,
        @ViewBuilder content: @escaping () -> some View
    ) {
        _coordinator = StateObject(wrappedValue: coordinator())
        self.content = AnyView(content())
    }

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            content
                .themeContainerBackground(appearance.tokens.background)
                .navigationDestination(for: NavigationRoute.self) { route in
                    route.destination
                        .themeContainerBackground(appearance.tokens.background)
                        .environment(
                            \.router,
                            .init(
                                navigationCoordinator: coordinator,
                                isRootOfPath: false
                            )
                        )
                }
        }
        .trackingFrame(for: .navigationStack)
        .environment(
            \.router,
            .init(
                navigationCoordinator: coordinator,
                isRootOfPath: true
            )
        )
        .environmentObject(coordinator)
        #if os(tvOS)
        .fullScreenCover(
            item: $coordinator.presentedSheet
        ) {
            coordinator.presentedSheet = nil
        } content: { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
            .background(.regularMaterial)
        }
        .fullScreenCover(
            item: $coordinator.presentedFullScreen
        ) { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
        }
        #else
        .sheet(
            item: $coordinator.presentedSheet
        ) {
            coordinator.presentedSheet = nil
        } content: { presentedRoute in
            NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                presentedRoute.route.destination
            }
        }
        // SweetFin : seul le lecteur est présenté en plein écran → verrouillé en paysage sur
        // iPhone (iPad libre). Plein écran standard (comme tvOS) : avec le zoom de Transmission,
        // le retour en portrait n'arrivait qu'après l'animation de fermeture (accueil affiché en
        // paysage, puis pivoté). Le masque est posé ici, hors de la `NavigationStack` : une
        // préférence ne la traverse pas.
        .fullScreenCover(
            item: $coordinator.presentedFullScreen
        ) { presentedRoute in
            PreferencesView {
                NavigationInjectionView(coordinator: presentedRoute.coordinator) {
                    presentedRoute.route.destination
                }
                .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : .landscape)
            }
            .ignoresSafeArea()
            .background(Color.black)
            .onDisappear { Self.rotateToPortrait() }
        }
        #endif
    }

    #if os(iOS)
    /// SweetFin : ramène l'écran en portrait à la fermeture du lecteur (iPhone). À l'ouverture,
    /// rien à demander : le masque paysage du lecteur suffit à faire pivoter (vérifié sur iPhone,
    /// la demande y était d'ailleurs refusée, partie trop tôt).
    private static func rotateToPortrait() {
        guard !UIDevice.isPad,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
    #endif
}

// SweetFin : aussi utilisé par les feuilles qui ont leur propre `NavigationStack`
// (`SeasonsContentGroup`).
extension View {

    /// Pose le fond du thème sur le **conteneur de navigation**.
    ///
    /// ⚠️ **Pourquoi `containerBackground` et pas `background`.** Un `.background`
    /// n'est dessiné qu'une fois la vue montée : à la première ouverture d'un onglet,
    /// le `UINavigationController` que SwiftUI vient de créer s'affichait avec son
    /// fond système opaque — une image noire avant le bleu. `containerBackground`
    /// peint le conteneur lui-même, dans la passe de layout qui le crée, donc sans
    /// trou. C'est aussi ce qui a permis de supprimer la teinte UIKit manuelle qui
    /// courait derrière cette image.
    ///
    /// ⚠️ **À poser sur chaque vue de la pile**, racine comme destination poussée :
    /// SwiftUI lit la valeur portée par la vue affichée, et non une fois pour toutes.
    ///
    /// ⚠️ **iOS uniquement.** Le placement `.navigation` est indisponible sur tvOS,
    /// qui garde le fond du système.
    ///
    /// Parametres :
    /// - color (Color) : le fond du thème
    @ViewBuilder
    func themeContainerBackground(_ color: Color) -> some View {
        #if os(iOS)
        containerBackground(color, for: .navigation)
        #else
        self
        #endif
    }
}
