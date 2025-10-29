// RecommendationSectionView.swift
//
// Unified recommendation list that supports theme colors and single-source playback control.
// - If the link is a YouTube watch URL (has ?v=...), embed YouTubeInlinePlayerView.
// - Otherwise, use AVPlayer to play an audio clip between start~end seconds.
// - Uses a single `playingMusicID` to ensure only one item plays at a time.
// RecommendationSectionView.swift
import SwiftUI
import AVFoundation

final class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var clipStart: Double = 0
    private var clipEnd: Double = 0

    var isSetup: Bool { player != nil }

    func setup(urlString: String, start: Int, end: Int) {
        guard let url = URL(string: urlString) else { return }
        player = AVPlayer(url: url)
        clipStart = Double(start)
        clipEnd = Double(end)
        addObserver()
    }

    func playPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            let startTime = CMTime(seconds: clipStart, preferredTimescale: 600)
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        guard let player = player else { return }
        player.pause()
        let startTime = CMTime(seconds: clipStart, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        isPlaying = false
    }

    private func addObserver() {
        guard let player = player else { return }
        removeObserver()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = CMTimeGetSeconds(time)
            if current >= self.clipEnd {
                self.stop()
            }
        }
    }

    private func removeObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    deinit {
        removeObserver()
    }
}

struct RecommendationSectionView: View {
    @EnvironmentObject var theme: ThemeStore
    let musicList: [Music]
    @State private var playingMusicID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("推薦音樂")
                .font(.title2)
                .foregroundColor(theme.c.accentColor)

            ForEach(musicList) { track in
                PreviewCardView(
                    music: track,
                    playingMusicID: $playingMusicID
                )
            }
        }
        .padding(.horizontal)
    }
}

struct PreviewCardView: View {
    @EnvironmentObject var theme: ThemeStore

    let music: Music
    @Binding var playingMusicID: UUID?

    @StateObject private var audioMgr = AudioPlayerManager()

    private var isPlaying: Bool { playingMusicID == music.id }
    private var videoID: String? { Self.youtubeID(from: music.link) }
    private var isYouTube: Bool { videoID != nil }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                if isPlaying {
                    AudioVisualizerView(barCount: 4, updateInterval: 0.15)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 30))
                        .foregroundColor(theme.c.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title)
                        .font(.headline)
                        .foregroundColor(theme.c.textPrimary)
                    Text(music.composer)
                        .font(.subheadline)
                        .foregroundColor(theme.c.textTitle)
                    Text("\(music.start.timeFormatted) - \(music.end.timeFormatted)")
                        .font(.caption)
                        .foregroundColor(theme.c.textTitle)
                }

                Spacer()

                Button {
                    handleTap()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(theme.c.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if isPlaying, let vid = videoID {
                YouTubeInlinePlayerView(videoID: vid, start: music.start, end: music.end)
                    .frame(height: 180)
                    .cornerRadius(10)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(theme.c.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .onChange(of: playingMusicID) { _ in
            if playingMusicID != music.id, audioMgr.isPlaying {
                audioMgr.stop()
            }
        }
    }

    private func handleTap() {
        if isPlaying {
            if !isYouTube {
                audioMgr.stop()
            }
            playingMusicID = nil
        } else {
            if isYouTube {
                playingMusicID = music.id
            } else {
                if !audioMgr.isSetup {
                    audioMgr.setup(urlString: music.link, start: music.start, end: music.end)
                }
                playingMusicID = music.id
                audioMgr.playPause()
            }
        }
    }

    private static func youtubeID(from link: String) -> String? {
        guard let comp = URLComponents(string: link) else { return nil }

        if let host = comp.host, host.contains("youtu.be") {
            let parts = comp.path.split(separator: "/").map(String.init)
            return parts.first
        }
        if let host = comp.host, host.contains("youtube.com") {
            if let v = comp.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
            let parts = comp.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0].lowercased() == "shorts" {
                return parts[1]
            }
        }
        return nil
    }
}

struct AudioVisualizerView: View {
    @EnvironmentObject var theme: ThemeStore

    var barCount: Int = 5
    var updateInterval: TimeInterval = 0.2

    @State private var heights: [CGFloat] = []
    @State private var timerID = UUID()

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { idx in
                Capsule()
                    .fill(theme.c.accentColor)
                    .frame(width: 4, height: heights.indices.contains(idx) ? heights[idx] : 4)
            }
        }
        .onAppear {
            heights = Array(repeating: 4, count: barCount)
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        let id = UUID()
        timerID = id
        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { t in
            if id != timerID {
                t.invalidate()
                return
            }
            withAnimation(.linear(duration: updateInterval)) {
                for i in heights.indices {
                    heights[i] = CGFloat.random(in: 8...30)
                }
            }
        }
    }

    private func stopTimer() {
        timerID = UUID()
    }
}
