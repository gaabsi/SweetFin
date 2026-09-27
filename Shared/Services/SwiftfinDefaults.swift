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
    static let appSuite = UserDefaults(suiteName: "swiftfinApp")!

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

        enum Poster {

            static var configuration: Key<PosterConfiguration> {
                UserKey("posterConfiguration", default: .default)
            }
        }

        enum Library {

            static var cinematicBackground: Key<Bool> {
                UserKey("libraryCinematicBackground", default: true)
            }

            static var enabledDrawerFilters: Key<[ItemFilterType]> {
                UserKey(
                    "libraryEnabledDrawerFilters",
                    default: ItemFilterType.allCases
                )
            }

            static var letterPickerOrientation: Key<LetterPickerOrientation> {
                UserKey("letterPickerOrientation", default: .disabled)
            }

            static var style: Key<LibraryStyle> {
                UserKey(
                    "libraryStyle",
                    default: .init(
                        displayType: .grid,
                        posterDisplayType: .portrait,
                        listColumnCount: 1
                    )
                )
            }

            static var randomImage: Key<Bool> {
                UserKey("libraryRandomImage", default: true)
            }

            static var showFavorites: Key<Bool> {
                UserKey("libraryShowFavorites", default: true)
            }

            static var rememberLayout: Key<Bool> {
                UserKey("libraryRememberLayout", default: false)
            }

            static var rememberSort: Key<Bool> {
                UserKey("libraryRememberSort", default: false)
            }
        }

        enum Home {
            /// Nombre de tuiles d'« Ajoutés récemment » (`HomeRecentlyAddedLibrary`).
            static var recentlyAddedLimit: Key<Int> {
                UserKey("homeRecentlyAddedLimit", default: 20)
            }
        }
    }

    enum VideoPlayer {

        static var appMaximumBitrate: Key<PlaybackBitrate> {
            UserKey("appMaximumBitrate", default: .max)
        }

        static var appMaximumBitrateTest: Key<PlaybackBitrateTestSize> {
            UserKey("appMaximumBitrateTest", default: .regular)
        }

        static var jumpBackwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpBackwardLength", default: .fifteen)
        }

        static var jumpForwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpForwardLength", default: .fifteen)
        }

        static var supplements: Key<[VideoPlayerSupplement]> {
            UserKey(
                "videoPlayerSupplements",
                default: VideoPlayerSupplement.supportedCases
            )
        }

        static var videoPlayerType: Key<VideoPlayerType> {
            UserKey("videoPlayerType", default: .vlc)
        }

        enum Gesture {

            static var horizontalPanAction: Key<PanGestureAction> {
                UserKey("videoPlayerHorizontalPanGesture", default: .none)
            }

            static var horizontalSwipeAction: Key<SwipeGestureAction> {
                UserKey("videoPlayerhorizontalSwipeAction", default: .none)
            }

            static var longPressAction: Key<LongPressGestureAction> {
                UserKey("videoPlayerLongPressGesture", default: .gestureLock)
            }

            static var longPressSpeedMultiplier: Key<PlaybackSpeed> {
                UserKey(
                    "videoPlayerLongPressSpeedMultiplier",
                    default: .two
                )
            }

            static var multiTapGesture: Key<MultiTapGestureAction> {
                UserKey("videoPlayerMultiTapGesture", default: .none)
            }

            static var doubleTouchGesture: Key<DoubleTouchGestureAction> {
                UserKey("videoPlayerDoubleTouchGesture", default: .none)
            }

            static var pinchGesture: Key<PinchGestureAction> {
                UserKey("videoPlayerSwipeGesture", default: .aspectFill)
            }

            static var verticalPanLeftAction: Key<PanGestureAction> {
                UserKey("videoPlayerverticalPanLeftAction", default: .none)
            }

            static var verticalPanRightAction: Key<PanGestureAction> {
                UserKey("videoPlayerverticalPanRightAction", default: .none)
            }
        }

        enum Overlay {

            static var chapterSlider: Key<Bool> {
                UserKey("chapterSlider", default: true)
            }

        }

        enum Playback {
            static var appMaximumResolution: Key<PlaybackResolution> {
                UserKey("appMaximumResolution", default: .max)
            }

            static var appMaximumBitrate: Key<PlaybackBitrate> {
                UserKey("appMaximumBitrate", default: .auto)
            }

            static var appMaximumBitrateTest: Key<PlaybackBitrateTestSize> {
                UserKey("appMaximumBitrateTest", default: .regular)
            }

            static var compatibilityMode: Key<PlaybackCompatibility> {
                UserKey("compatibilityMode", default: .auto)
            }

            static var playbackRate: Key<Float> {
                UserKey("playbackRate", default: Float(1.0))
            }
        }

    }

    // Experimental settings
    enum Experimental {

        static var mpvPlayer: Key<Bool> {
            UserKey("experimentalMPVPlayer", default: false)
        }

        static var serverConnectionAutoSwitch: Key<Bool> {
            UserKey("experimentalServerConnectionAutoSwitch", default: false)
        }

        static var videoPlayerEPG: Key<Bool> {
            UserKey("experimentalVideoPlayerEPG", default: false)
        }
    }

    // tvos specific

}

// MARK: Debug

#if DEBUG

extension UserDefaults {

    static let debugSuite = UserDefaults(suiteName: "swiftfinstore-debug-defaults")!
}

extension Defaults.Keys {

    static func DebugKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .appSuite)
    }

    static let sendProgressReports: Key<Bool> = DebugKey("sendProgressReports", default: true)
}
#endif
