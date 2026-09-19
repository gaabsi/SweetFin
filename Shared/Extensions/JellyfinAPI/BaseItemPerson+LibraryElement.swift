//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Fork : `FactoryKit` sert à vérifier que le serveur expose bien EnhancedFin
// avant de dérouter le tap vers lui.
import FactoryKit
import JellyfinAPI
import SwiftUI

extension BaseItemPerson: LibraryElement {

    static var supportedLibraryStyleOptions: LibraryStyleOptions {
        BaseItemKind.libraryStyleOptions(for: [.person])
    }

    /// Fork : ouvre la filmographie complète plutôt que les seuls rôles présents
    /// sur le serveur, ce à quoi se limite la page native.
    ///
    /// La navigation part **immédiatement**. La résolution de l'identifiant TMDB,
    /// qui demande une requête pour une personne venue d'une fiche native, a lieu
    /// dans `ExplorerPersonProvider` : la faire ici laissait une à trois secondes
    /// sans aucun retour visuel, pendant lesquelles un second tap empilait un
    /// second écran.
    func libraryDidSelectElement(
        router: Router.Wrapper,
        in namespace: Namespace.ID
    ) {
        // Fork : sur un serveur sans le plugin, la page personne native reste la
        // seule destination possible — il n'y a pas de filmographie à demander.
        guard Container.shared.currentUserSession()?.enhancedFinClient != nil else {
            BaseItemDto(person: self)
                .libraryDidSelectElement(router: router, in: namespace)
            return
        }

        // Fork : destination EnhancedFin.
        router.route(to: .explorerPerson(person: self), in: namespace)
    }

    @ViewBuilder
    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        BaseItemDto(person: self)
            .makeBody(
                libraryStyle: libraryStyle,
                action: action
            )
    }
}
