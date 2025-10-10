import SwiftUI
import YouTubeiOSPlayerHelper

/// 嵌入 YouTube iFrame 短片段試聽
struct YouTubePreviewView: UIViewRepresentable {
    let videoID: String
    let start: Int
    let end: Int

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.scrollView.isScrollEnabled = false
        web.allowsBackForwardNavigationGestures = false
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let raw = """
        https://www.youtube.com/embed/\(videoID)
        ?start=\(start)
        &end=\(end)
        &autoplay=1
        &controls=1
        &modestbranding=1
        &playsinline=1
        """
        let urlStr = raw.replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: urlStr) else { return }
        webView.load(URLRequest(url: url))
    }
}


struct YouTubeInlinePlayerView: UIViewRepresentable {
    let videoID: String
    let start: Int
    let end: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator

        // Load the initial video
        context.coordinator.currentVideoID = videoID
        playerView.load(
            withVideoId: videoID,
            playerVars: context.coordinator.playerVars(start: start, end: end)
        )

        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {
        // If videoID changed, reload
        if context.coordinator.currentVideoID != videoID {
            context.coordinator.currentVideoID = videoID
            uiView.load(
                withVideoId: videoID,
                playerVars: context.coordinator.playerVars(start: start, end: end)
            )
        }
    }

    class Coordinator: NSObject, YTPlayerViewDelegate {
        /// Keep track of which video is loaded
        var currentVideoID: String?

        /// Build the playerVars dictionary
        func playerVars(start: Int, end: Int) -> [String: Any] {
            return [
                "start":       NSNumber(value: start),
                "end":         NSNumber(value: end),
                "autoplay":    NSNumber(value: 1),
                "controls":    NSNumber(value: 1),
                "modestbranding": NSNumber(value: 1),
                "playsinline": NSNumber(value: 1),
                "rel":         NSNumber(value: 0),
                "fs":          NSNumber(value: 0)
            ]
        }

        /// Called when the player is ready; start playback
        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            playerView.playVideo()
        }

        /// Handle embed errors by falling back to external YouTube
        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            guard let vid = currentVideoID else { return }
            // Try YouTube App first
            if let appURL = URL(string: "youtube://\(vid)"),
               UIApplication.shared.canOpenURL(appURL) {
                UIApplication.shared.open(appURL)
            }
            else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(vid)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}
