//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// ⚠️ **iOS uniquement.** `PageTabViewStyle` et `PageIndexViewStyle` n'existent pas sur
// tvOS, qui a déjà son propre carrousel piloté par le focus
// (`CinematicSelectionContentGroup`). Sans cette garde, la cible tvOS ne compile plus —
// et son SDK n'étant pas installé ici, l'erreur ne se verrait qu'ailleurs.
#if os(iOS)

/// Le carrousel d'accueil : une affiche pleine largeur, son logo, et de quoi lancer
/// la lecture.
///
/// Réglages repris du plugin Media Bar (`slideshowpure.js`) — ils sont éprouvés, et
/// les réinventer n'aurait rien apporté.
struct MediaBarView: View {

    /// Durée d'une diapo. 12 s : le temps de lire un titre sans s'impatienter.
    private static let rotation: Duration = .seconds(12)

    /// Proportion de l'affiche. Plus haute que l'en-tête d'une fiche (1.6) : ici
    /// l'image *est* le contenu, elle n'introduit pas une page.
    ///
    /// ⚠️ Ne pas remonter au-delà de ~1.3 : la diapo devient alors trop courte pour
    /// loger le logo, le bouton et les points sans que le logo ne vienne percuter le
    /// grand titre « Accueil » de la barre de navigation.
    private static let aspectRatio: CGFloat = 1.1

    @ObservedObject
    var viewModel: PagingLibraryViewModel<RandomItemsLibrary>

    /// Position dans la fenêtre circulaire — **pas** un indice d'item.
    @State
    private var position: Int = 0

    /// Coupe la rotation dès la première interaction : quelqu'un qui balaye a pris la
    /// main, et se faire déplacer sous le doigt est désagréable.
    @State
    private var hasInteracted = false

    /// La dernière position que **nous** avons posée.
    ///
    /// ⚠️ `TabView` n'expose aucun événement de balayage : la seule façon de savoir
    /// qui a changé de diapo est de comparer avec ce qu'on venait de poser soi-même.
    /// Sans ça, la rotation s'arrête d'elle-même dès le premier pas — elle déclenche
    /// son propre `onChange` et croit à un balayage. (Vécu : trois captures à 13 s
    /// d'intervalle, identiques au bit près.)
    @State
    private var lastAutoPosition: Int?

    private var items: [BaseItemDto] {
        viewModel.elements.elements
    }

    /// Nombre de copies de la liste dans la fenêtre. Trois : une avant, une visible,
    /// une après — de quoi balayer dans les deux sens sans jamais atteindre un bord.
    private static let cycles = 3

    private var windowSize: Int { items.count * Self.cycles }

    /// L'item affiché à une position donnée.
    private func item(at position: Int) -> BaseItemDto? {
        guard items.isNotEmpty else { return nil }

        return items[position % items.count]
    }

    var body: some View {
        TabView(selection: $position) {
            ForEach(0 ..< windowSize, id: \.self) { slot in
                if let item = item(at: slot) {
                    MediaBarSlide(item: item, aspectRatio: Self.aspectRatio)
                        .tag(slot)
                }
            }
        }
        // Pastilles natives désactivées : la fenêtre circulaire contient trois fois
        // la liste, elles en afficheraient donc trois fois trop. Les nôtres comptent
        // les items réels.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        // Une carte aux coins arrondis collée aux bords de l'écran ne se lit pas comme
        // une carte : il lui faut de la marge pour que l'arrondi ait un sens. Visible
        // surtout sur un fond coloré, où le bord à bord donnait l'impression que la
        // barre débordait de l'écran.
        .edgePadding(.horizontal)
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 12)
        }
        .onChange(of: position) { _, newValue in
            if newValue != lastAutoPosition { hasInteracted = true }

            recenterIfNeeded(from: newValue)
        }
        .task(id: items.count) {
            await rotate()
        }
        .accessibilityLabel(HomeStrings.mediaBar)
    }

    /// Un point par média réel, celui en cours mis en avant.
    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            HStack(spacing: 8) {
                ForEach(0 ..< items.count, id: \.self) { index in
                    Circle()
                        .fill(.white)
                        .opacity(index == position % items.count ? 1 : 0.35)
                        .frame(width: 7, height: 7)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: position)
            .accessibilityHidden(true)
        }
    }

    /// Ramène la position au cycle du milieu quand elle s'approche d'un bord.
    ///
    /// C'est ce qui rend le défilement **infini** : `TabView` ne boucle pas, on lui
    /// donne donc trois copies de la liste et on le repositionne discrètement d'une
    /// copie dès qu'il entre dans la première ou la dernière. Le saut porte sur un
    /// item identique à l'écran, il est donc invisible.
    ///
    /// ⚠️ **Sans animation**, sinon le saut se voit comme un défilement éclair. Et
    /// ⚠️ **en mémorisant la position posée**, sinon le recentrage passe pour un
    /// balayage et arrête la rotation.
    private func recenterIfNeeded(from position: Int) {
        guard items.count > 1 else { return }

        let middle = items.count
        let recentered: Int

        if position < middle {
            recentered = position + items.count
        } else if position >= middle * 2 {
            recentered = position - items.count
        } else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            select(recentered)
        }
    }

    /// Fait tourner le carrousel tant que l'écran est visible.
    ///
    /// ⚠️ **Dans un `.task` et non un `Timer`** : la tâche est annulée dès que la vue
    /// disparaît, donc le carrousel ne tourne pas en fond ni sur les autres onglets.
    /// Un `Timer.publish` continuerait, à réveiller le processeur pour rien.
    ///
    /// ⚠️ **Rien ne bouge si les animations sont réduites.** Un mouvement automatique
    /// est précisément ce que ce réglage d'accessibilité demande d'éviter.
    private func rotate() async {
        guard items.isNotEmpty else { return }

        // Départ au cycle du milieu : on peut alors balayer vers l'arrière dès la
        // première diapo.
        select(items.count)

        // ⚠️ **Une seule diapo ne tourne pas.** `recenterIfNeeded` sort sur
        // `items.count > 1`, donc rien ne ramènerait la position dans la fenêtre :
        // elle sortirait des trois tags existants et le carrousel deviendrait blanc,
        // sans retour possible. Le cas arrive pour de vrai — `RandomItemsLibrary`
        // filtre sur non-vu, logo *et* synopsis.
        guard items.count > 1 else { return }

        guard !UIAccessibility.isReduceMotionEnabled else { return }

        while !Task.isCancelled, !hasInteracted {
            try? await Task.sleep(for: Self.rotation)

            guard !Task.isCancelled, !hasInteracted else { return }

            withAnimation {
                select(position + 1)
            }
        }
    }

    /// Change de diapo **de notre fait**. L'ordre compte : mémoriser d'abord, poser
    /// ensuite, sinon `onChange` nous prend pour l'utilisateur.
    private func select(_ newPosition: Int) {
        lastAutoPosition = newPosition
        position = newPosition
    }
}

// MARK: - Une diapo

private struct MediaBarSlide: View {

    @Router
    private var router

    @Namespace
    private var namespace

    let item: BaseItemDto
    let aspectRatio: CGFloat

    var body: some View {
        // ⚠️ **Le backdrop ne doit PAS dicter la taille de la diapo.** En `.fill` il
        // est plus large que l'écran ; posé dans un `ZStack`, c'est lui qui impose sa
        // largeur au conteneur, et le contenu se retrouve mis en page contre une
        // largeur qui dépasse — les logos larges sortent alors de l'écran des deux
        // côtés, malgré `edgePadding` et `clipped()`, qui ne masquent que l'image.
        //
        // D'où un `Color.clear` au bon format comme seul élément dimensionnant : le
        // fond passe en `.background`, le contenu en `.overlay`, et ni l'un ni l'autre
        // n'influence plus la taille.
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background {
                backdrop
            }
            // Coins arrondis comme les tuiles : à angles vifs, le carrousel était le
            // seul élément carré d'un écran qui ne l'est nulle part ailleurs.
            // `clipShape` remplace `clipped()`, qui rognait au rectangle.
            .clipShape(.rect(cornerRadius: 20))
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    logo

                    MediaBarPlayButton(item: item)
                        .frame(maxWidth: 220)
                }
                .edgePadding(.horizontal)
                .padding(.bottom, 40)
            }
            .contentShape(.rect)
            .onTapGesture {
                router.route(to: .item(item: item), in: namespace)
            }
            .colorScheme(.dark)
    }

    /// L'image de fond, assombrie vers le bas pour que le logo et le bouton restent
    /// lisibles quelle que soit l'affiche.
    ///
    /// ⚠️ **Le voile doit couvrir la bande du logo, pas seulement le bas.** Beaucoup
    /// de logos sont en lettres **noires** — « NOUS FINIRONS ENSEMBLE » — et se
    /// perdent sur une affiche claire si l'assombrissement ne commence qu'en dessous
    /// d'eux. C'est le cas qu'on rate en ne testant que des logos blancs.
    @ViewBuilder
    private var backdrop: some View {
        ImageView(
            item.imageSource(
                .backdrop,
                environment: ImageSourceOptions(maxWidth: 1320)
            )
        )
        .failure {
            Color.secondarySystemFill
        }
        .aspectRatio(contentMode: .fill)
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.25), location: 0.3),
                    .init(color: .black.opacity(0.6), location: 0.55),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    /// Le logo du média.
    ///
    /// Pas de repli sur le titre : ``RandomItemsLibrary`` filtre sur
    /// `imageTypes=Logo,Backdrop`, donc un média sans logo n'arrive jamais ici. Le
    /// `failure` ne couvre qu'un échec de téléchargement.
    @ViewBuilder
    private var logo: some View {
        ImageView(
            item.imageSource(
                .logo,
                environment: ImageSourceOptions(maxHeight: 90)
            )
        )
        // ⚠️ **Redimensionner l'image explicitement est indispensable.** `ImageView`
        // ne porte pas de ratio intrinsèque : un `.aspectRatio(contentMode: .fit)`
        // posé par-dessus n'a rien sur quoi s'appuyer, le cadre ne contraint alors
        // que la hauteur, et un logo large — « THE BIG SHORT, LE CASSE DU SIÈCLE » —
        // sort de l'écran des deux côtés. Un logo presque carré comme Shrek passait,
        // ce qui rend le défaut facile à manquer.
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
                .font(.title)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: 80)
        .accessibilityLabel(item.displayTitle)
        .accessibilityRemoveTraits(.isImage)
    }
}

// MARK: - Le bouton Lire

/// Lance la lecture depuis le carrousel.
///
/// ⚠️ **La cible n'est pas l'item affiché.** Pour une série, il faut trouver l'épisode
/// à lire — épisode suivant, sinon reprise en cours, sinon le premier disponible. Cette
/// logique vit dans `ItemContentGroupProvider`, en privé. On l'**appelle** plutôt que
/// de la recopier : une copie ne produirait aucune erreur de compilation en divergeant,
/// juste un bouton qui lance le mauvais épisode.
///
/// ⚠️ **Résolu au tap, pas à chaque diapo.** Précharger demanderait une requête toutes
/// les douze secondes, pour une lecture qu'on ne lancera presque jamais.
private struct MediaBarPlayButton: View {

    @Default(.accentColor)
    private var accentColor

    @Router
    private var router

    @State
    private var isResolving = false

    let item: BaseItemDto

    var body: some View {
        Button {
            guard !isResolving else { return }
            resolveAndPlay()
        } label: {
            HStack(spacing: 8) {
                if isResolving {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "play.fill")
                }

                Text(L10n.play)
            }
            .font(.callout)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(accentColor, in: .capsule)
            .foregroundStyle(accentColor.overlayColor)
        }
        .buttonStyle(.plain)
        .disabled(isResolving)
    }

    private func resolveAndPlay() {
        isResolving = true

        Task { @MainActor in
            defer { isResolving = false }

            let provider = ItemContentGroupProvider(item: item)

            // `makeGroups` fait tout le travail : récupère l'item complet, résout
            // l'épisode à lire, et publie `mediaPlayerItemProvider`. On jette les
            // groupes, pas le reste.
            _ = try? await provider.makeGroups(environment: .init())

            guard let playbackProvider = provider.mediaPlayerItemProvider else {
                // Rien de lisible — un média sans fichier, par exemple. Ouvrir la
                // fiche vaut mieux qu'un bouton qui ne fait rien.
                router.route(to: .item(item: item))
                return
            }

            let queue: (any MediaPlayerQueue)? = playbackProvider.item.type == .episode
                ? EpisodeMediaPlayerQueue(episode: playbackProvider.item)
                : nil

            router.route(to: .videoPlayer(provider: playbackProvider, queue: queue))
        }
    }
}

#endif
