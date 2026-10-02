//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum DownloadStrings {

    static let downloads = String(localized: "Downloads", table: "SweetFin")
    static let download = String(localized: "Download", table: "SweetFin")
    static let downloaded = String(localized: "Downloaded", table: "SweetFin")
    static let cancelDownload = String(localized: "Cancel Download", table: "SweetFin")
    static let deleteDownload = String(localized: "Delete Download", table: "SweetFin")
    static let retryDownload = String(localized: "Retry Download", table: "SweetFin")
    static let missingSource = String(localized: "No file to download for this item.", table: "SweetFin")
    static let failed = String(localized: "Download Failed", table: "SweetFin")

    static let offlineBanner = String(localized: "Offline — only your downloads are available.", table: "SweetFin")

    static let emptyTitle = String(localized: "No Downloads", table: "SweetFin")
    static let emptyMessage = String(localized: "Open a movie or an episode, then ⋯ → Download. It will stay playable offline.", table: "SweetFin")

    static let downloadSeason = String(localized: "Download Rest of Season", table: "SweetFin")
    static let nothingToDownload = String(localized: "Nothing to download: you've watched everything, or the rest of the season is already downloaded.", table: "SweetFin")

    static func seasonSummary(count: Int, bytes: Int64) -> String {
        String(localized: "\(count) episodes · \(size(bytes))", table: "SweetFin")
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func totalSize(_ bytes: Int64) -> String {
        String(localized: "\(size(bytes)) used on this device", table: "SweetFin")
    }

    static func downloading(_ progress: Double) -> String {
        String(localized: "Downloading \(Int(progress * 100))%", table: "SweetFin")
    }

    static func notEnoughSpace(needed: Int64, available: Int64) -> String {
        String(localized: "Not enough space: \(size(needed)) needed, \(size(available)) available.", table: "SweetFin")
    }
}
