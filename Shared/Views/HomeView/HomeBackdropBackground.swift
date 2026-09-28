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

extension Container {

    var homeBackdrop: Factory<HomeBackdrop> {
        self { @MainActor in HomeBackdrop() }
            .singleton
    }
}

/// SweetFin : le média affiché par la media bar, pour le fond de l'Accueil.
///
/// La media bar l'écrit à chaque changement de diapo ; le fond de l'Accueil le lit. Rien
/// d'autre n'y touche.
@MainActor
final class HomeBackdrop: ObservableObject {

    @Published
    var item: BaseItemDto?
}

extension TabItem {

    /// SweetFin : l'Accueil du fork, avec le fond que son thème demande.
    static var home: TabItem {
        let provider = HomeContentGroupProvider()

        return TabItem(
            id: provider.id,
            title: provider.displayTitle,
            systemImage: "house.fill"
        ) {
            ContentGroupView(provider: provider)
                .homeBackground()
        }
    }
}

private extension View {

    /// Fond de l'Accueil selon le thème : rien à faire pour un fond uni (la pile de
    /// navigation le peint déjà), le backdrop de la media bar si le thème le demande.
    func homeBackground() -> some View {
        modifier(HomeBackgroundModifier())
    }
}

private struct HomeBackgroundModifier: ViewModifier {

    @Default(.appearance)
    private var appearance

    func body(content: Content) -> some View {
        switch appearance.tokens.homeBackground {
        case .solid:
            content
        case .mediaBarBackdrop:
            #if os(iOS)
            // Même API que le fond uni (`themeContainerBackground`) : peint dans la passe
            // de layout du conteneur, donc sans image noire à l'ouverture de l'onglet.
            content.containerBackground(for: .navigation) {
                MediaBarBackdropBackground(base: appearance.tokens.background)
            }
            #else
            content
            #endif
        }
    }
}

/// Le backdrop de la diapo affichée, en verre dépoli : fortement flouté, assombri pour
/// que les textes restent lisibles, et fondu vers le suivant au changement de diapo.
///
/// Image demandée en **basse résolution** : floutée, une grande image n'apporterait
/// rien, et le Pi redimensionne à la volée.
private struct MediaBarBackdropBackground: View {

    let base: Color

    @ObservedObject
    private var backdrop = Container.shared.homeBackdrop()

    var body: some View {
        ZStack {
            base

            if let item = backdrop.item {
                ImageView(item.imageSource(.backdrop, environment: ImageSourceOptions(maxWidth: 320)))
                    .failure { Color.clear }
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .opacity(0.55)
                    // Une image par média : le changement de diapo se fait en fondu.
                    .id(item.id)
                    .transition(.opacity)
            }

            LinearGradient(
                colors: [base.opacity(0.35), base.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 1.2), value: backdrop.item?.id)
        .ignoresSafeArea()
    }
}
