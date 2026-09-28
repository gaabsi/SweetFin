//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import SwiftUI

extension BaseItemPerson: Poster {

    struct Environment: WithDefaultValue, WithImageSourceOptions {

        var maxWidth: CGFloat?
        var maxHeight: CGFloat?
        var quality: Int?

        static var `default`: Self {
            .init()
        }
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .portrait
    }

    var subtitle: String? {
        displayRole
    }

    var systemImage: String {
        "person.fill"
    }

    var posterLabel: some View {
        BaseItemDto(person: self).posterLabel
    }

    var posterContextMenu: some View {
        BaseItemDto(person: self).posterContextMenu
    }

    /// SweetFin : remplit le cadre, visage au centre.
    ///
    /// Sans ce `transform`, l'image n'était que `resizable` : invisible tant que le
    /// cadre avait le ratio de la photo (2:3), mais étirée dans un rond du casting,
    /// qui est carré.
    ///
    /// ⚠️ Pas `.top` : ancrée en haut, la photo montre surtout le front et le visage
    /// tombe en bas du rond, menton coupé. Voir `VerticalAlignment.face`.
    @ViewBuilder
    func transform(image: Image, displayType: PosterDisplayType) -> some View {
        Color.clear
            .overlay(alignment: Alignment(horizontal: .center, vertical: .face)) {
                image
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }

    func portraitImageSources(
        environment: Environment
    ) -> [ImageSource] {
        BaseItemDto(person: self)
            .portraitImageSources(
                environment: baseItemDtoEnvironment(from: environment)
            )
    }

    /// SweetFin : les ronds du casting sont carrés, et une personne n'a pas
    /// d'image carrée. Sans ça, le défaut du protocole (`[]`) laissait l'icône de
    /// remplacement ; la photo portrait est recadrée par `transform(image:)`.
    func squareImageSources(
        environment: Environment
    ) -> [ImageSource] {
        portraitImageSources(environment: environment)
    }

    private func baseItemDtoEnvironment(from environment: Environment) -> BaseItemDto.Environment {
        var itemEnvironment = BaseItemDto.Environment.default
        itemEnvironment.maxWidth = environment.maxWidth
        itemEnvironment.maxHeight = environment.maxHeight
        itemEnvironment.quality = environment.quality

        return itemEnvironment
    }
}

private extension VerticalAlignment {

    /// SweetFin : le point à 33 % de la hauteur, repris d'ElegantFin
    /// (`#castCollapsible .cardImageContainer { background-position-y: 33% }`).
    ///
    /// Aligner ce point du cadre sur ce même point de la photo décale celle-ci de
    /// 33 % de ce qui dépasse — exactement le calcul de `background-position` en CSS.
    /// Les photos de casting sont des portraits serrés dont le visage est vers le
    /// tiers haut : à 33 %, il tombe au centre du rond.
    enum FaceAlignment: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions.height * 0.33
        }
    }

    static let face = VerticalAlignment(FaceAlignment.self)
}
