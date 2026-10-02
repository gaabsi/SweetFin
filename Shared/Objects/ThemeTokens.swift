//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Tout ce qu'un thème décide, en un seul endroit.
///
/// ⚠️ **C'est ici qu'on ajoute une valeur de thème, et nulle part ailleurs.** Ces
/// réglages vivaient en dur dans cinq fichiers upstream (`PosterButton`,
/// `BaseItemDto+Poster`, `ViewExtensions`…) : cinq conflits de rebase garantis pour du
/// cosmétique, et un second thème qui n'aurait pu changer ni les arrondis ni les
/// ombres, faute d'un endroit où les déclarer.
///
/// Un `struct` et non un fichier de données : le compilateur refuse alors un thème
/// incomplet, et attrape une faute de frappe sur un nom de champ. Un JSON ne
/// donnerait cette garantie qu'à l'exécution — et une app iOS ne peut de toute façon
/// pas gagner de thème sans être recompilée.
struct ThemeTokens {

    /// Le style d'interface imposé. Tous les thèmes sont sombres aujourd'hui, mais
    /// c'est une valeur par thème pour qu'un thème clair reste une simple addition.
    let style: UIUserInterfaceStyle

    /// ⚠️ Écrase la couleur d'accent de l'app. Le réglage utilisateur a été retiré
    /// pour cette raison — voir `RootCoordinator.applyAccentColor`.
    let accent: Color

    /// Peint par `themeContainerBackground(_:)` et par ``RootView``.
    ///
    /// ⚠️ À reporter dans le color set `LaunchBackground` pour le thème par défaut :
    /// l'écran de lancement est rendu par iOS avant que le code s'exécute, il ne peut
    /// pas lire ce token.
    let background: Color

    /// Arrondi des affiches, en proportion de leur largeur.
    let posterCornerRatio: (landscape: CGFloat, portrait: CGFloat)

    /// Ombre portée des affiches.
    ///
    /// La couleur est explicite : `shadow(radius:)` sans couleur applique un noir à
    /// 33 %, invisible sur un fond sombre.
    let posterShadow: (color: Color, radius: CGFloat, y: CGFloat)

    /// Alignement du titre sous une affiche, natif comme EnhancedFin.
    let posterLabelAlignment: HorizontalAlignment

    /// Forme des photos du casting.
    let personPosterShape: PersonPosterShape

    /// Fond de l'Accueil et des fiches : uni (``background``) ou le backdrop du média
    /// affiché (diapo de la media bar, média de la fiche), en flou.
    var pageBackground: PageBackground = .solid

    /// L'équivalent `TextAlignment` de ``posterLabelAlignment``, pour les titres qui
    /// passent à la ligne. Dérivé plutôt que déclaré : deux champs à tenir d'accord
    /// finiraient par diverger.
    var posterLabelTextAlignment: TextAlignment {
        switch posterLabelAlignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}

extension AppAppearance {

    /// Les valeurs du thème.
    ///
    /// `switch` exhaustif sans `default:` : ajouter un `case` à ``AppAppearance`` ne
    /// compile pas tant que ses tokens ne sont pas écrits.
    var tokens: ThemeTokens {
        switch self {
        case .standard:
            Self.tokens(background: Color(uiColor: .standardBackground))
        case .dark:
            Self.tokens(background: .black)
        }
    }

    /// Tout ce que les thèmes partagent : ils ne diffèrent que par le fond.
    ///
    /// Parametres :
    /// - background (Color) : fond de l'app
    ///
    /// Output :
    /// - tokens (ThemeTokens) : les valeurs du thème
    private static func tokens(background: Color) -> ThemeTokens {
        ThemeTokens(
            // Thème sombre : les couleurs de texte supposent un fond foncé, et le
            // laisser suivre le système le rendrait illisible.
            style: .dark,
            accent: Color(uiColor: .standardAccent),
            background: background,
            // Arrondis repris d'ElegantFin (`--smallRadius`, `--largeRadius`) et
            // des cartes du front web. Les valeurs upstream (1/30 et 0,0375)
            // donnaient des coins presque droits, que rien d'autre ne rappelait.
            posterCornerRatio: (landscape: 1 / 16, portrait: 0.065),
            posterShadow: (color: .black.opacity(0.5), radius: 8, y: 4),
            // Titres centrés partout : le fork centrait déjà les siens, et aligner
            // les tuiles natives à gauche donnait deux styles selon l'écran.
            posterLabelAlignment: .center,
            // Casting en ronds, comme le front web d'ElegantFin
            // (`#castCollapsible .cardScalable { border-radius: 50% }`).
            personPosterShape: .circle,
            pageBackground: .blurredBackdrop
        )
    }
}

/// Fond de l'Accueil et des fiches, voir ``ThemeTokens/pageBackground``.
enum PageBackground {

    /// Le fond du thème, uni.
    case solid
    /// Le backdrop du média affiché, flouté et assombri.
    case blurredBackdrop
}

/// Forme des photos du casting, voir ``ThemeTokens/personPosterShape``.
enum PersonPosterShape {

    /// Rond, recadré sur le visage.
    case circle
    /// Affiche portrait, comme un média.
    case poster

    /// Le type d'affiche à demander au rail : un rond ne se découpe que dans un carré.
    var displayType: PosterDisplayType {
        switch self {
        case .circle: .square
        case .poster: .portrait
        }
    }
}

private extension UIColor {

    /// `hsl(243, 75%, 62%)`
    static let standardAccent = UIColor(red: 93 / 255, green: 85 / 255, blue: 231 / 255, alpha: 1)

    /// `#111827`
    static let standardBackground = UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 1)
}
