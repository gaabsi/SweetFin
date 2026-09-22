//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftUI

/// Ce qui sort un jour : un média, et combien d'épisodes il en diffuse.
///
/// ``count`` vaut 1 pour un film comme pour un épisode isolé ; au-delà, la série
/// diffuse plusieurs épisodes le même jour.
struct CalendarEntry: Identifiable, Hashable {

    let release: EnhancedFinRelease
    let count: Int

    var id: String { release.mediaKey }
}

/// Alimente l'onglet Calendrier depuis `GET /me/calendar`.
///
/// Une période de 16 jours à la fois, démarrant un lundi.
///
/// ⚠️ Sur quatre colonnes, une colonne ne désigne **aucun** jour fixe : seize jours
/// font tourner les jours de la semaine d'une ligne à l'autre. Chaque case rappelle
/// donc son jour (« lun. 14 »).
@MainActor
final class CalendarViewModel: ViewModel {

    /// 4 colonnes × 4 lignes.
    static let daysPerPage = 16

    /// Ce que décalent les chevrons. Une quinzaine, comme le front web : un pas d'une
    /// période entière ferait perdre le fil, un pas d'un jour serait interminable.
    private static let shiftDays = 14

    /// Calendrier **ISO 8601**, dont la semaine commence toujours un lundi.
    ///
    /// `Calendar.current` suivrait la région de l'appareil — dimanche aux États-Unis —
    /// et la grille ne commencerait plus le même jour selon le téléphone.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        return calendar
    }()

    /// Convertit une date en clé de jour, au format du serveur.
    ///
    /// ⚠️ `locale` en `en_US_POSIX` : sans lui, un format fixe est interprété selon les
    /// réglages de l'appareil, et un calendrier bouddhiste ou japonais produirait
    /// « 2569-09-20 ». Aucune sortie ne serait alors trouvée, sans la moindre erreur.
    ///
    /// ⚠️ Le fuseau est celui de l'appareil, **et doit l'être** : les dates du serveur
    /// sont des jours calendaires sans heure. Les lire en UTC alors que la grille est
    /// construite en heure locale décalerait les sorties d'une case pour quiconque vit
    /// à l'ouest de Greenwich.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter
    }()

    /// Sorties du jour, indexées par clé de jour.
    @Published
    private(set) var releasesByDay: [String: [EnhancedFinRelease]] = [:]

    /// Les médias suivis, les plus récemment ajoutés d'abord.
    @Published
    private(set) var follows: [EnhancedFinFollow] = []

    @Published
    private(set) var isLoading = false

    @Published
    private(set) var error: Error?

    /// Premier jour affiché — toujours un lundi.
    @Published
    private(set) var start: Date = CalendarViewModel.weekStart(of: Date())

    /// Les seize jours de la période.
    var days: [Date] {
        (0 ..< Self.daysPerPage).compactMap {
            Self.isoCalendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    /// La période affichée contient-elle aujourd'hui ?
    var showsToday: Bool {
        days.contains { Self.isoCalendar.isDateInToday($0) }
    }

    /// Ce qui sort un jour donné, **un média par ligne**.
    ///
    /// Une série qui diffuse quatre épisodes d'un coup compte pour une entrée : on
    /// veut savoir *qu'elle sort*, pas dérouler sa liste d'épisodes dans une case de
    /// calendrier. Le front web agrège de la même façon (`_flatten_releases` :
    /// « 1 entrée par jour quel que soit le nb d'épisodes »).
    ///
    /// Le groupement se fait ici et non côté serveur : la route garde le détail, que
    /// d'autres écrans pourront vouloir, et ce modèle vit dans `Shared/` — tvOS en
    /// héritera sans duplication.
    ///
    /// Parametres :
    /// - day (Date) : jour interrogé
    ///
    /// Output :
    /// - entries ([CalendarEntry]) : un média par entrée, dans l'ordre du serveur
    func entries(on day: Date) -> [CalendarEntry] {
        let releases = releasesByDay[Self.key(for: day)] ?? []

        var order: [String] = []
        var grouped: [String: [EnhancedFinRelease]] = [:]

        for release in releases {
            if grouped[release.mediaKey] == nil { order.append(release.mediaKey) }
            grouped[release.mediaKey, default: []].append(release)
        }

        return order.compactMap { key in
            guard let group = grouped[key], let first = group.first else { return nil }

            return CalendarEntry(release: first, count: group.count)
        }
    }

    // MARK: - Navigation

    func shift(forward: Bool) {
        let amount = forward ? Self.shiftDays : -Self.shiftDays

        guard let moved = Self.isoCalendar.date(byAdding: .day, value: amount, to: start) else { return }

        start = moved
    }

    func goToToday() {
        start = Self.weekStart(of: Date())
    }

    // MARK: - Chargement

    /// Charge la période courante.
    ///
    /// Une seule requête : le serveur borne la plage à 366 jours, et seize en sont
    /// loin. Rien n'est conservé d'une période à l'autre — les dates de diffusion
    /// bougent, et une sortie repoussée doit se voir au retour.
    func load() async {
        guard let client = userSession?.enhancedFinClient,
              let last = days.last
        else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // En parallèle : les deux listes sont indépendantes, et les enchaîner
            // doublerait l'attente avant que l'écran s'affiche.
            async let calendar = client.calendar(
                from: Self.key(for: start),
                to: Self.key(for: last)
            )
            async let follows = client.follows()

            let (days, followed) = try await (calendar.days, follows.items)

            // ⚠️ **Fusionner, et non faire confiance.** `Dictionary(uniqueKeysWithValues:)`
            // *trap* sur une clé en double — un crash, pas une erreur, que le `catch`
            // ci-dessous ne rattraperait pas. Or `date` vient du serveur : deux
            // regroupements pour un même jour suffiraient à fermer l'app.
            releasesByDay = Dictionary(days.map { ($0.date, $0.releases) }, uniquingKeysWith: +)
            self.follows = followed
            error = nil
        } catch {
            logger.warning("EnhancedFin calendar failed: \(error.localizedDescription)")
            releasesByDay = [:]
            follows = []
            self.error = error
        }
    }

    /// Ne plus suivre un média.
    ///
    /// Le retrait est **optimiste** : la ligne disparaît tout de suite, et revient si
    /// le serveur refuse. Même patron que les boutons de la barre d'actions.
    ///
    /// ⚠️ La grille est rechargée ensuite : les sorties de ce média n'ont plus lieu
    /// d'y figurer. Sans ça, l'écran se contredirait — une série absente de la liste
    /// des suivis mais toujours présente dans les cases.
    ///
    /// Parametres :
    /// - follow (EnhancedFinFollow) : le suivi à retirer
    func unfollow(_ follow: EnhancedFinFollow) async {
        guard let client = userSession?.enhancedFinClient else { return }

        let previous = follows
        follows.removeAll { $0.mediaKey == follow.mediaKey }

        do {
            try await client.unfollow(follow.mediaKey)
            await load()
        } catch {
            logger.warning("EnhancedFin unfollow failed: \(error.localizedDescription)")
            follows = previous
        }
    }

    // MARK: - Dates

    static func key(for day: Date) -> String {
        dayFormatter.string(from: day)
    }

    /// L'inverse de ``key(for:)`` : une clé de jour du serveur vers une date.
    ///
    /// Même formateur, donc mêmes garanties de locale et de fuseau — les deux
    /// conversions ne peuvent pas diverger.
    ///
    /// Parametres :
    /// - key (String) : jour au format `AAAA-MM-JJ`
    ///
    /// Output :
    /// - date (Date?) : nil si la chaîne n'est pas au format attendu
    static func date(fromKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    /// Le lundi de la semaine d'une date.
    private static func weekStart(of day: Date) -> Date {
        let components = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)

        return isoCalendar.date(from: components) ?? isoCalendar.startOfDay(for: day)
    }

    static func isToday(_ day: Date) -> Bool {
        isoCalendar.isDateInToday(day)
    }

    /// Antérieur à aujourd'hui — la case est alors atténuée, comme dans le front web.
    static func isPast(_ day: Date) -> Bool {
        isoCalendar.startOfDay(for: day) < isoCalendar.startOfDay(for: Date())
    }
}
