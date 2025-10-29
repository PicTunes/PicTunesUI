// MusicRowView.swift
import SwiftUI

struct MusicRowView: View {
    @EnvironmentObject var theme: ThemeStore

    let music: Music
    @Binding var playingMusicID: UUID?
    var onSelect: ((Music) -> Void)? = nil

    private var isPlaying: Bool { playingMusicID == music.id }

    private var videoID: String? {
        Self.youtubeID(from: music.link)
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

    // MARK: - Colors tuned by theme
    private var titleColor: Color { theme.c.textPrimary }

    private var composerColor: Color {
        switch theme.kind {
        case .film:
            return Color.white.opacity(0.88)
        case .anime:
            return theme.c.textTitle
        }
    }

    private var timeColor: Color {
        switch theme.kind {
        case .film:
            return Color.white.opacity(0.65)
        case .anime:
            return theme.c.textTitle
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        .foregroundColor(titleColor)

                    Text(music.composer)
                        .font(.subheadline)
                        .foregroundColor(composerColor)

                    Text("\(music.start.timeFormatted) - \(music.end.timeFormatted)")
                        .font(.caption)
                        .foregroundColor(timeColor)
                }

                Spacer()

                if videoID != nil {
                    Button {
                        if isPlaying {
                            playingMusicID = nil
                        } else {
                            playingMusicID = music.id
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(theme.c.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                }
            }
            .padding(12)

            if isPlaying, let vid = videoID {
                YouTubeInlinePlayerView(videoID: vid, start: music.start, end: music.end)
                    .cornerRadius(8)
                    .frame(height: 180)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if let onSelect = onSelect {
                    HStack {
                        Spacer()
                        Button(action: { onSelect(music) }) {
                            Text("選擇")
                                .font(.subheadline).bold()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(theme.c.accentColor)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                        }
                        .accessibilityLabel("Select this track")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(theme.c.cardBackground)
        .cornerRadius(12)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}
