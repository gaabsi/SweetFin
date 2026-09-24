//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// EnhancedFin : l'écran de pause, sur le modèle du web Jellyfin (ElegantFin).
///
/// Présenté par `EnhancedFinPlaybackControls` après quelques secondes de pause. Fond
/// assombri, logo, année et durée, synopsis, puis la progression :
/// « 0:26 / 22:31 • 2 % regardé • Se termine à 22:00 ». Un tap n'importe où, ou `×`,
/// le ferme.
///
/// Pour un épisode, fond et logo sont ceux de la **série** : un épisode n'a
/// généralement ni l'un ni l'autre.
struct EnhancedFinPauseScreen: View {

    @Environment(\.safeAreaInsets)
    private var safeAreaInsets

    @EnvironmentObject
    private var manager: MediaPlayerManager

    let onClose: () -> Void

    private var item: BaseItemDto {
        manager.item
    }

    private var runtime: Duration {
        item.runtime ?? .zero
    }

    /// Part regardée, entre 0 et 1.
    private var progress: Double {
        guard runtime > .zero else { return 0 }

        return clamp(manager.seconds / runtime, min: 0, max: 1)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Button(L10n.close, systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                }
                .padding(.top, safeAreaInsets.top + EdgeInsets.edgePadding)
                .padding(.trailing, safeAreaInsets.trailing + EdgeInsets.edgePadding)
        }
        .foregroundStyle(.white)
        .background {
            backdrop
        }
        .contentShape(.rect)
        .onTapGesture(perform: onClose)
        .colorScheme(.dark)
    }

    // MARK: - Contenu

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            logo

            HStack(spacing: 24) {
                if let year = item.productionYear {
                    Text(String(year))
                }

                if runtime > .zero {
                    Text(runtime, format: .hourMinuteAbbreviated)
                }
            }
            .font(.title3)

            if let overview = item.overview {
                Text(overview)
                    .font(.body)
                    .lineLimit(6)
            }

            ProgressView(value: progress)
                .tint(.white)

            progressDetails
        }
        // Une colonne, comme sur le web : le synopsis ne court pas sur toute la largeur.
        .frame(maxWidth: 480, alignment: .leading)
        .padding(.leading, safeAreaInsets.leading + EdgeInsets.edgePadding * 2)
        .padding(.trailing, EdgeInsets.edgePadding)
    }

    /// « 0:26 / 22:31 • 2 % regardé • Se termine à 22:00 ».
    ///
    /// L'heure de fin = maintenant + temps restant (à la vitesse de lecture). Actualisée
    /// chaque minute : en pause, elle avance avec l'horloge.
    private var progressDetails: some View {
        TimelineView(.everyMinute) { context in
            let remaining = (runtime - manager.seconds) / Double(max(manager.rate, 0.1))
            let endDate = context.date.addingTimeInterval(max(remaining, .zero).seconds)

            DotHStack {
                Text("\(manager.seconds, format: .runtime) / \(runtime, format: .runtime)")
                Text(PlayerStrings.watched(percent: Int(progress * 100)))
                Text("\(PlayerStrings.endsAt) \(endDate, format: .dateTime.hour().minute())")
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Images

    /// Le logo, ou le titre s'il n'y en a pas.
    ///
    /// ⚠️ Redimensionné explicitement, comme dans `MediaBarView` : `ImageView` n'a pas
    /// de ratio propre, et un logo large sortirait du cadre.
    private var logo: some View {
        ImageView(Self.sources(of: item, .logo, parentID: item.parentLogoItemID, parentTag: item.parentLogoImageTag))
            .image { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .placeholder { _ in
                EmptyView()
            }
            .failure {
                Text(item.seriesName ?? item.displayTitle)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
            }
            .frame(maxWidth: 320, maxHeight: 90, alignment: .leading)
            .accessibilityLabel(item.seriesName ?? item.displayTitle)
    }

    private var backdrop: some View {
        ImageView(
            Self.sources(
                of: item,
                .backdrop,
                parentID: item.parentBackdropItemID,
                parentTag: item.parentBackdropImageTags?.first
            )
        )
        .image { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .failure {
            Color.black
        }
        .overlay {
            // Plus sombre à gauche, sous le texte, comme le web.
            LinearGradient(
                colors: [.black.opacity(0.85), .black.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Les sources d'une image : celle du parent (la série d'un épisode) d'abord, puis
    /// celle de l'item. `ImageView` passe à la suivante si une source échoue.
    ///
    /// Parametres :
    /// - item (BaseItemDto) : l'item en lecture
    /// - type (ImageType) : logo ou fond
    /// - parentID (String?) : l'item parent qui porte l'image
    /// - parentTag (String?) : son tag d'image
    ///
    /// Output :
    /// - sources ([ImageSource]) : les sources exploitables, sans URL vide
    private static func sources(
        of item: BaseItemDto,
        _ type: ImageType,
        parentID: String?,
        parentTag: String?
    ) -> [ImageSource] {
        // En points (×3 à l'écran) : le logo à sa largeur affichée, le fond comme la
        // media bar, pour profiter de la même image en cache.
        let options = ImageSourceOptions(maxWidth: type == .logo ? 320 : 1320)

        return [
            item.imageSource(itemID: parentID, type, tag: parentTag, environment: options),
            item.imageSource(type, environment: options),
        ]
        .compacted(using: \.url)
    }
}
