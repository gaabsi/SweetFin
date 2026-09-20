//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Ce qu'un filtre de section doit savoir de lui-même pour s'afficher.
///
/// Deux sections de l'Explorer en ont un — les rayons de la watchlist et les vues
/// des tendances — et leur sélecteur est le même à l'énumération près.
protocol ExplorerFilter: CaseIterable, Identifiable, Hashable {

    var displayTitle: String { get }
}

extension WatchlistFilter: ExplorerFilter {

    var displayTitle: String {
        switch self {
        case .all: ExplorerStrings.allTypes
        case .movie: ExplorerStrings.moviesOnly
        case .tv: ExplorerStrings.seriesOnly
        case .anime: ExplorerStrings.animesOnly
        }
    }

    /// Titre de l'écran ouvert par « Voir plus ».
    ///
    /// « Ma watchlist · Tout » n'aurait aucun sens : sans rayon, c'est la watchlist,
    /// point.
    var pageTitle: String {
        self == .all
            ? ExplorerStrings.watchlistSection
            : ExplorerStrings.watchlistCategory(displayTitle)
    }
}

// `displayTitle` est déclaré **ici** et non sur le type lui-même : celui-ci vit dans
// `EnhancedFinModels`, qui décrit le contrat du plugin et n'a pas à connaître les
// libellés du fork.
extension EnhancedFinTrendingFilter: ExplorerFilter {

    var displayTitle: String {
        switch self {
        case .all: ExplorerStrings.allTypes
        case .movie: ExplorerStrings.moviesOnly
        case .tv: ExplorerStrings.seriesOnly
        case .anime: ExplorerStrings.animesOnly
        }
    }
}

/// Sélecteur segmenté d'un filtre de section.
struct ExplorerFilterPicker<Filter: ExplorerFilter>: View {

    /// Sert de libellé d'accessibilité — le sélecteur segmenté ne l'affiche pas.
    let title: String

    @Binding
    var selection: Filter

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Filter.allCases)) { option in
                Text(option.displayTitle).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .edgePadding(.horizontal)
    }
}

/// Titre de section, cliquable quand il y a une suite à montrer.
///
/// Reprend l'en-tête de `PosterHStackLibrarySection`, celui de l'écran d'Accueil :
/// **titre et chevron accolés**, chevron en `.secondary`. L'Explorer avait un
/// « Voir plus › » aligné à droite de l'écran — une forme qu'on ne trouve nulle part
/// ailleurs dans l'app, et qui donnait deux silhouettes d'en-tête différentes selon
/// que la section avait une suite ou non.
///
/// Le titre **fait partie du bouton** : viser une ligne entière au doigt est plus
/// facile qu'un chevron.
struct ExplorerSectionHeader: View {

    let title: String

    /// Nombre d'éléments, quand le savoir motive l'action — « à noter » surtout.
    /// `nil` partout ailleurs : un compteur sur chaque section n'informerait plus.
    var count: Int? = nil

    /// `nil` pour une section sans suite à montrer.
    var seeAll: (() -> Void)? = nil

    var body: some View {
        if let seeAll {
            Button(action: seeAll) {
                HStack(spacing: 3) {
                    label

                    Image(systemName: "chevron.forward")
                        .font(.title3)
                }
            }
            .foregroundStyle(.primary, .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .edgePadding(.horizontal)
        } else {
            label
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .edgePadding(.horizontal)
        }
    }

    @ViewBuilder
    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let count {
                Text(count, format: .number)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
