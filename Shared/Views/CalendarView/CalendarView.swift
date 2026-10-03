//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Onglet Calendrier — les sorties des médias suivis, à leur date.
///
/// Grille de 16 jours (4 × 4) démarrant un lundi, comme le front web en affichage
/// mobile. Une case montre au plus deux titres puis « +N » ; le tap ouvre la feuille
/// du jour, qui laisse la grille visible.
struct CalendarView: View {

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    /// Les mesures de la grille : iPhone, ou grand écran (iPad).
    private var metrics: CalendarDayCell.Metrics {
        horizontalSizeClass == .regular ? .regular : .compact
    }

    @StateObject
    private var viewModel = CalendarViewModel()

    /// Jour dont la feuille est ouverte. `nil` = aucune.
    @State
    private var selectedDay: CalendarDaySelection?

    /// Repliée à l'ouverture : le calendrier est le sujet de l'écran, les suivis en
    /// sont la gestion — on n'y va que quand on le décide.
    @State
    private var showsFollows = false

    var body: some View {
        // `ScrollView` et non `VStack` : la section des suivis, dépliée, dépasse
        // l'écran. La feuille du jour n'entre pas en conflit — elle porte son propre
        // geste de fermeture.
        ScrollView {
            VStack(spacing: 0) {
                header

                content

                if viewModel.follows.isNotEmpty {
                    followsSection
                }
            }
        }
        .navigationTitle(CalendarStrings.calendar)
        .hidesNavigationTitle()
        .task(id: viewModel.start) {
            await viewModel.load()
        }
        .sheet(item: $selectedDay) { selection in
            CalendarDaySheet(day: selection.date, entries: viewModel.entries(on: selection.date))
        }
    }

    // MARK: - En-tête

    /// Chevrons, intervalle affiché, et retour au présent.
    ///
    /// « Aujourd'hui » n'apparaît que lorsqu'on s'est éloigné : un bouton qui ne ferait
    /// rien occuperait l'espace sans l'expliquer.
    @ViewBuilder
    private var header: some View {
        HStack {
            Button {
                viewModel.shift(forward: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(CalendarStrings.previousPeriod)

            Spacer()

            VStack(spacing: 2) {
                Text(rangeTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .contentTransition(.identity)

                if !viewModel.showsToday {
                    Button(CalendarStrings.today) {
                        viewModel.goToToday()
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button {
                viewModel.shift(forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(CalendarStrings.nextPeriod)
        }
        .font(.title3)
        .edgePadding(.horizontal)
        .padding(.top, 12)
        // La plage de dates est un repère, pas un titre de section : lui donner de
        // l'air en dessous évite qu'elle se lise comme l'en-tête de la première ligne
        // de cases.
        .padding(.bottom, 28)
    }

    /// « 15 – 30 septembre 2026 », l'année n'étant répétée que si la période l'enjambe.
    private var rangeTitle: String {
        let days = viewModel.days

        guard let first = days.first, let last = days.last else { return "" }

        let sameYear = Calendar.current.component(.year, from: first)
            == Calendar.current.component(.year, from: last)

        let start = sameYear
            ? first.formatted(.dateTime.day().month(.abbreviated))
            : first.formatted(.dateTime.day().month(.abbreviated).year())

        return "\(start) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.error {
            unavailable(error)
        } else if !viewModel.isLoading, viewModel.releasesByDay.isEmpty {
            // Vide n'est pas une panne : on peut très bien ne rien avoir à voir cette
            // quinzaine-là, et les chevrons restent utilisables.
            ContentUnavailableView(
                CalendarStrings.emptyTitle,
                systemImage: "calendar",
                description: Text(CalendarStrings.emptyMessage)
            )
        } else {
            grid
        }
    }

    /// `LazyVGrid` sans défilement propre : les seize cases tiennent dans la largeur,
    /// c'est la page entière qui défile.
    @ViewBuilder
    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(viewModel.days, id: \.self) { day in
                let entries = viewModel.entries(on: day)

                CalendarDayCell(
                    day: day,
                    entries: entries,
                    metrics: metrics
                )
                .onTapGesture {
                    guard entries.isNotEmpty else { return }
                    selectedDay = CalendarDaySelection(day: day)
                }
            }
        }
        .edgePadding(.horizontal)
    }

    // MARK: - Mes suivis

    /// Les médias suivis, et de quoi cesser de les suivre.
    ///
    /// C'est le seul endroit de l'app où cette liste existe : on pouvait suivre depuis
    /// une fiche, mais pas voir ce qu'on suivait ni le défaire sans la rouvrir.
    @ViewBuilder
    private var followsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showsFollows.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(CalendarStrings.myFollows)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Image(systemName: "chevron.forward")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsFollows ? 90 : 0))

                    Spacer()
                }
                .foregroundStyle(.primary)
                .edgePadding(.horizontal)
            }
            .buttonStyle(.plain)

            if showsFollows {
                VStack(spacing: 0) {
                    ForEach(viewModel.follows) { follow in
                        FollowRow(follow: follow) {
                            Task { await viewModel.unfollow(follow) }
                        }
                    }
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func unavailable(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(CalendarStrings.unavailableTitle, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 8) {
                Text(CalendarStrings.unavailableMessage)
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Une case de jour : son jour, les médias qui sortent, et le reste en compteur.
struct CalendarDayCell: View {

    /// Tout ce qui change entre l'iPhone et un grand écran, en un seul endroit.
    struct Metrics {

        let height: CGFloat
        /// Titres affichés avant de résumer le reste.
        let maxInline: Int
        let titleLines: Int
        let titleSize: CGFloat
        let daySize: CGFloat

        /// iPhone. Deux titres au plus : une case fait le quart de la largeur, au-delà
        /// les lignes deviennent trop serrées. Le web applique le même plafond.
        static let compact = Metrics(height: 82, maxInline: 2, titleLines: 1, titleSize: 9, daySize: 11)

        /// iPad : la grille de l'iPhone, agrandie. Des cases plus hautes et un texte
        /// plus grand, 150 pt pour que les quatre lignes tiennent encore en paysage.
        /// ❌ 8 colonnes : cases étroites, texte minuscule, la moitié de l'écran vide.
        static let regular = Metrics(height: 150, maxInline: 3, titleLines: 2, titleSize: 13, daySize: 15)
    }

    let day: Date
    let entries: [CalendarEntry]
    let metrics: Metrics

    private var isToday: Bool { CalendarViewModel.isToday(day) }
    private var isPast: Bool { CalendarViewModel.isPast(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            dayNumber

            // Un média par ligne, quel que soit le nombre d'épisodes qu'il diffuse
            // ce jour-là : une case de calendrier dit *ce qui sort*, pas le détail.
            ForEach(entries.prefix(metrics.maxInline)) { entry in
                Text(entry.release.title)
                    .font(.system(size: metrics.titleSize, weight: .medium))
                    .lineLimit(metrics.titleLines)
                    .truncationMode(.tail)
                    .foregroundStyle(entry.release.isMovie ? Color.orange : Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if entries.count > metrics.maxInline {
                Text(CalendarStrings.more(entries.count - metrics.maxInline))
                    .font(.system(size: metrics.titleSize))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(5)
        // ⚠️ `maxWidth: .infinity` est indispensable : sans lui chaque case épouse
        // la largeur de son contenu, les cases vides se rétrécissent et les colonnes
        // cessent d'être alignées — une grille de calendrier qui n'aligne rien.
        .frame(maxWidth: .infinity, minHeight: metrics.height, maxHeight: metrics.height, alignment: .topLeading)
        .background(background, in: .rect(cornerRadius: 8))
        // Le passé s'efface sans disparaître : on le lit encore, il ne retient plus
        // l'œil. Même intention que `is-past` dans le front web.
        .opacity(isPast ? 0.45 : 1)
    }

    /// « lun. 14 », et non le seul numéro.
    ///
    /// ⚠️ Sur **quatre** colonnes (iPhone), seize jours font tourner les jours de la semaine
    /// d'une ligne à l'autre : la première colonne est lundi, puis vendredi, puis
    /// mardi. Une colonne ne désigne donc aucun jour fixe, et sans ce rappel dans
    /// chaque case on ne sait plus quel jour on regarde. Le front web mobile fait de
    /// même — c'est la contrepartie de la grille 4×4 face à une semaine de 7 jours.
    @ViewBuilder
    private var dayNumber: some View {
        Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
            .font(.system(size: metrics.daySize, weight: isToday ? .bold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isToday ? Color.accentColor : .primary)
    }

    private var background: Color {
        if isToday { return Color.accentColor.opacity(0.18) }

        return entries.isEmpty ? Color.secondarySystemFill.opacity(0.4) : Color.secondarySystemFill
    }
}

/// Le jour dont la feuille est ouverte, ce que `.sheet(item:)` exige.
///
/// ⚠️ **Un type à nous, et non `extension Date: Identifiable`.** `@retroactive` fait
/// taire l'avertissement, il ne supprime pas le risque : `Date` appartient à
/// Foundation et `Identifiable` à la bibliothèque standard. Le jour où Apple ajoute
/// la conformance, le build casse d'un coup — et la portée était le module entier
/// pour un besoin d'un seul fichier.
///
/// L'identité est la **clé de jour**, pas l'horodatage : deux `Date` du même jour
/// doivent désigner la même feuille, ce que `timeIntervalSince1970` ne faisait pas.
private struct CalendarDaySelection: Identifiable {

    let date: Date

    /// Calculée à la création : `CalendarViewModel.key(for:)` vit sur le `MainActor`
    /// — son formateur y est isolé — alors que `Identifiable.id` se lit de partout.
    let id: String

    @MainActor
    init(day: Date) {
        self.date = day
        self.id = CalendarViewModel.key(for: day)
    }
}

/// Un média suivi : son affiche, son titre, sa prochaine sortie, et de quoi cesser
/// de le suivre.
struct FollowRow: View {

    @Router
    private var router

    @Namespace
    private var namespace

    let follow: EnhancedFinFollow
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                router.openEnhancedFin(follow, in: namespace)
            } label: {
                HStack(spacing: 12) {
                    ImageView(ImageSource(url: URL.enhancedFinImage(follow.posterUrl)))
                        .failure {
                            ZStack {
                                Color.secondarySystemFill
                                Image(systemName: follow.systemImage)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 40, height: 60)
                        .clipShape(.rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(follow.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(nextAir)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            // Bouton explicite plutôt qu'un balayage : les lignes vivent dans un
            // `ScrollView`, pas dans une `List`, et `swipeActions` n'y existe pas.
            // L'icône reprend la cloche de la barre d'actions, barrée.
            Button(action: onUnfollow) {
                Image(systemName: "bell.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CalendarStrings.unfollow)
        }
        .padding(.vertical, 6)
        .edgePadding(.horizontal)
    }

    /// « Prochain : jeu. 24 sept. », ou la mention d'absence.
    ///
    /// ⚠️ `nextAirDate` est nulle pour une série terminée ou dont la suite n'est pas
    /// annoncée — fréquent. Une ligne vide laisserait croire à un chargement raté.
    private var nextAir: String {
        guard let date = follow.nextAirDate,
              let parsed = CalendarViewModel.date(fromKey: date)
        else { return CalendarStrings.noNextAirDate }

        return CalendarStrings.nextAir(parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
    }
}
