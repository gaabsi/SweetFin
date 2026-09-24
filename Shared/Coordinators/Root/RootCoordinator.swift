//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import SwiftUI
import UIKit

enum AppStartupError: Error {

    case dataStack(Error)
}

@MainActor
@Stateful
final class RootCoordinator: ObservableObject {

    @CasePathable
    enum Action {
        case start

        var transition: Transition {
            switch self {
            case .start:
                .to(.ready)
            }
        }
    }

    enum State {
        case initial
        case error
        case ready
    }

    private var started = false
    private var appearanceCancellable: AnyCancellable?
    private var currentSessionCancellable: AnyCancellable?

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    deinit {
        appearanceCancellable?.cancel()
        currentSessionCancellable?.cancel()
    }

    @Function(\Action.Cases.start)
    private func _start() async throws {
        guard !started else { return }
        started = true

        do {
            try await SwiftfinStore.setupDataStack()
            startPreferenceObservation()
        } catch {
            throw AppStartupError.dataStack(error)
        }
    }

    private func startPreferenceObservation() {
        setPreferenceObservation(for: userSessionManager.currentSession)

        currentSessionCancellable = userSessionManager.$currentSession
            .dropFirst()
            .sink { [weak self] session in
                Task { @MainActor in
                    self?.setPreferenceObservation(for: session)
                }
            }
    }

    private func setPreferenceObservation(for session: UserSession?) {
        if session == nil {
            setAppDefaultsObservation()
        } else {
            setUserDefaultsObservation()
        }
    }

    private func setUserDefaultsObservation() {
        appearanceCancellable?.cancel()

        // EnhancedFin : les réglages que le fork impose au lecteur, avant toute lecture.
        EnhancedFinPlayerPolicy.enforce()

        appearanceCancellable = Task {
            mirrorAppearanceForNextLaunch(Defaults[.userAppearance])
            applyAppearance(Defaults[.userAppearance])

            for await newValue in Defaults.updates(.userAppearance) {
                mirrorAppearanceForNextLaunch(newValue)
                applyAppearance(newValue)
            }
        }
        .asAnyCancellable()
    }

    private func setAppDefaultsObservation() {
        appearanceCancellable?.cancel()

        // EnhancedFin : plus de garde-fou `selectUserUseSplashscreen` ici, ni de tâche
        // qui l'observe. Tous deux ne servaient qu'au forçage `.dark` de l'écran de
        // sélection, supprimé avec les thèmes clairs — voir `applyAppearance`.
        appearanceCancellable = Task {
            applyAppearance(Defaults[.appAppearance])

            for await newValue in Defaults.updates(.appAppearance) {
                applyAppearance(newValue)
            }
        }
        .asAnyCancellable()
    }

    /// EnhancedFin : **le thème est le seul propriétaire de la couleur d'accent.**
    ///
    /// ⚠️ Il y avait deux écrivains concurrents sur `Defaults[.accentColor]` : une
    /// tâche qui suivait le réglage utilisateur et `applyAppearance`. `Defaults.updates`
    /// réémet la valeur courante à l'abonnement (`initial: true` par défaut), et l'ordre
    /// de deux `Task` indépendants n'est pas garanti : l'accent tombait sur la couleur
    /// du thème ou sur celle des réglages selon le lancement.
    ///
    /// Le réglage « couleur d'accent » a donc été retiré des réglages, et sa clé avec.
    ///
    /// Parametres :
    /// - color (Color) : la couleur d'accent du thème
    @MainActor
    private func applyAccentColor(_ color: Color) {
        Defaults[.accentColor] = color

        #if os(iOS)
        UIApplication.shared.setAccentColor(color.uiColor)
        #endif
    }

    @MainActor
    private func applyAppearance(_ appearance: AppAppearance) {
        Defaults[.appearance] = appearance
        UIApplication.shared.setAppearance(appearance.tokens.style)

        // EnhancedFin : un thème impose sa couleur d'accent.
        //
        // Posé ici plutôt que dans les deux tâches d'observation : `applyAppearance`
        // est le point de passage commun aux réglages de l'app **et** à ceux de
        // l'utilisateur, et c'est le second qui gouverne une fois connecté.
        #if os(iOS)
        applyAccentColor(appearance.tokens.accent)
        #endif
    }

    /// EnhancedFin : recopie l'apparence de l'utilisateur au niveau application.
    ///
    /// ⚠️ **Sans elle, l'application change de couleur sous les yeux au démarrage.**
    /// L'apparence choisie est stockée **par utilisateur**, mais avant l'ouverture de
    /// session c'est la clé **application** qui gouverne : l'écran de chargement
    /// s'affichait donc dans l'apparence par défaut, puis tout virait à la couleur du
    /// thème une fois la session ouverte.
    ///
    /// ⚠️ **À appeler depuis le chemin utilisateur uniquement.** Le placer dans
    /// `applyAppearance` recopierait aussi le `.dark` que l'écran de sélection impose,
    /// et écraserait le thème choisi.
    ///
    /// Parametres :
    /// - appearance (AppAppearance) : l'apparence choisie par l'utilisateur
    @MainActor
    private func mirrorAppearanceForNextLaunch(_ appearance: AppAppearance) {
        guard Defaults[.appAppearance] != appearance else { return }

        Defaults[.appAppearance] = appearance
    }

}
