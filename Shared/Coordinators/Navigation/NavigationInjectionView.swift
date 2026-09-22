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
import Transmission

// TODO: have full screen zoom presentation zoom from/to center
//       - probably need to make mock view with matching ids

struct PresentationControllerShouldDismissPreferenceKey: PreferenceKey {

    static var defaultValue: Bool = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct NavigationInjectionView: View {

    // EnhancedFin : `\.appearance` est l'apparence **résolue** posée par
    // `RootCoordinator.applyAppearance`, et non le réglage brut — celui-ci diffère
    // selon qu'on est connecté ou non.
    @Default(.appearance)
    private var appearance

    @StateObject
    private var coordinator: NavigationCoordinator

    @State
    private var isPresentationInteractive: Bool = true

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
                .themeContainerBackground(appearance.backgroundColor)
                .navigationDestination(for: NavigationRoute.self) { route in
                    route.destination
                        .themeContainerBackground(appearance.backgroundColor)
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
        .presentation(
            $coordinator.presentedFullScreen,
            transition: .zoomIfAvailable(
                .init(
                    dimmingVisualEffect: .systemThickMaterialDark,
                    prefersScalePresentingView: false
                ),
                options: .init(
                    isInteractive: isPresentationInteractive,
                    preferredPresentationSafeAreaInsets: .zero,
                ),
                otherwise: .slide(.init(edge: .bottom), options: .init(isInteractive: isPresentationInteractive))
            )
        ) { presentedRouteBinding, _ in
            let vc = UIPreferencesHostingController {
                NavigationInjectionView(coordinator: presentedRouteBinding.wrappedValue.coordinator) {
                    presentedRouteBinding.wrappedValue.route.destination
                        .onPreferenceChange(PresentationControllerShouldDismissPreferenceKey.self) { newValue in
                            isPresentationInteractive = newValue
                        }
                }
            }

            vc.view.backgroundColor = .black

            return vc
        }
        #endif
    }
}

// EnhancedFin
private extension View {

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
    /// qui n'a de toute façon pas d'apparence à fond coloré.
    ///
    /// Parametres :
    /// - color (Color?) : le fond du thème, ou nil pour garder celui du système
    @ViewBuilder
    func themeContainerBackground(_ color: Color?) -> some View {
        #if os(iOS)
        if let color {
            containerBackground(color, for: .navigation)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
