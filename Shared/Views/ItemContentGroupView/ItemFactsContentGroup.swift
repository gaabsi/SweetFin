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
/// - le **plugin** (TMDB + MDBList), pour toute fiche qui a un identifiant TMDB ;
/// - l'**item Jellyfin** en secours, quand le plugin ne répond pas. Moins complet :
///   son import TMDB ne garde pas toujours la réalisation (vérifié : Hunger Games,
///   Toy Story 5 n'y ont que des producteurs), et il n'a pas la note du public.
struct ItemFacts {

    let genres: [String]

    /// Réalisation d'un film, créateurs d'une série.
    let directors: [String]
    let releaseDate: Date?
    let isSeries: Bool

    /// Note TMDB, sur 10.
    let tmdbRating: Double?

    /// Rotten Tomatoes, en pourcentage : la critique, puis le public.
    let rtCritics: Int?
    let rtAudience: Int?

    var hasRatings: Bool {
        tmdbRating != nil || rtCritics != nil || rtAudience != nil
    }

    var isEmpty: Bool {
        genres.isEmpty && directors.isEmpty && releaseDate == nil && !hasRatings
    }

    /// Parametres :
    /// - media (EnhancedFinMedia) : réponse du plugin, demandée avec `detail`
    init(media: EnhancedFinMedia) {
        self.genres = media.genreNames ?? []
        self.directors = media.detail?.directors?.components(separatedBy: ", ").filter(\.isNotEmpty) ?? []
        self.releaseDate = media.detail?.releaseDate.flatMap(EnhancedFinSyntheticItem.day)
        self.isSeries = EnhancedFinMediaType(mediaKey: media.mediaKey) == .tv
        self.tmdbRating = media.voteAverage
        self.rtCritics = media.scores?.rtCritics
        self.rtAudience = media.scores?.rtAudience
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
        // `criticRating` est le Tomatometer, quand le fournisseur de métadonnées
        // l'a rempli. Jellyfin n'a pas d'équivalent pour le public.
        self.rtCritics = item.criticRating.map { Int($0) }
        self.rtAudience = nil
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
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
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

    /// Les notes, réparties sur la largeur. Une note absente n'a pas de place.
    ///
    /// ⚠️ Emojis et non symboles pour la tomate et le popcorn : `popcorn.fill` n'a
    /// qu'un calque (vérifié en le rendant en palette : tout d'une couleur), il ne
    /// peut pas faire un pot rouge et du popcorn jaune. Le symbole `tomato.fresh`
    /// ferait une tomate plate ; l'emoji est celui du site web.
    private var ratings: some View {
        HStack {
            if let tmdbRating = facts.tmdbRating {
                // En pourcentage, comme les deux autres : 7,3 → 73 %.
                rating("\(Int((tmdbRating * 10).rounded()))%") {
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.teal)
                }
            }

            if let rtCritics = facts.rtCritics {
                rating("\(rtCritics)%") {
                    // Sous 60 %, Rotten Tomatoes affiche l'éclaboussure verte.
                    if rtCritics >= 60 {
                        emoji("🍅")
                    } else {
                        Image(.tomatoRotten)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.green)
                    }
                }
            }

            if let rtAudience = facts.rtAudience {
                rating("\(rtAudience)%") {
                    emoji("🍿")
                }
            }
        }
        .padding(.top, 4)
    }

    /// ⚠️ `fixedSize` : un emoji de 16 pt est un peu plus large que le cadre de 18 pt
    /// de `rating`, et un `Text` trop étroit se **tronque** — la tomate sortait rognée.
    private func emoji(_ character: String) -> some View {
        Text(character)
            .font(.system(size: 16))
            .fixedSize()
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
