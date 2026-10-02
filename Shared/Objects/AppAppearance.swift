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
/// Ce type ne porte que l'identité d'un thème ; tout ce qu'il décide est dans
/// ``ThemeTokens``. Ajouter un thème, c'est donc un `case` ici et un littéral là-bas —
/// que le compilateur réclame tant qu'il manque.
enum AppAppearance: String, CaseIterable, Displayable, Storable {

    /// **Default** : fond bleu nuit `#111827`, accent indigo `#5D55E7` (couleurs
    /// inspirées du thème web ElegantFin, tout le reste est à nous). Fond de l'Accueil =
    /// backdrop flouté de la media bar.
    case standard

    /// **Default - Purple** : Default avec l'accent violet de Jellyfin `#AA5CC3`.
    case standardPurple

    /// **Dark** : fond noir pur, accent blanc.
    case dark

    var displayTitle: String {
        switch self {
        case .standard:
            "Default"
        case .standardPurple:
            "Default - Purple"
        case .dark:
            "Dark"
        }
    }
}
