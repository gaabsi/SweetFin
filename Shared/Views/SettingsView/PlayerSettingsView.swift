//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

/// SweetFin : Réglages → Avancé → Lecteur vidéo, à la place de
/// `VideoPlayerSettingsView` (upstream, gardé pour tvOS).
///
/// Seulement ce que l'utilisateur règle vraiment : la longueur des sauts, et ses
/// langues préférées. Le reste (moteur, aperçus, gestes…) est imposé par
/// `SweetFinPlayerPolicy`.
struct PlayerSettingsView: View {

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardInterval
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardInterval

    /// Les langues préférées vivent dans la configuration **serveur** de l'utilisateur :
    /// Jellyfin s'en sert pour choisir les pistes, sur tous les appareils.
    @StateObject
    private var viewModel = ServerUserAdminViewModel(
        user: Container.shared.currentUserSession()?.user.data ?? UserDto()
    )

    var body: some View {
        Form(systemImage: "tv") {
            Section(L10n.buttons) {
                JumpIntervalPicker(title: L10n.jumpBackwardLength, selection: $jumpBackwardInterval)
                JumpIntervalPicker(title: L10n.jumpForwardLength, selection: $jumpForwardInterval)
            }

            Section(PlayerStrings.audioAndSubtitles) {
                CulturePicker(
                    PlayerStrings.preferredAudioLanguage,
                    threeLetterISOLanguageName: configurationBinding(\.audioLanguagePreference)
                )
                CulturePicker(
                    PlayerStrings.preferredSubtitleLanguage,
                    threeLetterISOLanguageName: configurationBinding(\.subtitleLanguagePreference)
                )
            }
            // La configuration est renvoyée **en entier** au serveur : tant qu'elle n'a pas
            // été relue, on écraserait ce qui a changé depuis un autre appareil.
            .disabled(viewModel.state != .content)
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        .navigationTitle(L10n.videoPlayer.localizedCapitalized)
        .topBarTrailing {
            if viewModel.background.is(.updating) || viewModel.background.is(.refreshing) {
                ProgressView()
            }
        }
    }

    /// Un champ de la configuration serveur de l'utilisateur, lu et écrit comme le fait
    /// `VideoPlayerSettingsView`.
    ///
    /// Parametres :
    /// - keyPath (WritableKeyPath<UserConfiguration, String?>) : le champ
    ///
    /// Output :
    /// - binding (Binding<String?>) : la valeur, envoyée au serveur à chaque changement
    private func configurationBinding(
        _ keyPath: WritableKeyPath<UserConfiguration, String?>
    ) -> Binding<String?> {
        Binding(
            get: { viewModel.user.configuration?[keyPath: keyPath] },
            set: { newValue in
                guard viewModel.user.id != nil, var configuration = viewModel.user.configuration else { return }

                configuration[keyPath: keyPath] = newValue
                viewModel.updateConfiguration(configuration)
            }
        )
    }
}
