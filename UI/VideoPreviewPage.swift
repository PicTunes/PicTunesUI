// VideoPreviewPage.swift
import SwiftUI
import AVKit

// MARK: - Player on preview page
struct VideoPreviewView: View {
    let videoURL: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
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
