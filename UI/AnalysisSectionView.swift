// AnalysisSectionView.swift
import SwiftUI

/// Top big image + "圖片分析結果" + themed cards list
/// Long-press the section title to toggle the debug panel.
struct AnalysisSectionView: View {
    @EnvironmentObject var theme: ThemeStore

    let selectedImage: UIImage?
    let similarItems: [SimilarItem]
    let debugText: String?
    var onAnalyzeSimilar: ((SimilarItem) -> Void)? = nil

    @State private var showDebug = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
            }

            Text("圖片辨認結果")
                .font(.title3).bold()
                .foregroundColor(.black)
                .padding(.horizontal)
                .onLongPressGesture {
                    withAnimation { showDebug.toggle() }
                }

            if showDebug, let debug = debugText {
                Text(debug)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }

            if similarItems.isEmpty {
                Text("目前沒有相似圖片")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 16) {
                    ForEach(similarItems) { item in
                        SimilarCard(item: item, onAnalyze: onAnalyzeSimilar)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct SimilarCard: View {
    @EnvironmentObject var theme: ThemeStore
    let item: SimilarItem
    var onAnalyze: ((SimilarItem) -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.imageUrl) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15))
                        ProgressView()
                    }
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15))
                        Image(systemName: "photo").font(.title2).foregroundColor(.gray)
                    }
                @unknown default:
                    RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
            .cornerRadius(14)

            VStack(alignment: .leading, spacing: 6) {
                Text("圖片標籤：\(labelText(item.label))")
                    .font(.subheadline)
                    .foregroundColor(theme.c.textPrimary.opacity(0.85))
                Text("相似度：\(similarityPercent(item.score))")
                    .font(.footnote)
                    .foregroundColor(theme.c.textPrimary.opacity(0.85))
            }

            Spacer()

            Button(action: { onAnalyze?(item) }) {
                Text("分析音樂")
                    .font(.subheadline).bold()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(theme.c.accentColor)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
            }
            .disabled(onAnalyze == nil)
            .opacity(onAnalyze == nil ? 0.6 : 1.0)
        }
        .padding(16)
        .background(theme.c.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    private func labelText(_ label: String?) -> String {
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知" : trimmed
    }

    private func similarityPercent(_ score: Double) -> String {
        if score <= 1.0 {
            let clamped = Swift.max(0.0, Swift.min(1.0, score))
            let pct = Int(round(clamped * 100.0))
            return "\(pct)%"
        } else {
            let pct = Int(round(Swift.min(score, 100.0)))
            return "\(pct)%"
        }
    }
}
