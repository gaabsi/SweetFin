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
}
