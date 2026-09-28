//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

// TODO: enabled/disabled state
// TODO: scrubbing snapping behaviors
//       - chapter boundaries
//       - current running time
// TODO: show chapter title under preview image
//       - have max width, on separate offset track

extension VideoPlayer.PlaybackControls {

    struct PlaybackProgress: View {


        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager
        @EnvironmentObject
        private var scrubbedSecondsBox: PublishedBox<Duration>

        @State
        private var currentTranslation: CGPoint = .zero

        @State
        private var sliderSize: CGSize = .zero

        private var isScrubbing: Bool {
            get {
                containerState.isScrubbing
            }
            nonmutating set {
                containerState.isScrubbing = newValue
            }
        }

        private var isSlowScrubbing: Bool {
            isScrubbing && (currentTranslation.y >= 60)
        }

        private var previewXOffset: CGFloat {
            guard sliderSize.width.isFinite, sliderSize.width > 0 else { return 0 }

            let videoWidth = 85 * videoSizeAspectRatio
            let p = (sliderSize.width * scrubbedProgress) - (videoWidth / 2)
            return clamp(p, min: 0, max: max(0, sliderSize.width - videoWidth))
        }

        private var scrubbedProgress: Double {
            guard let runtime = manager.item.runtime, runtime > .zero else { return 0 }

            let progress = scrubbedSeconds / runtime
            guard progress.isFinite else { return 0 }

            return clamp(progress, min: 0, max: 1)
        }

        private var scrubbedSeconds: Duration {
            scrubbedSecondsBox.value
        }

        private var videoSizeAspectRatio: CGFloat {
            guard let videoPlayerProxy = manager.proxy as? any VideoMediaPlayerProxy else {
                return 1.77
            }

            let videoSize = videoPlayerProxy.videoSize.value
            guard videoSize.width.isFinite,
                  videoSize.height.isFinite,
                  videoSize.width > 0,
                  videoSize.height > 0
            else {
                return 1.77
            }

            let aspectRatio = videoSize.aspectRatio
            guard aspectRatio.isFinite else { return 1.77 }

            return clamp(aspectRatio, min: 0.25, max: 4)
        }

        private var sliderTotal: Double {
            let total = (manager.item.runtime ?? .zero).seconds
            guard total.isFinite, total > 0 else { return 1 }
            return total
        }

        @ViewBuilder
        private var liveIndicator: some View {
            Text(L10n.live)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    Capsule()
                        .fill(Color.gray)
                }
        }

        @ViewBuilder
        private var slowScrubbingIndicator: some View {
            HStack {
                Image(systemName: "backward.fill")
                Text(L10n.slowScrubbing.localizedCapitalized)
                Image(systemName: "forward.fill")
            }
            .font(.caption)
        }

        /// SweetFin : barre fine en pilule (4 pt, 6 pt au glisser), comme ElegantFin.
        /// ❌ Upstream l'étirait au glisser (`scaleEffect`) : avec les temps de part et
        /// d'autre, elle passait par-dessus.
        @ViewBuilder
        private var capsuleSlider: some View {
            AlternateLayoutView {
                EmptyHitTestView()
                    .frame(height: 6)
                    .trackingSize($sliderSize)
            } content: {
                SliderContainer(
                    value: $scrubbedSecondsBox.value.map(
                        getter: { $0.seconds },
                        setter: { .seconds($0) }
                    ),
                    total: sliderTotal
                )
                .translation($currentTranslation)
                .valueDamping(isSlowScrubbing ? 0.1 : 1)
                .gesturePadding(30)
                .onEditingChanged { newValue in
                    isScrubbing = newValue
                }
                .frame(height: isScrubbing ? 6 : 4)
                .foregroundStyle(manager.state == .loadingItem ? .gray : .primary)
            }
            .animation(.linear(duration: 0.05), value: scrubbedSeconds)
            .frame(height: 6)
            .disabled(manager.state == .loadingItem)
        }

        /// Temps restant, négatif : « -21:49 ».
        @ViewBuilder
        private var remainingTime: some View {
            if let runtime = manager.item.runtime {
                Text(.zero - (runtime - scrubbedSeconds), format: .runtime)
            } else {
                Text(verbatim: .emptyRuntime)
            }
        }

        var body: some View {
            Group {
                if manager.item.isLiveStream {
                    liveIndicator
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // SweetFin : « 0:42 ▬▬▬ -21:49 » sur une seule ligne, comme ElegantFin.
                    // L'aperçu s'accroche à la barre : ses coordonnées sont celles de la barre.
                    HStack(spacing: 12) {
                        Text(scrubbedSeconds, format: .runtime)

                        capsuleSlider
                            .overlay(alignment: .topLeading) {
                                if isScrubbing, let previewImageProvider = manager.playbackItem?.previewImageProvider {
                                    PreviewImageView(previewImageProvider: previewImageProvider)
                                        .aspectRatio(videoSizeAspectRatio, contentMode: .fit)
                                        .frame(height: 85)
                                        .posterBorder()
                                        .cornerRadius(ratio: 1 / 30, of: \.width)
                                        .offset(x: previewXOffset, y: -100)
                                }
                            }

                        remainingTime
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isScrubbing ? .primary : .secondary)
                }
            }
            .edgePadding(.horizontal)
            .frame(maxWidth: .infinity)
            .animation(.bouncy(duration: 0.4, extraBounce: 0.1), value: isScrubbing)
            .overlay(alignment: .bottom) {
                if isSlowScrubbing {
                    slowScrubbingIndicator
                        .offset(y: EdgeInsets.edgePadding * 2)
                        .transition(.opacity.animation(.linear(duration: 0.1)))
                }
            }
            .onChange(of: isSlowScrubbing) {
                guard isScrubbing else { return }
                UIDevice.impact(.soft)
            }
        }
    }
}
