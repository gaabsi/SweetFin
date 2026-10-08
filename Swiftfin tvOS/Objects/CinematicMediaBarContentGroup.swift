//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// SweetFin : la media bar de tvOS, en vitrine.
///
/// Même contenu que sur iOS (``RandomItemsLibrary`` : le tirage de films et séries non
/// vus, avec logo et fond), un média à la fois dans une carte bordée : fond, logo,
/// synopsis, « Lire » et « Infos ». La media bar iOS ne se porte pas
/// (`PageTabViewStyle` n'existe pas ici).
///
/// ❌ D'abord le `CinematicItemSelector` d'upstream avec ce tirage : son rail de huit
/// affiches sous le fond laissait croire que le serveur ne contenait que ça.
/// ❌ Puis une vitrine bord à bord : sans cadre, elle ne se lisait pas comme une section.
struct CinematicMediaBarContentGroup: ContentGroup {

    let id: String = "media-bar"
    let viewModel: PagingLibraryViewModel<RandomItemsLibrary>

    init() {
        self.viewModel = .init(library: RandomItemsLibrary(), pageSize: RandomItemsLibrary.itemLimit)
    }

    /// Même règle que sur iOS : pas de média, pas de section.
    var _shouldBeResolved: Bool {
        viewModel.elements.isNotEmpty
    }

    func body(with viewModel: PagingLibraryViewModel<RandomItemsLibrary>) -> some View {
        MediaBarShowcase(viewModel: viewModel)
    }
}

private struct MediaBarShowcase: View {

    /// Les éléments focalisables de la vitrine, sur deux niveaux :
    /// - `card` : la carte elle-même, focus à l'arrivée. ← / → y changent de média,
    ///   ↓ descend sur les boutons, un clic ouvre la fiche ;
    /// - `play`, `info` : les boutons. ← / → passent de l'un à l'autre.
    ///
    /// ⚠️ Les autres cas sont des **butées** invisibles (`FocusStop`) : sans elles, ←
    /// sortait de la vitrine et ouvrait le menu latéral des onglets. `onMoveCommand`
    /// voit la flèche mais ne retient pas le focus. Le focus s'arrête sur la butée, et
    /// `redirect(from:to:)` le renvoie où il doit aller.
    private enum Focus: Hashable {
        case card
        case play
        case info
        /// À gauche et à droite de la carte : changent de média, **si** on vient de la
        /// carte (en remontant depuis « Lire », on peut y tomber aussi).
        case previous
        case next
        /// À gauche et à droite des boutons : ne font que retenir le focus.
        case rowStart
        case rowEnd
    }

    /// Même durée que la media bar iOS.
    private static let rotation: Duration = .seconds(15)

    private static let cornerRadius: CGFloat = 36

    @Router
    private var router

    @ObservedObject
    var viewModel: PagingLibraryViewModel<RandomItemsLibrary>

    /// Indice du média affiché. En `@State` : la vue reste en vie sous une fiche
    /// poussée, on retrouve donc le même média au retour.
    @State
    private var index = 0

    /// Coupe la rotation dès la première action, comme sur iOS : quelqu'un qui
    /// parcourt a pris la main.
    @State
    private var hasInteracted = false

    @FocusState
    private var focus: Focus?

    private var items: [BaseItemDto] {
        viewModel.elements.elements
    }

    private var item: BaseItemDto? {
        guard items.isNotEmpty else { return nil }
        return items[index % items.count]
    }

    var body: some View {
        CinematicContentGroupContainer {
            ZStack(alignment: .bottomLeading) {
                backdrop

                if let item {
                    VStack(alignment: .leading, spacing: 32) {
                        details(for: item)

                        buttons(for: item)
                    }
                    .padding(60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                pageIndicator
                    .padding(60)
            }
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .overlay {
                // Bordure fixe : ❌ allumée au focus de la carte, jugée de trop.
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 2)
            }
            // Sous la pastille d'onglet (en haut à gauche), et aux marges des rails.
            .padding(.top, 120)
            .edgePadding(.horizontal)
        }
        .focusSection()
        .defaultFocus($focus, .card)
        .onChange(of: focus) { oldValue, newValue in
            redirect(from: oldValue, to: newValue)
        }
        .task(id: items.count) {
            await rotate()
        }
        .preference(
            key: ContentGroupCustomizationKey.self,
            value: .ignoreSafeAreaTop
        )
    }

    // MARK: - Fond

    /// Le fond du média, en fondu d'un média à l'autre, assombri en bas à gauche : là
    /// où sont le texte et les boutons.
    private var backdrop: some View {
        FadeContentTransitionView(item: item) { item in
            ImageView(
                item?.imageSource(
                    .backdrop,
                    environment: ImageSourceOptions(maxWidth: 1920)
                ) ?? ImageSource()
            )
            .failure {
                Color.secondarySystemFill
            }
            .aspectRatio(contentMode: .fill)
        }
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.55), location: 0.6),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: - Focus

    /// Ce qu'on fait quand le focus se pose sur une butée (voir ``Focus``).
    private func redirect(from oldValue: Focus?, to newValue: Focus?) {
        switch newValue {
        case .previous, .next:
            if oldValue == .card {
                step(by: newValue == .previous ? -1 : 1)
            }
            focus = .card
        case .rowStart:
            focus = .play
        case .rowEnd:
            focus = .info
        default:
            break
        }
    }

    // MARK: - Carte

    /// Logo et synopsis, focalisables : c'est « la carte » (voir ``Focus``), entre
    /// ses deux butées.
    private func details(for item: BaseItemDto) -> some View {
        HStack(spacing: 0) {
            FocusStop()
                .focused($focus, equals: .previous)

            ItemDetails(item: item)
                // ⚠️ Nouvelle identité à chaque média : `ImageView` garde ses sources
                // en `@State`, le logo resterait le précédent.
                .id(item.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusable()
                .focused($focus, equals: .card)
                .onTapGesture {
                    router.route(to: .item(item: item))
                }

            FocusStop()
                .focused($focus, equals: .next)
        }
    }

    // MARK: - Boutons

    /// « Lire » et « Infos », entre leurs deux butées (voir ``Focus``).
    private func buttons(for item: BaseItemDto) -> some View {
        HStack(spacing: 24) {
            FocusStop()
                .focused($focus, equals: .rowStart)

            Button {
                router.play(item)
            } label: {
                Label(L10n.play, systemImage: "play.fill")
            }
            .focused($focus, equals: .play)

            Button {
                router.route(to: .item(item: item))
            } label: {
                Label(HomeStrings.info, systemImage: "info.circle")
            }
            .focused($focus, equals: .info)

            FocusStop()
                .focused($focus, equals: .rowEnd)
        }
        // Les butées ne décalent pas les boutons : ils restent alignés sur le logo.
        .padding(.leading, -24)
    }

    /// Un point par média, celui en cours mis en avant.
    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            HStack(spacing: 12) {
                ForEach(0 ..< items.count, id: \.self) { position in
                    Circle()
                        .fill(.white)
                        .opacity(position == index % items.count ? 1 : 0.35)
                        .frame(width: 12, height: 12)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: index)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Défilement

    /// Passe au média voisin, à la main.
    private func step(by offset: Int) {
        guard items.count > 1 else { return }

        hasInteracted = true
        withAnimation {
            index = (index + offset + items.count) % items.count
        }
    }

    /// Rotation automatique tant que personne n'a pris la main. Même règles que la
    /// media bar iOS : dans un `.task` (s'arrête quand l'Accueil disparaît), rien si
    /// les animations sont réduites.
    private func rotate() async {
        guard items.count > 1, !UIAccessibility.isReduceMotionEnabled else { return }

        while !Task.isCancelled, !hasInteracted {
            try? await Task.sleep(for: Self.rotation)

            guard !Task.isCancelled, !hasInteracted else { return }

            withAnimation {
                index = (index + 1) % items.count
            }
        }
    }
}

/// Une butée de focus invisible, voir `MediaBarShowcase.Focus`.
private struct FocusStop: View {

    var body: some View {
        Color.clear
            .frame(width: 1, height: 60)
            .focusable()
            .accessibilityHidden(true)
    }
}

/// Logo et synopsis du média affiché.
private struct ItemDetails: View {

    let item: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Pas de repli sur le titre en temps normal : `RandomItemsLibrary` ne tire
            // que des médias qui ont un logo. Le `failure` couvre un échec réseau.
            ImageView(
                item.imageSource(
                    .logo,
                    environment: ImageSourceOptions(maxWidth: 600, maxHeight: 180)
                )
            )
            .image { (image: UIImage) in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .placeholder { _ in
                EmptyView()
            }
            .failure {
                Text(item.displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: 600, maxHeight: 180, alignment: .bottomLeading)
            .accessibilityLabel(item.displayTitle)

            if let overview = item.overview {
                // Discret et étroit, en retrait du logo : ❌ plus large, en `body`
                // blanc, il prenait le pas sur l'image.
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }
}
