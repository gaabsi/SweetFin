//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// Provider d'`ItemView` pour la fiche d'une personne.
///
/// Même approche que pour les médias hors serveur : on ne réimplémente pas la vue,
/// on remplace la source. `ItemContentGroupProvider` sait déjà présenter une
/// personne — naissance, décès, lieu — il suffit de lui donner un item de type
/// `.person`, auquel on ajoute la filmographie.
///
/// La différence avec la page native tient en une chose : celle-ci ne liste que les
/// rôles dont le serveur possède un fichier. Ici la carrière est entière, et chaque
/// tuile mène à la fiche correspondante, native ou de découverte.
final class ExplorerPersonProvider: ItemContentGroupProvider {

    private let person: BaseItemPerson

    init(person: BaseItemPerson) {
        self.person = person
        super.init(item: EnhancedFinSyntheticItem.makePersonPlaceholder(person))
    }

    /// - Important: `_makeGroups` n'est **pas** appelé ici, contrairement à la fiche
    ///   d'un média. Pour une personne, il délègue à `ItemTypeContentGroupProvider`
    ///   avec l'item pour parent — donc une requête au serveur avec un identifiant
    ///   synthétique qu'il ne connaît pas. Jellyfin renvoie alors des médias
    ///   arbitraires, présentés comme la filmographie de quelqu'un d'autre.
    ///
    ///   Seul le bloc état civil est réutilisé, via `personContentGroups(for:)`.
    override func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
        // ⚠️ **Aucun de ces échecs ne doit rendre d'erreur.** Trois choses peuvent
        // manquer — la session, l'identifiant TMDB, le plugin — et aucune ne rend la
        // personne inintéressante : il reste son état civil et son portrait. Un écran
        // d'erreur, lui, remplaçait la seule page que l'utilisateur pouvait atteindre.
        //
        // L'identifiant TMDB se résout **ici** et pas au moment du tap : pour une
        // personne venue d'une fiche native il demande une requête, et la faire avant
        // de naviguer laissait une à trois secondes sans le moindre retour visuel — le
        // temps qu'il faut pour retaper et empiler un second écran.
        guard let client = userSession?.enhancedFinClient,
              let tmdbID = try? await person.enhancedFinTmdbID(),
              let filmography = try? await client.person(tmdbID)
        else {
            return Self.personContentGroups(for: item)
        }

        // Réassigner et pas seulement transmettre : l'en-tête lit `provider.item`,
        // d'où viennent le portrait et la biographie.
        replaceItem(EnhancedFinSyntheticItem.makePerson(filmography))

        var groups = Self.personContentGroups(for: item)

        if filmography.credits.isNotEmpty {
            groups.append(FilmographyGroup(credits: filmography.credits))
        }

        return groups
    }
}
