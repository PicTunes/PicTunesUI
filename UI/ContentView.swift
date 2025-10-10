// ContentView.swift
import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var theme: ThemeStore

    // Tabs
    @State private var selectedTab: PictunesTab = .upload

    // Picker and selected image
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    // Networking state
    @State private var isUploading = false
    @State private var showMockBanner = false
    @State private var lastErrorMessage: String? = nil

    // Server-driven data
    @State private var analysisLabel: String? = nil
    @State private var musicList: [Music] = []
    @State private var similarItems: [SimilarItem] = []
    @State private var generatedVideoURL: URL?

    // Playback state for recommendation list
    @State private var playingMusicID: UUID? = nil

    // The category user picked on Analysis page
    @State private var chosenSimilar: SimilarItem? = nil

    // New: remember which track user selected for generation
    @State private var chosenTrack: Music? = nil

    // Layout constants
    private let tabBarBottomPadding: CGFloat = 36
    private let hintLiftAboveTab: CGFloat = 72

    private var currentDomain: RecommendationDomain {
        theme.kind == .anime ? .anime : .film
    }

    // MARK: - Dynamic hint banners
    private var contextHint: String? {
        switch selectedTab {
        case .upload:
            if selectedImage == nil { return "尚未選擇圖片，點「上傳」挑選照片" }
        case .analysis:
            if selectedImage == nil {
                return "尚未選擇圖片，請先至「上傳」頁挑選照片"
            } else if similarItems.isEmpty && !isUploading {
                return "尚未辨認，請按「辨認」進行圖片辨認"
            }
        case .recommendation:
            if chosenSimilar == nil {
                return "請先在「辨認」頁點選一張類別卡片"
            } else if musicList.isEmpty && !isUploading {
                return "尚未取得推薦，請重新分析或檢查網路/後端"
            }
        case .preview:
            if generatedVideoURL == nil {
                return "尚未產出影片，請按「合成」或在推薦頁按「選擇」"
            }
        }
        return nil
    }

    private var bannersToShow: [String] {
        var msgs: [String] = []
        if showMockBanner { msgs.append("後端未連線，顯示模擬資料") }
        if let hint = contextHint { msgs.append(hint) }
        return msgs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    theme.c.backgroundTransition2,
                    Color.white,
                    theme.c.backgroundTransition1
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: theme.kind)

            VStack(spacing: 10) {
                // Domain segmented control
                DomainToggle(
                    domain: Binding(
                        get: { currentDomain },
                        set: { newVal in theme.apply(newVal == .anime ? .anime : .film) }
                    )
                )
                .padding(.top, 8)
                .padding(.horizontal)

                Group {
                    switch selectedTab {
                    case .upload:
                        uploadView
                    case .analysis:
                        analysisView
                    case .recommendation:
                        recommendationView
                    case .preview:
                        previewView
                    }
                }
                .padding(.bottom, 100)
            }

            // Floating tab bar
            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.bottom, tabBarBottomPadding)

            // Stacked hint pills above the tab bar
            if !bannersToShow.isEmpty {
                VStack(spacing: 8) {
                    ForEach(bannersToShow, id: \.self) { msg in
                        HintPill(text: msg)
                    }
                }
                .padding(.bottom, tabBarBottomPadding + hintLiftAboveTab)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(theme.c.background)
        .edgesIgnoringSafeArea(.bottom)
        .alert("辨認失敗", isPresented: Binding(
            get: { lastErrorMessage != nil },
            set: { _ in lastErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastErrorMessage ?? "")
        }
        .onChange(of: theme.kind) { _ in
            // Reset states when switching domain
            musicList = []
            playingMusicID = nil
            chosenSimilar = nil
            generatedVideoURL = nil
            chosenTrack = nil
        }
    }

    // MARK: - Upload tab
    private var uploadView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("PicTunes：上傳（\(domainTitle)）")
                    .font(.title).bold()
                    .foregroundStyle(theme.c.pageTitleColor)
                    .padding(.top)

                UploadSectionView(
                    pickerItem: $pickerItem,
                    image: $selectedImage,
                    onAnalyze: {
                        analyzeImage()
                        selectedTab = .analysis
                    },
                    isUploading: isUploading
                )
                Spacer(minLength: 50)
            }
        }
    }

    // MARK: - Analysis tab
    private var analysisView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("PicTunes：圖片辨認（\(domainTitle)）")
                    .font(.title).bold()
                    .foregroundStyle(theme.c.pageTitleColor)
                    .padding(.top)

                AnalysisSectionView(
                    selectedImage: selectedImage,
                    similarItems: similarItems,
                    debugText: PictunesService.shared.debugSummary,
                    onAnalyzeSimilar: { item in
                        self.chosenSimilar = item
                        self.selectedTab = .recommendation
                    }
                )

                Spacer(minLength: 50)
            }
        }
    }

    // MARK: - Recommendation tab
    private var recommendationView: some View {
        VStack(spacing: 16) {
            Text("PicTunes：推薦（\(domainTitle)）")
                .font(.title).bold()
                .foregroundStyle(theme.c.pageTitleColor)
                .padding(.top)

            if let picked = chosenSimilar {
                ChosenCategoryCard(
                    item: picked,
                    onChange: { self.selectedTab = .analysis }
                )
                .padding(.horizontal)
            }

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(musicList) { track in
                        MusicRowView(
                            music: track,
                            playingMusicID: $playingMusicID,
                            onSelect: { selected in
                                // Keep your existing behavior: generate immediately,
                                // but also remember which track user selected.
                                chosenTrack = selected
                                selectAndRender(track: selected)
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)

            Spacer()
        }
    }

    // MARK: - Preview tab
    private var previewView: some View {
        VStack(spacing: 16) {
            Text("PicTunes：合成（\(domainTitle)）")
                .font(.title).bold()
                .foregroundStyle(theme.c.pageTitleColor)
                .padding(.top)

            // >>> 新增：放在「標題」與「播放器」之間的卡片 <<<
            PreviewHeaderCard(
                image: selectedImage,
                categoryLabel: chosenSimilar?.label,
                music: chosenTrack,
                onGenerate: { regenerateFromPreview() } // tap to generate again
            )
            .padding(.horizontal)

            if let url = generatedVideoURL {
                VideoPreviewView(videoURL: url)
                    .frame(height: 280)
                    .padding(.horizontal)

                InstagramShareButton(media: .video(url))
                    .padding(.horizontal)
            } else if selectedImage != nil {
                // Placeholder area for player
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 280)
                    .overlay(
                        Image(systemName: "play.slash.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                    )
                    .padding(.horizontal)

                InstagramShareButton(media: .image(selectedImage!))
                    .padding(.horizontal)
            } else {
                Text("請先於「上傳」與「辨認」完成流程，再至「推薦」選擇音樂。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Actions
    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isUploading = true
        showMockBanner = false
        lastErrorMessage = nil

        PictunesService.shared.upload(image: image, domain: currentDomain) { result in
            isUploading = false

            withAnimation {
                showMockBanner = PictunesService.shared.lastRequestUsedMock
            }

            switch result {
            case .success(let response):
                self.analysisLabel = response.label
                self.musicList = response.music
                self.similarItems = response.similar ?? []
                self.generatedVideoURL = response.videoUrl
            case .failure(let err):
                self.analysisLabel = "辨認錯誤"
                self.musicList = []
                self.similarItems = []
                self.generatedVideoURL = nil
                self.lastErrorMessage = err.localizedDescription
            }
        }
    }

    /// Existing behavior: generate right after selecting a track on the recommendation page.
    private func selectAndRender(track: Music) {
        guard let img = selectedImage else {
            lastErrorMessage = "尚未選擇圖片，無法產生影片"
            return
        }
        isUploading = true
        lastErrorMessage = nil

        // Your backend signature: generateVideo(image:domain:track:completion)
        PictunesService.shared.generateVideo(image: img, domain: currentDomain, track: track) { result in
            isUploading = false
            switch result {
            case .success(let url):
                self.generatedVideoURL = url
                self.selectedTab = .preview
            case .failure(let err):
                self.lastErrorMessage = err.localizedDescription
            }
        }
    }

    /// New: re-generate from preview page card
    private func regenerateFromPreview() {
        guard let track = chosenTrack else {
            lastErrorMessage = "尚未選擇音樂"
            return
        }
        selectAndRender(track: track)
    }

    // MARK: - Helpers
    private var domainTitle: String {
        switch currentDomain {
        case .anime: return "動漫"
        case .film:  return "電影"
        }
    }
}

// MARK: - Domain segmented toggle
private struct DomainToggle: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var domain: RecommendationDomain

    var body: some View {
        HStack(spacing: 10) {
            Text("推薦資料庫")
                .font(.subheadline).bold()
                .foregroundColor(theme.c.textTitle)

            Picker("", selection: $domain) {
                Text("動漫").tag(RecommendationDomain.anime)
                Text("電影").tag(RecommendationDomain.film)
            }
            .pickerStyle(.segmented)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.c.accentColor.opacity(0.6), lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: theme.kind)
    }
}

//
// MARK: - Hint pill component
//
private struct HintPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).bold()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.95))
            .foregroundColor(.black)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
            .accessibilityLabel(text)
    }
}

//
// MARK: - Inline ChosenCategoryCard
//
struct ChosenCategoryCard: View {
    @EnvironmentObject var theme: ThemeStore
    let item: SimilarItem
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
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
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                @unknown default:
                    RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
            .cornerRadius(14)

            // Texts
            VStack(alignment: .leading, spacing: 6) {
                Text("目前使用的類別")
                    .font(.caption).bold()
                    .foregroundColor(theme.c.textPrimary.opacity(0.8))

                Text(labelText(item.label))
                    .font(.headline)
                    .foregroundColor(theme.c.textPrimary)

                Text("相似度 \(similarityPercent(item.score))")
                    .font(.caption)
                    .foregroundColor(theme.c.textPrimary.opacity(0.7))
            }

            Spacer()

            // Reselect button
            Button(action: onChange) {
                Text("重新選擇")
                    .font(.subheadline).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.c.accentColor)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
            }
        }
        .padding(16)
        .background(theme.c.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    // Helpers
    private func labelText(_ label: String?) -> String {
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知" : trimmed
    }

    private func similarityPercent(_ score: Double) -> String {
        if score <= 1.0 {
            let clamped = max(0.0, min(1.0, score))
            let pct = Int(round(clamped * 100.0))
            return "\(pct)%"
        } else {
            let pct = Int(round(min(score, 100.0)))
            return "\(pct)%"
        }
    }
}
