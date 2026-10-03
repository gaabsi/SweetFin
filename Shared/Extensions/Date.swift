//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension Date {

    func isStale(with interval: Duration) -> Bool {
        Date.now.timeIntervalSince(self) > interval.seconds
    }
}

extension DateFormatter {

    /// SweetFin : jours calendaires du serveur et de TMDB (`AAAA-MM-JJ`, sans heure).
    /// Seul formateur de ce format dans l'app : calendrier, épisodes et personnes
    /// lisent tous leurs dates de la même façon.
    ///
    /// ⚠️ `locale` en `en_US_POSIX` : sans lui, un format fixe est interprété selon les
    /// réglages de l'appareil, et un calendrier bouddhiste ou japonais produirait
    /// « 2569-09-20 ». Aucune sortie ne serait alors trouvée, sans la moindre erreur.
    ///
    /// ⚠️ Le fuseau est celui de l'appareil, **et doit l'être** : ces dates sont des
    /// jours sans heure. Les lire en UTC puis les afficher en heure locale les
    /// décalerait d'un jour pour quiconque vit à l'ouest de Greenwich.
    static let calendarDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter
    }()
}
