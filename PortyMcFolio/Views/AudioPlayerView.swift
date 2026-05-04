import SwiftUI
import AVKit

/// `NSViewRepresentable` wrapping `AVPlayerView` with `.inline` controls.
/// Used for audio slides in the carousel — SwiftUI's `VideoPlayer` renders
/// audio-only tracks as an ugly black pane, so we drop to AppKit for this
/// specific case.
struct AudioPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = AVPlayer(url: url)
        v.controlsStyle = .inline
        v.showsFullScreenToggleButton = false
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        // Recreate the player only when the url changes — avoids resetting
        // the scrub position on every re-render.
        let currentURL = (v.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            v.player = AVPlayer(url: url)
        }
    }
}
