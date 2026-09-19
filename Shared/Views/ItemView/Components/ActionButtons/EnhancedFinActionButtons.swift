//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// Boutons EnhancedFin de la barre d'actions : noter, watchlist, suivre.
//
// Ils apparaissent sur toute fiche dont le média a une clé EnhancedFin, qu'il soit
// sur le serveur ou non : noter un film qu'on possède a autant de sens que d'en
// mettre un en watchlist avant de l'avoir.

extension ItemActionButtons {

    /// Aiguillage depuis `ItemActionButtons.view(for:)`.
    ///
    /// Cette indirection est nécessaire : `view(for:)` est statique et ne connaît
    /// que le type de bouton. La clé du média vit sur le provider, injecté par
    /// l'environnement — il faut donc une vue pour le lire avant de pouvoir la
    /// transmettre.
    struct EnhancedFinButton: View {

        @EnvironmentObject
        private var provider: ItemContentGroupProvider

        let button: ItemActionButton

        var body: some View {
            // `isAvailable` a déjà filtré les items sans clé ; ce garde ne couvre
            // que le cas où la fiche change d'item sous la vue.
            if let mediaKey = provider.item.enhancedFinMediaKey {
                let state = EnhancedFinItemStateStore.shared.state(for: mediaKey)

                switch button {
                case .enhancedFinRating:
                    RatingButton(state: state)
                case .enhancedFinWatchlist:
                    WatchlistButton(state: state)
                case .enhancedFinFollow:
                    FollowButton(state: state)
                default:
                    EmptyView()
                }
            }
        }
    }

    /// Note : les trois valeurs du référentiel, plus le retrait.
    ///
    /// Un menu et non un interrupteur — il y a trois valeurs distinctes, qu'un
    /// bouton à deux états ne saurait pas exprimer.
    struct RatingButton: View {

        @ObservedObject
        var state: EnhancedFinItemState

        var body: some View {
            Menu {
                // Pas d'entrée « retirer » : reposer la note déjà en place la retire,
                // en poser une autre la remplace. Un seul geste, deux effets.
                ForEach(EnhancedFinScore.allCases, id: \.self) { score in
                    Button {
                        // « J'adore ! » mérite d'être plus franc sous le doigt que
                        // les deux autres : c'est le geste qu'on pose rarement.
                        if score == .loved, score != state.rating {
                            UIDevice.impact(.heavy)
                        }
                        Task { await state.setRating(score == state.rating ? nil : score) }
                    } label: {
                        Label(score.displayTitle, systemImage: score.systemImage)
                    }
                }

            } label: {
                Label(
                    ExplorerStrings.rate,
                    systemImage: state.rating?.systemImage ?? ItemActionButton.enhancedFinRating.secondarySystemImage
                )
            }
            .isSelected(state.rating != nil)
            // Repose le style au plus près du Label pour l'emporter sur celui que
            // la barre applique au-dessus : le bouton prend la couleur de la note
            // donnée, et non une teinte fixe.
            .labelStyle(ItemActionButtonLabelStyle(activeColor: state.rating?.color))
            .task { await state.load() }
        }
    }

    /// Watchlist : interrupteur simple.
    struct WatchlistButton: View {

        @ObservedObject
        var state: EnhancedFinItemState

        var body: some View {
            Button(
                state.isInWatchlist ? ExplorerStrings.removeFromWatchlist : ExplorerStrings.addToWatchlist,
                systemImage: state.isInWatchlist
                    ? ItemActionButton.enhancedFinWatchlist.systemImage
                    : ItemActionButton.enhancedFinWatchlist.secondarySystemImage
            ) {
                Task { await state.toggleWatchlist() }
            }
            .isSelected(state.isInWatchlist)
            .task { await state.load() }
        }
    }

    /// Suivi : les prochaines sorties de la série entrent au calendrier.
    struct FollowButton: View {

        @ObservedObject
        var state: EnhancedFinItemState

        var body: some View {
            Button(
                state.isFollowing ? ExplorerStrings.unfollow : ExplorerStrings.follow,
                systemImage: state.isFollowing
                    ? ItemActionButton.enhancedFinFollow.systemImage
                    : ItemActionButton.enhancedFinFollow.secondarySystemImage
            ) {
                Task { await state.toggleFollow() }
            }
            .isSelected(state.isFollowing)
            .task { await state.load() }
        }
    }
}

extension EnhancedFinScore: Displayable {

    var displayTitle: String {
        switch self {
        case .disliked: ExplorerStrings.disliked
        case .liked: ExplorerStrings.liked
        case .loved: ExplorerStrings.loved
        }
    }

    /// - Note: SF Symbols n'a **pas** de cœur brisé (`brokenheart` n'existe pas).
    ///   `heart.slash.fill`, le cœur barré, est le plus lisible pour « pas pour moi ».
    ///   Un vrai cœur brisé demanderait un `.symbolset` maison.
    var systemImage: String {
        switch self {
        case .disliked: "heart.slash.fill"
        case .liked, .loved: "heart.fill"
        }
    }

    /// Couleur du cœur, partagée entre le menu, la pastille des tuiles et l'état
    /// actif du bouton — une note doit se reconnaître à la même couleur partout.
    var color: Color {
        switch self {
        case .disliked: Color(red: 229 / 255, green: 9 / 255, blue: 20 / 255)
        case .liked: Color(red: 240 / 255, green: 160 / 255, blue: 0)
        case .loved: Color(red: 0, green: 160 / 255, blue: 80 / 255)
        }
    }
}
