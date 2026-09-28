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
import JellyfinAPI

// TODO: also have matching properties on `UserState` that get/set values
// TODO: cleanup/organize

// MARK: keys

extension StoredValues.Keys {

    /// Construct a key where `ownerID` is the id of the user in the
    /// current user session, or always returns the default if there
    /// isn't a current session user.
    static func CurrentUserKey<Value: Codable>(
        _ name: String? = nil,
        field: String,
        default defaultValue: Value,
        storage: StoredValues.Key<Value>.StorageDestination = .sql,
    ) -> Key<Value> {
        guard let currentUser = Container.shared.currentUserSession()?.user else {
            return Key(always: defaultValue)
        }

        return Key(
            name ?? field,
            ownerID: currentUser.id,
            field: field,
            storage: storage,
            default: defaultValue
        )
    }

    static func UserKey<Value: Codable>(
        _ name: String? = nil,
        ownerID: String,
        field: String,
        default defaultValue: Value
    ) -> Key<Value> {
        Key(
            name ?? field,
            ownerID: ownerID,
            field: field,
            default: defaultValue
        )
    }

    static func UserKey<Value: Codable>(always: Value) -> Key<Value> {
        Key(always: always)
    }
}

// MARK: values

extension UserDto: @retroactive Defaults.Serializable {}
extension UserDto: Storable {}
extension UserState: Defaults.Serializable {}
extension UserState: Storable {}
extension Array: Storable where Element: Storable {}
extension Bool: Storable {}
extension Int: Storable {}
extension String: Storable {}

extension StoredValues.Keys {

    enum User {

        static var users: Key<[UserState]> {
            Key(
                "users",
                ownerID: "sweetfinApp",
                field: "users",
                storage: .sql,
                default: []
            )
        }

        // Doesn't use `CurrentUserKey` because data may be
        // retrieved and stored without a user session
        static func data(id: String) -> Key<UserDto> {
            UserKey(
                ownerID: id,
                field: "userData",
                default: .init()
            )
        }

    }
}
