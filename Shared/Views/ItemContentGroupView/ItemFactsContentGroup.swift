//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// SweetFin : ce que le bloc « infos » d'une fiche affiche.
///
/// Deux sources, une seule forme :
/// - le **plugin** (TMDB), pour toute fiche qui a un identifiant TMDB ;
/// - l'**item Jellyfin** en secours, quand le plugin ne répond pas. Moins complet :
///   son import TMDB ne garde pas toujours la réalisation (vérifié : Hunger Games,
///   Toy Story 5 n'y ont que des producteurs).
struct ItemFacts {

    let genres: [String]

    /// Réalisation d'un film, créateurs d'une série.
    let directors: [String]
    let releaseDate: Date?
    let isSeries: Bool

    /// Note TMDB, sur 10.
    let tmdbRating: Double?

    var hasRatings: Bool {
        tmdbRating != nil
    }

    var isEmpty: Bool {
        genres.isEmpty && directors.isEmpty && releaseDate == nil && !hasRatings
    }

    /// Parametres :
    /// - media (EnhancedFinMedia) : réponse du plugin, demandée avec `detail`
    init(media: EnhancedFinMedia) {
        self.genres = media.genreNames ?? []
        self.directors = media.detail?.directors?.components(separatedBy: ", ").filter(\.isNotEmpty) ?? []
        self.releaseDate = media.detail?.releaseDate.flatMap(DateFormatter.calendarDay.date(from:))
        self.isSeries = EnhancedFinMediaType(mediaKey: media.mediaKey) == .tv
        self.tmdbRating = media.voteAverage
    }

    /// Parametres :
    /// - item (BaseItemDto) : item du serveur, chargé en entier
    init(item: BaseItemDto) {
        let isSeries = item.type == .series
        // Une série n'a pas un réalisateur mais un par épisode : c'est `creator`
        // qui la signe, comme `created_by` côté TMDB.
        let kind: PersonKind = isSeries ? .creator : .director

        self.genres = item.genres ?? []
        self.directors = (item.people ?? [])
            .filter { $0.type == kind }
            .compactMap(\.name)
            .uniqued()
            .map(\.self)
        self.releaseDate = item.premiereDate
        self.isSeries = isSeries
        self.tmdbRating = item.communityRating.map(Double.init)
    }
}

/// SweetFin : le bloc « infos » d'une fiche.
///
/// Repris de la fiche du front web : une carte, une ligne par information,
/// les notes en pied. Il remplace les sections natives Genres et Studios, dont les
/// pastilles ne s'accordaient pas au reste de la fiche. Les studios ne sont pas
/// repris, jugés superflus sur une fiche.
struct ItemFactsContentGroup: ContentGroup {

    let displayTitle = ItemStrings.facts
    let id = "item-facts"

    let facts: ItemFacts

    /// Les lignes de texte, dans l'ordre. Une valeur absente n'a pas de ligne.
    private var rows: [(label: String, value: String)] {
        [
            (
                facts.isSeries ? ItemStrings.firstAired : ItemStrings.releaseDate,
                facts.releaseDate?.formatted(date: .long, time: .omitted) ?? ""
            ),
            (L10n.genres, facts.genres.joined(separator: ", ")),
            (
                facts.isSeries ? ItemStrings.createdBy : ItemStrings.directedBy,
                facts.directors.joined(separator: ", ")
            ),
        ]
        .filter { $0.1.isNotEmpty }
    }

    func body(with viewModel: Empty) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }

                row(rows[index].label) {
                    Text(rows[index].value)
                }
            }

            if facts.hasRatings {
                if rows.isNotEmpty {
                    Divider()
                }

                row(ItemStrings.ratings) {
                    ratings
                }
            }
        }
        .padding(.horizontal, 16)
        .infoCardStyle()
        .edgePadding(.horizontal)
    }

    /// Une ligne : libellé discret en capitales, contenu dessous.
    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content()
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    /// La note TMDB, en pourcentage.
    private var ratings: some View {
        HStack {
            if let tmdbRating = facts.tmdbRating {
                // En pourcentage : 7,3 → 73 %.
                rating("\(Int((tmdbRating * 10).rounded()))%") {
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.teal)
                }
            }
        }
        .padding(.top, 4)
    }

    private func rating(_ value: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 6) {
            icon()
                .frame(width: 18, height: 18)

            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
