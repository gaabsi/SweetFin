//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

extension ViewContext {

    /// SweetFin : une tuile de « Continuer de regarder », seul endroit où l'appui
    /// long propose « Masquer » (`BaseItemDtoPosterContextMenu`).
    ///
    /// Distinct d'`isInResume`, qui sert aussi à tvOS et aux indicateurs d'affiche.
    ///
    /// ⚠️ Premier bit libre après ceux d'upstream (`WithViewContext.swift`, jusqu'à
    /// `1 << 6`). À décaler si upstream en ajoute.
    static let isInContinueWatching = Self(rawValue: 1 << 7)
}
