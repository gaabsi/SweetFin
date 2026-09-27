//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

extension DeviceProfile {

    /// EnhancedFin : VLC lit tout côté client → lecture directe dans 100 % des cas, le
    /// Pi ne transcode jamais. Ni conditions par codec, ni profil de transcodage, ni
    /// sous-titres incrustés.
    ///
    /// Output :
    /// - deviceProfile (DeviceProfile) : le profil envoyé à `PlaybackInfo`
    static func build() -> DeviceProfile {
        var deviceProfile = DeviceProfile()
        deviceProfile.directPlayProfiles = [DirectPlayProfile(type: .video)]
        deviceProfile.subtitleProfiles = vlcSubtitleProfiles
        return deviceProfile
    }

    @ArrayBuilder<SubtitleProfile>
    private static var vlcSubtitleProfiles: [SubtitleProfile] {
        SubtitleProfile.build(method: .embed) {
            SubtitleFormat.ass
            SubtitleFormat.cc_dec
            SubtitleFormat.dvbsub
            SubtitleFormat.dvdsub
            SubtitleFormat.libzvbi_teletextdec
            SubtitleFormat.mov_text
            SubtitleFormat.mpl2
            SubtitleFormat.pgssub
            SubtitleFormat.pjs
            SubtitleFormat.realtext
            SubtitleFormat.sami
            SubtitleFormat.ssa
            SubtitleFormat.subrip
            SubtitleFormat.subviewer
            SubtitleFormat.subviewer1
            SubtitleFormat.text
            SubtitleFormat.ttml
            SubtitleFormat.vplayer
            SubtitleFormat.vtt
            SubtitleFormat.xsub
        }

        /// - Note: Unmatched text subtitles (ex: VTT) are converted to the first option (subrip)
        SubtitleProfile.build(method: .external) {
            SubtitleFormat.subrip
            SubtitleFormat.ass
            SubtitleFormat.libzvbi_teletextdec
            SubtitleFormat.mpl2
            SubtitleFormat.pjs
            SubtitleFormat.realtext
            SubtitleFormat.sami
            SubtitleFormat.ssa
            SubtitleFormat.subviewer
            SubtitleFormat.subviewer1
            SubtitleFormat.text
            SubtitleFormat.ttml
            SubtitleFormat.vplayer
        }

        SubtitleProfile.build(method: .encode) {
            SubtitleFormat.dvbsub
            SubtitleFormat.dvdsub
            SubtitleFormat.pgssub
            SubtitleFormat.vtt
            SubtitleFormat.xsub
        }
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
