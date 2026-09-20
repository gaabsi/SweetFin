//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Filmographie d'une personne, filtrable par type et triable.
///
/// Contient aussi les rôles absents du serveur : c'est tout l'intérêt de la page,
/// la vue native ne sait lister que ce dont on possède un fichier.
///
/// Le tri et le filtre sont appliqués **côté client** : le serveur a déjà envoyé la
/// liste entière, score de popularité compris, et la retrier ne vaut pas un
/// aller-retour.
///
/// Conséquence assumée : les deux tris réordonnent les crédits **retenus** par le
/// serveur, qui plafonne la liste aux plus populaires. Trier par date ne fait donc
/// pas remonter un rôle obscur que la sélection a écarté en amont.
struct FilmographyGroup: ContentGroup {

    /// Critère de tri.
    enum Sort: String, CaseIterable, Identifiable {

        case popularity
        case date

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .popularity: ExplorerStrings.sortByPopularity
            case .date: ExplorerStrings.sortByDate
            }
        }

        var systemImage: String {
            switch self {
            case .popularity: "flame"
            case .date: "calendar"
            }
        }
    }

    /// Type de média retenu.
    enum TypeFilter: String, CaseIterable, Identifiable {

        case all
        case movie
        case tv

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .all: ExplorerStrings.allTypes
            case .movie: ExplorerStrings.moviesOnly
            case .tv: ExplorerStrings.seriesOnly
            }
        }

        func accepts(_ credit: EnhancedFinPersonCredit) -> Bool {
            self == .all || credit.mediaType == rawValue
        }
    }

    let id = "enhancedfin-filmography"
    let credits: [EnhancedFinPersonCredit]

    func body(with viewModel: Empty) -> Body {
        Body(credits: credits)
    }

    struct Body: View {

        /// La popularité par défaut : sur une filmographie, on cherche d'abord les
        /// rôles qu'on reconnaît, pas le dernier tournage en date.
        @State
        private var sort: Sort = .popularity

        @State
        private var typeFilter: TypeFilter = .all

        let credits: [EnhancedFinPersonCredit]

        /// Les types réellement présents, pour ne pas proposer « Séries » à
        /// quelqu'un qui n'a tourné que des films.
        private var availableTypes: [TypeFilter] {
            let present = Set(credits.map(\.mediaType))
            return TypeFilter.allCases.filter { $0 == .all || present.contains($0.rawValue) }
        }

        private var visible: [EnhancedFinPersonCredit] {
            let filtered = credits.filter(typeFilter.accepts)

            return switch sort {
            case .date:
                // L'ordre du serveur, déjà chronologique inverse.
                filtered
            case .popularity:
                filtered.sorted { $0.popularity > $1.popularity }
            }
        }

        /// Applique le tri une fois le menu refermé, et sans animation.
        ///
        /// Le libellé du menu était interpolé d'une valeur à l'autre — « pular »
        /// avant « Popularité ». L'animation ne vient pas du binding mais de la
        /// **fermeture du menu**, animée par UIKit : l'écriture ayant lieu pendant
        /// cette transaction, la désactiver côté SwiftUI n'y change rien. Différer
        /// d'un tour de boucle sort de cette transaction.
        ///
        /// C'est le correctif, et il se suffit. Un `.transaction { $0.animation =
        /// nil }` posé sur le libellé faisait double emploi avec lui, et coupait au
        /// passage toute animation future de ce sous-arbre — un outil trop large
        /// pour le problème.
        private func select(_ newValue: Sort) {
            Task { @MainActor in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { sort = newValue }
            }
        }

        @ViewBuilder
        private var header: some View {
            HStack {
                Text(ExplorerStrings.filmography)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Menu {
                    // Des boutons et non un `Picker` : celui-ci porte sa propre
                    // animation de sélection, dont on ne veut pas ici.
                    ForEach(Sort.allCases) { option in
                        Button {
                            select(option)
                        } label: {
                            Label(option.displayTitle, systemImage: option.systemImage)
                        }
                    }
                } label: {
                    // La largeur est réservée par le plus long libellé. Ce n'est pas
                    // une mesure anti-animation de plus : « Popularité » et « Date »
                    // n'ont pas la même largeur, donc sans réservation le bouton —
                    // et avec lui le titre de section, calé dessus par le `Spacer` —
                    // se décale à chaque changement de tri. L'en-tête reste immobile.
                    AlternateLayoutView(alignment: .trailing) {
                        Text(ExplorerStrings.sortByPopularity)
                            .font(.subheadline)
                    } content: {
                        Text(sort.displayTitle)
                            .font(.subheadline)
                            // Assurance à coût nul, qui documente l'intention : pas
                            // d'interpolation caractère par caractère d'un libellé
                            // à l'autre.
                            .contentTransition(.identity)
                    }
                }
            }
            .edgePadding(.horizontal)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                header

                // Masqué quand la personne n'a qu'un seul type à son actif : un
                // sélecteur à une seule option utile n'apporte rien.
                if availableTypes.count > 2 {
                    Picker(ExplorerStrings.filmography, selection: $typeFilter) {
                        ForEach(availableTypes) { option in
                            Text(option.displayTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .edgePadding(.horizontal)
                }

                // Même grille et même règle d'ouverture que le reste de l'Explorer
                // — en bibliothèque la fiche native, sinon la fiche de découverte.
                ExplorerPosterGrid(items: visible)
            }
            .padding(.bottom, 24)
        }
    }
}
