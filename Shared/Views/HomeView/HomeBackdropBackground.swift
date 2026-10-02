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
                .pageBackground { base in
                    MediaBarBackdropBackground(base: base)
                }
        }
    }
}

extension View {

    /// SweetFin : fond d'une page (Accueil, fiche) selon le thème. Rien à faire pour un
    /// fond uni (la pile de navigation le peint déjà) ; sinon le backdrop flouté que la
    /// page fournit, à partir du fond du thème.
    ///
    /// Parametres :
    /// - backdrop ((Color) -> Backdrop) : le fond flouté, construit sur la couleur du thème
    func pageBackground(@ViewBuilder _ backdrop: @escaping (Color) -> some View) -> some View {
        modifier(PageBackgroundModifier(backdrop: backdrop))
    }
}

private struct PageBackgroundModifier<Backdrop: View>: ViewModifier {

    let backdrop: (Color) -> Backdrop

    @Default(.appearance)
    private var appearance

    func body(content: Content) -> some View {
        switch appearance.tokens.pageBackground {
        case .solid:
            content
        case .blurredBackdrop:
            #if os(iOS)
            // Même API que le fond uni (`themeContainerBackground`) : peint dans la passe
            // de layout du conteneur, donc sans image noire à l'ouverture de la page.
            content.containerBackground(for: .navigation) {
                backdrop(appearance.tokens.background)
            }
            #else
            content
            #endif
        }
    }
}

/// Le backdrop de la diapo affichée, suivi en temps réel.
private struct MediaBarBackdropBackground: View {

    let base: Color

    @ObservedObject
    private var backdrop = Container.shared.homeBackdrop()

    var body: some View {
        BlurredBackdropBackground(item: backdrop.item, base: base)
    }
}

/// SweetFin : le backdrop d'un média en verre dépoli — fortement flouté, assombri pour
/// que les textes restent lisibles, et fondu vers le suivant quand le média change.
///
/// Image demandée en **basse résolution** : floutée, une grande image n'apporterait
/// rien, et le serveur redimensionne à la volée.
struct BlurredBackdropBackground: View {

    let item: BaseItemDto?
    let base: Color

    var body: some View {
        ZStack {
            base

            if let item {
                // L'image remplit un calque de la taille du fond, sans jamais le dépasser :
                // posée seule en `.fill`, elle agrandissait toute la pile selon ses
                // proportions, et le fond virait au noir (images du serveur de démo).
                Color.clear
                    .overlay {
                        ImageView(item.imageSource(.backdrop, environment: ImageSourceOptions(maxWidth: 320)))
                            .failure { Color.clear }
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .blur(radius: 60)
                    .opacity(0.55)
                    // Une image par média : le changement se fait en fondu.
                    .id(item.id)
                    .transition(.opacity)
            }

            LinearGradient(
                colors: [base.opacity(0.35), base.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 1.2), value: item?.id)
        .ignoresSafeArea()
    }
}
