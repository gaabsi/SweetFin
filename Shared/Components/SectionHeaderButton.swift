//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// SweetFin : titre de section cliquable, partagé par l'Accueil
/// (`PosterHStackLibrarySection`) et l'Explorer (`ExplorerSectionHeader`).
///
/// - iOS : titre et chevron accolés, chevron en `.secondary` ;
/// - tvOS : le titre seul ; au focus, pastille de verre et chevron. ❌ Le style de bouton
///   par défaut de tvOS : un pavé gris, sans rapport avec les en-têtes de l'Accueil.
struct SectionHeaderButton<Title: View>: View {

    let action: () -> Void

    @ViewBuilder
    let title: Title

    var body: some View {
        Button(action: action) {
            #if os(tvOS)
            title
            #else
            HStack(spacing: 3) {
                title

                Image(systemName: "chevron.forward")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .foregroundStyle(.primary, .secondary)
        #if os(tvOS)
        .buttonStyle(TVHeaderButtonStyle())
        #endif
    }
}

#if os(tvOS)
private struct TVHeaderButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.label

            if isFocused {
                Image(systemName: "chevron.forward")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .backport
        .glassEffect(isFocused ? .regular : .identity, in: .capsule)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        // La pastille déborde à gauche : le titre reste aligné sur le rail.
        .offset(x: -16)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.8 : 1)
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
