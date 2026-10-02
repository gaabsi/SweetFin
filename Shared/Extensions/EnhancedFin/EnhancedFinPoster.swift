//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

// Conformances `Poster` des items EnhancedFin, pour qu'ils s'affichent dans les
// composants existants (`PosterHStack`, `PosterButton`) comme n'importe quel item
// Jellyfin.
//
// Particularité : les affiches viennent de TMDB par URL absolue, pas du serveur
// Jellyfin — même situation que `RemoteSearchResult`, dont ces extensions
// reprennent le patron.

// MARK: - Protocole commun

/// Ce que les quatre types d'items EnhancedFin ont en commun pour s'afficher.
///
/// Les quatre conformances `Poster` étaient identiques à deux ou trois lignes
/// près : même libellé, même sous-titre, mêmes sources d'images, même pastille de
/// note. Les regrouper ici laisse à chaque type ce qui le distingue vraiment.
///
/// Hérite d'``EnhancedFinLibraryLinkable`` : un item affichable est aussi un item
/// qu'on peut ouvrir, sur le serveur ou non. Les vues n'ont donc qu'une contrainte
/// à porter.
protocol EnhancedFinPosterItem: Poster, Displayable, EnhancedFinLibraryLinkable {

    var year: Int? { get }
    var posterUrl: String? { get }

    /// Image large, quand la route en renvoie une. Absente des notes et des
    /// « à noter », dont les tuiles sont toujours en portrait.
    var backdropUrl: String? { get }

    /// Ma note, pour la pastille posée sur l'affiche. `nil` = pas de pastille.
    var posterRatingScore: Int? { get }
}

extension EnhancedFinPosterItem {

    var backdropUrl: String? { nil }

    var posterRatingScore: Int? { nil }

    var displayTitle: String { title }

    var subtitle: String? { year.map(String.init) }

    /// Déduit de la clé, la seule donnée présente sur **toutes** les routes.
    var systemImage: String {
        EnhancedFinMediaType(mediaKey: mediaKey)?.systemImage ?? "film"
    }

    var preferredPosterDisplayType: PosterDisplayType { .portrait }

    func portraitImageSources(environment: Empty) -> [ImageSource] {
        [imageSource(posterUrl, serverType: .primary)]
    }

    func landscapeImageSources(environment: Empty) -> [ImageSource] {
        [imageSource(backdropUrl, serverType: .backdrop)]
    }

    /// L'affiche TMDB, ou à défaut celle du serveur.
    ///
    /// Un média **vu sur le serveur mais jamais noté** n'est pas dans le référentiel
    /// du plugin : il n'a donc pas d'URL TMDB, et un `GET` ne peuple rien pour lui en
    /// obtenir une. Mais le fichier est là, donc Jellyfin a son image — c'est
    /// exactement le repli du front web, qui préfère la carte Jellyfin locale quand
    /// l'item est en bibliothèque.
    ///
    /// L'item reconstruit n'a pas de tag d'image ; Jellyfin sert l'image sans lui, on
    /// perd seulement l'invalidation de cache.
    ///
    /// Parametres :
    /// - tmdbUrl (String?) : URL absolue renvoyée par le plugin, si elle existe
    /// - serverType (ImageType) : type d'image à demander au serveur à défaut
    ///
    /// Output :
    /// - source (ImageSource) : vide si le média n'a ni l'une ni l'autre
    private func imageSource(_ tmdbUrl: String?, serverType: ImageType) -> ImageSource {
        if let url = URL.enhancedFinImage(tmdbUrl) {
            return ImageSource(url: url)
        }

        // ⚠️ `maxWidth` en points (×3 à l'écran) : sans lui, le serveur servait l'image
        // originale pour chaque tuile. Assez large pour les grilles, pas plus.
        let options = ImageSourceOptions(maxWidth: serverType == .primary ? 200 : 400)

        return jellyfinItem?.imageSource(serverType, environment: options) ?? ImageSource()
    }

    @MainActor
    var posterLabel: EnhancedFinPosterLabel {
        EnhancedFinPosterLabel(title: displayTitle, subtitle: subtitle)
    }

    @MainActor
    func posterOverlay(for displayType: PosterDisplayType) -> EnhancedFinRatingBadge {
        EnhancedFinRatingBadge(score: posterRatingScore)
    }
}

// MARK: - Conformances

extension EnhancedFinRating: EnhancedFinPosterItem {

    var posterRatingScore: Int? { score }
}

// Le sous-titre est l'**année**, comme partout ailleurs dans l'Explorer — et non le
// nombre d'épisodes vus, qui répondait à une question que personne ne se pose devant
// une tuile. L'implémentation par défaut du protocole suffit donc.
extension EnhancedFinPendingRating: EnhancedFinPosterItem {}

extension EnhancedFinWatchlistItem: EnhancedFinPosterItem {

    var posterRatingScore: Int? { rating }
}

extension EnhancedFinSearchItem: EnhancedFinPosterItem {

    var posterRatingScore: Int? { me.rating }
}

// Une sortie de calendrier n'a pas d'année propre — c'est la date du jour qui la
// porte, et elle est déjà donnée par la case. La conformance sert surtout à obtenir
// `syntheticItem` et la règle d'ouverture de fiche sans les réécrire.
extension EnhancedFinRelease: EnhancedFinPosterItem {

    var year: Int? { nil }
}

// Rien à surcharger : `/me/follows` rend `inLibrary` et `jellyfinId` comme les
// autres routes de liste, et le reste vient des valeurs par défaut du protocole.
extension EnhancedFinFollow: EnhancedFinPosterItem {}

// MARK: - Navigation

/// Ce qu'un item EnhancedFin sait de sa présence sur le serveur.
///
/// Un item absent de la bibliothèque n'a pas de fiche Jellyfin à ouvrir : il
/// n'existe que dans le référentiel ou sur TMDB.
protocol EnhancedFinLibraryLinkable {

    var mediaKey: String { get }
    var title: String { get }
    var jellyfinId: String? { get }

    /// Item fabriqué pour rendre la fiche quand le média n'est pas sur le serveur.
    var syntheticItem: BaseItemDto { get }
}

extension EnhancedFinLibraryLinkable {

    /// La fiche Jellyfin correspondante, ou `nil` si le média n'est pas sur ce
    /// serveur.
    ///
    /// Seul l'identifiant est renseigné : `ItemView` recharge l'item complet.
    /// C'est le même raccourci que `TabItem.item(id:displayTitle:)`.
    var jellyfinItem: BaseItemDto? {
        guard let jellyfinId else { return nil }
        return BaseItemDto(id: jellyfinId, name: title)
    }
}

// MARK: - Libellé

/// Titre et sous-titre sous une affiche.
///
/// Reprend la hiérarchie visuelle du libellé natif d'upstream (`footnote` pour
/// le titre, `caption` secondaire pour le détail), que l'on ne peut pas réutiliser
/// directement : il est `private` dans l'extension `BaseItemDto`.
///
/// `reservesSpace` garde une hauteur constante d'une tuile à l'autre, sans quoi
/// une grille de titres courts et longs part en escalier.
///
/// Centré, contrairement au libellé natif d'upstream : c'est ce que fait le front
/// web (`cardTextCentered`), et l'Explorer en est le miroir.
struct EnhancedFinPosterLabel: View {

    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(subtitle == nil ? 2 : 1, reservesSpace: true)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pastille de note posée sur l'affiche.
///
/// Couleurs reprises de `.jr-card-badge` du front web : rouge, ambre, vert. Le
/// symbole est en revanche un cœur — barré, plein, plein qui bat — plutôt qu'un
/// pouce. C'est ce qui rend la note lisible d'un coup d'œil, sans ouvrir la fiche.
///
/// Rien n'est affiché pour un média non noté.
struct EnhancedFinRatingBadge: View {

    let score: Int?

    private var rating: EnhancedFinScore? {
        score.flatMap(EnhancedFinScore.init(rawValue:))
    }

    var body: some View {
        if let rating {
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Image(systemName: rating.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(rating.color, in: .circle)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
            }
            .padding(6)
        }
    }
}
