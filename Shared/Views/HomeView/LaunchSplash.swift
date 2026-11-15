//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// SweetFin : l'Accueil prévient qu'il a fini son premier chargement.
///
/// Partagé entre le chargement (`ContentGroupViewModel`) et l'écran de lancement
/// (``LaunchSplashOverlay``), qui ne se connaissent pas.
@MainActor
final class LaunchSplash: ObservableObject {

    static let shared = LaunchSplash()

    @Published
    private(set) var isHomeReady = false

    /// L'Accueil est chargé (ou en erreur : le logo laisse alors place au message).
    func homeReady() {
        guard !isHomeReady else { return }
        isHomeReady = true
    }

    /// Pas d'Accueil à attendre (choix du compte, erreur au démarrage) : le logo s'en va.
    func skip() {
        guard !isHomeReady else { return }
        isHomeReady = true
    }
}

/// SweetFin : suite de l'écran de lancement d'iOS (`UILaunchScreen`), posée par `RootView`
/// dès la première image. Même logo, même taille, même place : le passage du système à
/// l'app ne se voit pas. Le logo reste immobile au moins `minimumDuration`, le temps que
/// l'Accueil charge ; une fois l'Accueil prêt, il grossit et s'efface pour le laisser apparaître. Une durée minimale plutôt qu'une roue : l'arrivée
/// est toujours la même, et rien ne donne l'impression d'une connexion absente.
struct LaunchSplashOverlay: View {

    /// Durée minimale du logo fixe. Mesurée sur 61 lancements (2-14 nov. 2026, iPhone) :
    /// Accueil prêt en 0,51 s (médiane), 75 % avant 0,8 s, 87 % avant 2 s. 0,6 s : un
    /// peu au-dessus de la médiane, le logo ne fait pas « flash » (avant : 0,8 s).
    private static let minimumDuration: Duration = .milliseconds(600)
    private static let zoomDuration = 0.45
    /// Grossissement final. Le logo démarre à la taille de l'écran de lancement (image de
    /// 250 pt) : 1,92 le mène à 480 pt, la taille choisie sur les prototypes (×4 d'un logo de 120 pt).
    private static let zoomScale = 1.92
    /// Au-delà, une roue discrète sous le logo : le chargement est anormalement long.
    private static let slowAfter: Duration = .seconds(3)
    /// Au-delà, le logo s'en va quoi qu'il arrive : l'app ne reste jamais bloquée derrière.
    private static let giveUpAfter: Duration = .seconds(10)

    @Default(.appearance)
    private var appearance

    @ObservedObject
    private var splash = LaunchSplash.shared

    @State
    private var isZooming = false
    @State
    private var isGone = false
    @State
    private var isSlow = false

    var body: some View {
        if !isGone {
            ZStack {
                appearance.tokens.background
                    .ignoresSafeArea()
                    .opacity(isZooming ? 0 : 1)

                // Taille propre de l'image, centrée dans la zone sûre : comme `UILaunchScreen`
                // (`UIImageRespectsSafeAreaInsets`). La roue ne déplace pas le logo.
                Image(.appLogo)
                    .scaleEffect(isZooming ? Self.zoomScale : 1)
                    .opacity(isZooming ? 0 : 1)
                    .overlay(alignment: .bottom) {
                        ProgressView()
                            .offset(y: 24)
                            .opacity(isSlow && !isZooming ? 1 : 0)
                    }
            }
            .allowsHitTesting(!isZooming)
            .task {
                await run()
            }
        }
    }

    private func run() async {
        let clock = ContinuousClock()
        let start = clock.now
        let slow = Task {
            guard (try? await Task.sleep(for: Self.slowAfter)) != nil else { return }
            isSlow = true
        }
        defer { slow.cancel() }

        // Vue retirée (tâche annulée) : on s'arrête, sans boucler.
        do {
            try await Task.sleep(for: Self.minimumDuration)
            while !splash.isHomeReady, clock.now - start < Self.giveUpAfter {
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            return
        }

        withAnimation(.easeOut(duration: Self.zoomDuration)) {
            isZooming = true
        }
        try? await Task.sleep(for: .seconds(Self.zoomDuration))
        isGone = true
    }
}
