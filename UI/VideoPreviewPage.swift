// VideoPreviewPage.swift
import SwiftUI
import AVKit

/// 可內嵌播放 + 全螢幕的影片預覽元件
struct VideoPreviewView: View {
    let videoURL: URL

    // 持有 Player，避免 View 重建就中斷
    @State private var player: AVPlayer = AVPlayer()
    @State private var showFullScreen = false

    var body: some View {
        // 內嵌播放器
        VideoPlayer(player: player)
            .background(Color.black)
            .overlay(fullscreenButton, alignment: .topTrailing) // 右上角全螢幕按鈕
            .onAppear {
                // 若沒有載入影片或來源不同，替換並播放
                if (player.currentItem as? AVPlayerItem)?.asset is AVURLAsset == false ||
                    (player.currentItem?.asset as? AVURLAsset)?.url != videoURL {
                    player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
                }
                player.play()
            }
            .onChange(of: videoURL) { newURL in
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
                player.play()
            }
            .onDisappear { player.pause() }
            // 用原生 AVPlayerViewController 做全螢幕
            .fullScreenCover(isPresented: $showFullScreen) {
                PlayerFullScreenView(player: player)
                    .ignoresSafeArea()
            }
    }

    // 右上角全螢幕按鈕
    private var fullscreenButton: some View {
        Button {
            showFullScreen = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
                .padding(10)
        }
        .accessibilityLabel("全螢幕播放")
    }
}

/// 以 AVPlayerViewController 呈現全螢幕，沿用同一個 AVPlayer（保留進度、靜音狀態等）
private struct PlayerFullScreenView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.modalPresentationStyle = .fullScreen
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player {
            vc.player = player
        }
        // 開啟全螢幕時若尚未播放，讓它自動播放
        if vc.player?.timeControlStatus != .playing {
            vc.player?.play()
        }
    }
}
// MARK: - Header card that follows theme colors
struct PreviewHeaderCard: View {
    @EnvironmentObject var theme: ThemeStore

    // Inputs
    let image: UIImage?
    let categoryLabel: String?
    let music: Music?
    let onGenerate: () -> Void

    // Style
    private let cardCorner: CGFloat = 22
    private let thumbSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 14) {
            // Left: selected image thumbnail
            Group {
                if let ui = image {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.c.cardBackground.opacity(0.5))
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(theme.c.textPrimary.opacity(0.7))
                    }
                }
            }
            .frame(width: thumbSize, height: thumbSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Middle: category + music
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("圖片標籤：")
                        .font(.subheadline).bold()
                        .foregroundColor(theme.c.textPrimary)
                    Text(displayLabel(categoryLabel))
                        .font(.subheadline)
                        .foregroundColor(theme.c.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let m = music {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音樂：\(m.title)")
                            .font(.footnote)
                            .foregroundColor(theme.c.textPrimary.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("作曲：\(m.composer)")
                            .font(.footnote)
                            .foregroundColor(theme.c.textPrimary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("片段：\(m.start.timeFormatted) - \(m.end.timeFormatted)")
                            .font(.footnote)
                            .foregroundStyle(theme.c.textPrimary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text("音樂：尚未選擇")
                        .font(.footnote)
                        .foregroundColor(theme.c.textPrimary.opacity(0.7))
                }
            }

            Spacer(minLength: 8)

            // Right: generate action
            Button(action: onGenerate) {
                Text("合成")
                    .font(.subheadline).bold()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.c.accentColor)     // follow theme
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .disabled(image == nil || music == nil)
            .opacity((image == nil || music == nil) ? 0.6 : 1.0)
        }
        .padding(16)
        .background(
            // Use themed card background instead of hard-coded purple
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(theme.c.cardBackground) // follows anime/film theme automatically
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: - Helpers

    private func displayLabel(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知" : trimmed
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append("影片預覽")
        parts.append("圖片標籤 \(displayLabel(categoryLabel))")
        if let m = music {
            parts.append("音樂 \(m.title) 作曲 \(m.composer)")
        } else {
            parts.append("尚未選擇音樂")
        }
        return parts.joined(separator: "，")
    }
}

#if DEBUG
struct PreviewHeaderCard_Previews: PreviewProvider {
    static var previews: some View {
        let sample = Music(
            title: "Clair de Lune",
            composer: "Debussy",
            start: 30, end: 60,
            link: "https://www.youtube.com/watch?v=CvFH_6DNRCY"
        )

        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack {
                PreviewHeaderCard(
                    image: UIImage(systemName: "photo")?.withTintColor(.white, renderingMode: .alwaysOriginal),
                    categoryLabel: "sunset",
                    music: sample,
                    onGenerate: {}
                )
                .padding()
                Spacer()
            }
        }
    }
}
#endif
