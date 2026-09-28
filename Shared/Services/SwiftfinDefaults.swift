//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation
import SwiftUI
import UIKit

// TODO: organize
// TODO: all user settings could be moved to `StoredValues`?

// Note: Only use Defaults for basic single-value settings.
//       For larger data types and collections, use `StoredValue` instead.

// MARK: Suites

extension UserDefaults {

    // MARK: App

    /// Settings that should apply to the app
    static let appSuite = UserDefaults(suiteName: "sweetfinApp")!

    // MARK: User

    static var currentUserSuite: UserDefaults {
        switch Defaults[.lastSignedInUserID] {
        case .signedOut:
            userSuite(id: "default")
        case let .signedIn(userID):
            userSuite(id: userID)
        }
    }

    static func userSuite(id: String) -> UserDefaults {
        UserDefaults(suiteName: id)!
    }
}

private extension Defaults.Keys {

    static func AppKey<Value: Defaults.Serializable>(_ name: String) -> Key<Value?> {
        Key(name, suite: .appSuite)
    }

    static func AppKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .appSuite)
    }

    static func UserKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .currentUserSuite)
    }
}

// MARK: App

extension Defaults.Keys {

    /// The _real_ accent color key to be used.
    ///
    /// EnhancedFin : écrite **uniquement** par `RootCoordinator.applyAppearance`, à
    /// partir du thème. Le réglage utilisateur et sa clé `userAccentColor` ont été
    /// retirés — deux écrivains concurrents rendaient la valeur finale dépendante de
    /// l'ordre d'exécution de deux `Task`.
    static var accentColor: Key<Color> = AppKey("accentColor", default: .jellyfinPurple)

    /// The _real_ appearance key to be used.
    ///
    /// This is set externally whenever the app or user appearances change,
    /// depending on the current app state.
    static let appearance: Key<AppAppearance> = AppKey("appearance", default: .elegantFin)

    /// The appearance default for non-user contexts.
    /// /// Only use for `set`, use `appearance` for `get`.
    static let appAppearance: Key<AppAppearance> = AppKey("appAppearance", default: .elegantFin)

    static let backgroundTimeStamp: Key<Date> = AppKey("backgroundTimeStamp", default: Date.now)
    static let lastSignedInUserID: Key<UserSessionState> = AppKey("lastSignedInUserID", default: .signedOut)
    static let lastServerInformationRefreshDate: Key<Date> = AppKey("lastServerInformationRefreshDate", default: .distantPast)

    static let selectUserServerSelection: Key<SelectUserServerSelection> = AppKey("selectUserServerSelection", default: .all)
}

// MARK: User

extension Defaults.Keys {

    /// The appearance default for user contexts.
    /// /// Only use for `set`, use `appearance` for `get`.
    static var userAppearance: Key<AppAppearance> {
        UserKey("userAppearance", default: .elegantFin)
    }

    enum Customization {

        static var tabBarPlacement: Key<TabBarPlacement> {
            UserKey("tabBarPlacement", default: .sidebar)
        }

        enum Library {

            static var cinematicBackground: Key<Bool> {
                UserKey("libraryCinematicBackground", default: true)
            }

        }

        enum Home {
            // EnhancedFin : sections optionnelles de l'Accueil (la media bar et « Continuer
            // de regarder » sont imposées). Anciens noms de clé gardés : un compte retrouve
            // son choix.
            static var showLibraries: Key<Bool> {
                UserKey("homeShowLibraries", default: true)
            }

            static var showRecentlyAdded: Key<Bool> {
                UserKey("showRecentlyAdded", default: true)
            }

            /// Ancienneté maximale, en jours, d'un média d'« Ajoutés récemment »
            /// (`HomeRecentlyAddedLibrary`).
            static var recentlyAddedDays: Key<Int> {
                UserKey("homeRecentlyAddedDays", default: 30)
            }
        }
    }

    enum VideoPlayer {

        static var jumpBackwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpBackwardLength", default: .fifteen)
        }

        static var jumpForwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpForwardLength", default: .fifteen)
        }

        enum Playback {
            static var playbackRate: Key<Float> {
                UserKey("playbackRate", default: Float(1.0))
            }
        }
    }
}

// MARK: Debug

#if DEBUG

extension UserDefaults {

    static let debugSuite = UserDefaults(suiteName: "sweetfinstore-debug-defaults")!
}

extension Defaults.Keys {

    static func DebugKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .appSuite)
    }

    static let sendProgressReports: Key<Bool> = DebugKey("sendProgressReports", default: true)
}
#endif
