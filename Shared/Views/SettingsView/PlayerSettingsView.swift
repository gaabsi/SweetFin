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

/// SweetFin : Réglages → Avancé → Lecteur vidéo, à la place du
/// `VideoPlayerSettingsView` d'upstream.
///
/// Seulement ce que l'utilisateur règle vraiment : la longueur des sauts, et ses
/// langues préférées. Le reste (moteur, aperçus, gestes…) est imposé par
/// `SweetFinPlayerPolicy`.
struct PlayerSettingsView: View {

    @Default(.VideoPlayer.jumpBackwardInterval)
    private var jumpBackwardInterval
    @Default(.VideoPlayer.jumpForwardInterval)
    private var jumpForwardInterval
    @Default(.VideoPlayer.Subtitles.extraLanguages)
    private var extraLanguages
    @Default(.VideoPlayer.Subtitles.showSDH)
    private var showSDH
    @Default(.VideoPlayer.Audio.showAudioDescription)
    private var showAudioDescription

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

                Picker(L10n.subtitleMode, selection: configurationBinding(\.subtitleMode)) {
                    ForEach(SubtitlePlaybackMode.allCases, id: \.self) { mode in
                        Text(mode.displayTitle)
                            .tag(mode as SubtitlePlaybackMode?)
                    }
                }
            }
            // La configuration est renvoyée **en entier** au serveur : tant qu'elle n'a pas
            // été relue, on écraserait ce qui a changé depuis un autre appareil.
            .disabled(viewModel.state != .content)

            Section {
                NavigationLink {
                    ExtraSubtitleLanguagesView()
                } label: {
                    LabeledContent(PlayerStrings.extraSubtitleLanguages, value: extraLanguagesSummary)
                }

                Toggle(PlayerStrings.showSDH, isOn: $showSDH)
                Toggle(PlayerStrings.showAudioDescription, isOn: $showAudioDescription)
            } footer: {
                Text(PlayerStrings.accessibilityFooter)
            }
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

    /// Les langues cochées, par leur nom (« Anglais, Espagnol »).
    private var extraLanguagesSummary: String {
        let names = extraLanguages.compactMap(MediaTrackFilter.languageName)

        return names.isEmpty ? L10n.none : names.joined(separator: ", ")
    }

    /// Un champ de la configuration serveur de l'utilisateur, lu et écrit.
    ///
    /// Parametres :
    /// - keyPath (WritableKeyPath<UserConfiguration, Value?>) : le champ
    ///
    /// Output :
    /// - binding (Binding<Value?>) : la valeur, envoyée au serveur à chaque changement
    private func configurationBinding<Value>(
        _ keyPath: WritableKeyPath<UserConfiguration, Value?>
    ) -> Binding<Value?> {
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

/// SweetFin : les langues de sous-titres proposées en plus de la langue préférée.
///
/// Une liste à cocher plutôt qu'un menu : on en choisit plusieurs, parmi toutes les
/// langues que connaît le serveur.
private struct ExtraSubtitleLanguagesView: View {

    @Default(.VideoPlayer.Subtitles.extraLanguages)
    private var extraLanguages

    @StateObject
    private var viewModel = PagingLibraryViewModel(library: CultureLibrary())

    private var cultures: [CultureDto] {
        viewModel.elements
            .filter { $0.threeLetterISOLanguageName != nil }
            .sorted { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending }
    }

    var body: some View {
        List(cultures) { culture in
            let code = culture.threeLetterISOLanguageName!

            Button {
                toggle(code)
            } label: {
                HStack {
                    Text(culture.displayTitle.capitalized(with: .current))
                        .foregroundStyle(.primary)

                    Spacer()

                    if extraLanguages.contains(code) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle(PlayerStrings.extraSubtitleLanguages)
        .onFirstAppear {
            viewModel.refresh()
        }
    }

    /// Coche ou décoche une langue.
    ///
    /// Parametres :
    /// - code (String) : code ISO 639-2 de la langue
    private func toggle(_ code: String) {
        if extraLanguages.contains(code) {
            extraLanguages.removeAll { $0 == code }
        } else {
            extraLanguages.append(code)
        }
    }
}
