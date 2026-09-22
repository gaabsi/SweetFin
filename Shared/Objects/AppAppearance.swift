//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Les thèmes proposés par l'application.
///
/// ⚠️ **EnhancedFin : le fork est sombre, et un thème y est complet.** Les apparences
/// upstream — Système, Sombre, Clair — ont été remplacées, pas complétées. Une
/// application de médiathèque se regarde dans le noir : « Clair » n'était jamais
/// utilisé, et « Système » pouvait ramener l'app en clair sur un appareil clair, avec
/// des couleurs de texte pensées pour du sombre.
///
/// ### Ajouter un thème
///
/// Un `case` de plus, et le compilateur fait le reste : les `switch` ci-dessous sont
/// **exhaustifs et sans `default:`**, donc il lève une erreur sur chacun des quatre
/// tokens tant qu'ils ne sont pas renseignés. C'est volontaire — c'est ce qui rend
/// impossible d'ajouter un thème en oubliant sa couleur d'accent ou son fond.
enum AppAppearance: String, CaseIterable, Displayable, Storable {

    /// Le thème web **ElegantFin** (`lscambo13/ElegantFin`) : indigo `#5D55E7`
    /// (`--accentColor: hsl(243, 75%, 62%)`) sur bleu nuit `#111827`
    /// (`--darkerGradientPoint`).
    case elegantFin

    var displayTitle: String {
        switch self {
        case .elegantFin:
            "ElegantFin"
        }
    }

    /// Le style d'interface imposé par le thème.
    ///
    /// Tous les thèmes sont sombres aujourd'hui, mais ça reste un token **par thème**
    /// plutôt qu'un `.dark` en dur : un thème clair resterait une simple addition.
    var style: UIUserInterfaceStyle {
        switch self {
        case .elegantFin:
            .dark
        }
    }

    /// Couleur d'accent du thème.
    ///
    /// ⚠️ Elle écrase la couleur choisie dans les réglages — c'est le propre d'un
    /// thème. Changer de thème ne restitue pas l'ancienne : il faut la reprendre à la
    /// main.
    var accentColor: Color {
        switch self {
        case .elegantFin:
            Color(uiColor: .elegantFinAccent)
        }
    }

    /// Fond du thème, peint par ``themeContainerBackground(_:)`` et par ``RootView``.
    ///
    /// ⚠️ Toute valeur ajoutée ici doit l'être **aussi** dans le color set
    /// `LaunchBackground` si c'est le thème par défaut : l'écran de lancement est
    /// rendu par iOS avant que le code s'exécute, il ne peut pas lire ce token.
    var backgroundColor: Color {
        switch self {
        case .elegantFin:
            Color(uiColor: .elegantFinBackground)
        }
    }
}

private extension UIColor {

    /// `hsl(243, 75%, 62%)`
    static let elegantFinAccent = UIColor(red: 93 / 255, green: 85 / 255, blue: 231 / 255, alpha: 1)

    /// `#111827`
    static let elegantFinBackground = UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 1)
}
