//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

extension DeviceProfile {

    static func build(
        for videoPlayer: VideoPlayerType,
        compatibilityMode: PlaybackCompatibility,
        maxBitrate: Int? = nil,
        maxResolution: PlaybackResolution = Defaults[.VideoPlayer.Playback.appMaximumResolution]
    ) -> DeviceProfile {

        var deviceProfile: DeviceProfile = .init()

        // EnhancedFin : VLC et MPV lisent tout côté client → lecture directe dans 100 % des
        // cas, le Pi ne transcode jamais. Ni conditions par codec, ni profil de transcodage,
        // ni sous-titres incrustés : les réglages de compatibilité (masqués) sont ignorés.
        if videoPlayer != .native {
            deviceProfile.directPlayProfiles = PlaybackCompatibility.Video.forcedDirectPlayProfile
            deviceProfile.subtitleProfiles = videoPlayer.subtitleProfiles
            return deviceProfile
        }

        // MARK: - Video Player Specific Logic

        deviceProfile.codecProfiles = videoPlayer.codecProfiles

        deviceProfile.subtitleProfiles = videoPlayer.subtitleProfiles

        if let resolutionCodecProfile = maxResolution.codecProfile {
            deviceProfile.codecProfiles?.append(resolutionCodecProfile)
        }

        // MARK: - DirectPlay & Transcoding Profiles

        switch compatibilityMode {
        case .auto:
            deviceProfile.directPlayProfiles = videoPlayer.directPlayProfiles
            deviceProfile.transcodingProfiles = videoPlayer.transcodingProfiles

        case .mostCompatible:
            deviceProfile.directPlayProfiles = PlaybackCompatibility.Video.compatibilityDirectPlayProfile
            deviceProfile.transcodingProfiles = PlaybackCompatibility.Video.compatibilityTranscodingProfile

        case .directPlay:
            deviceProfile.directPlayProfiles = PlaybackCompatibility.Video.forcedDirectPlayProfile

        }

        // MARK: - Assign the Bitrate if provided

        if let maxBitrate {
            deviceProfile.maxStaticBitrate = maxBitrate
            deviceProfile.maxStreamingBitrate = maxBitrate
            deviceProfile.musicStreamingTranscodingBitrate = maxBitrate
        }

        return deviceProfile
    }

    // MARK: - Playback Capability Queries

    /// Whether any `DirectPlayProfile` allows media with this audio codec in the given container to be played directly.
    func canPlay(type: DlnaProfileType, audioCodec: String?, container: String?) -> Bool {
        (directPlayProfiles ?? []).contains { profile in
            profile.type == type
                && profileContains(profile: profile.audioCodec, audioCodec)
                && profileContains(profile: profile.container, container)
        }
    }

    /// Whether any `DirectPlayProfile` allows media with this video codec in the given container to be played directly.
    func canPlay(type: DlnaProfileType, videoCodec: String?, container: String?) -> Bool {
        (directPlayProfiles ?? []).contains { profile in
            profile.type == type
                && profileContains(profile: profile.videoCodec, videoCodec)
                && profileContains(profile: profile.container, container)
        }
    }

    /// Whether any `SubtitleProfile` allows this format to be delivered via the given method.
    func canPlay(subtitleFormat: String?, method: SubtitleDeliveryMethod) -> Bool {
        guard let subtitleFormat = subtitleFormat?.lowercased() else { return false }
        return (subtitleProfiles ?? []).contains { profile in
            profile.method == method
                && profile.format?.lowercased() == subtitleFormat
        }
    }

    /// Parse & check membership like this is CSV as that's the format we send to the server.
    private func profileContains(profile: String?, _ candidate: String?) -> Bool {
        guard let profile else { return true }
        guard let candidate = candidate?.lowercased() else { return false }
        return profile
            .lowercased()
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces) == candidate }
    }
}
