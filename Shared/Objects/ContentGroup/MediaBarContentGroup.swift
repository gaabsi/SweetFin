//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// iOS uniquement, comme ``MediaBarView`` qu'il enveloppe.
#if os(iOS)

/// Le carrousel en tête de l'Accueil, à la manière du plugin Jellyfin **Media Bar**.
///
/// Ce plugin n'expose aucune API de contenu — il injecte du JavaScript dans le client
/// web, et son carrousel interroge `/Items` comme n'importe qui. On reprend donc sa
/// requête (``RandomItemsLibrary``) et ses réglages, pas une de ses routes.
struct MediaBarContentGroup: ContentGroup {

    let id: String = "media-bar"
    let viewModel: PagingLibraryViewModel<RandomItemsLibrary>

    init() {
        self.viewModel = .init(library: RandomItemsLibrary(), pageSize: RandomItemsLibrary.itemLimit)
    }

    /// Un serveur sans média non vu n'a pas de carrousel — mieux vaut pas de section
    /// qu'un grand vide en haut de l'écran.
    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    func body(with viewModel: PagingLibraryViewModel<RandomItemsLibrary>) -> some View {
        // ⚠️ **Pas de `.ignoreSafeAreaTop` ici.** Le sélecteur cinématique de tvOS
        // l'utilise, mais sur iPhone la zone sûre du haut est occupée par l'encoche :
        // le carrousel y démarrait *derrière* elle, et le haut de l'affiche était
        // rogné. On reste sous la zone sûre.
        MediaBarView(viewModel: viewModel)
    }
}

#endif
