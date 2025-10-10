// PictunesApp.swift
// Theme system + global button style + page title color

import SwiftUI

// MARK: - Theme palette model
struct ThemeColors {
    // Surfaces and texts
    let background: Color
    let accentColor: Color
    let cardBackground: Color
    let textPrimary: Color
    let textTitle: Color
    let backgroundTransition1: Color
    let backgroundTransition2: Color

    // Page title color used on large titles in each tab
    let pageTitleColor: Color

    // Unified button colors for the whole app
    let buttonBackground: Color
    let buttonForeground: Color
}

// MARK: - Theme kind and palettes
enum ThemeKind: String, CaseIterable, Identifiable {
    case anime   // original anime/Disney/Pixar/anime database
    case film    // new movie theme songs / end-credit songs database
    var id: String { rawValue }

    /// Color palettes for each theme
    var colors: ThemeColors {
        switch self {
        case .anime:
            // Anime palette
            let lightBlue = Color(red: 210/255, green: 235/255, blue: 245/255)      // 淺藍（冰藍）
            return ThemeColors(
                background: Color(red: 20/255, green: 12/255, blue: 11/255),        // 主背景：極深暖黑
                accentColor: lightBlue,                                             // 強調色：淺藍
                cardBackground: Color(red: 159/255, green: 150/255, blue: 191/255), // 卡片底：灰紫
                textPrimary: .white,                                                // 主要文字：白
                textTitle: Color(red: 40/255, green: 39/255, blue: 44/255),         // 標題文字：深灰
                backgroundTransition1: Color(red: 161/255, green: 161/255, blue: 209/255), // 背景漸層1：藍紫
                backgroundTransition2: Color(red: 204/255, green: 230/255, blue: 230/255),  // 背景漸層2：淺青藍綠
                pageTitleColor: Color.black.opacity(0.85),                           // 頁面大標題：近黑
                buttonBackground: lightBlue,                                         // 全域按鈕底：淺藍
                buttonForeground: .black                                             // 全域按鈕字：黑
            )

        case .film:
            // Film palette
            let gold = Color(red: 228/255, green: 199/255, blue: 112/255)           // 金黃
            return ThemeColors(
                background: Color(red: 12/255, green: 12/255, blue: 14/255),        // 主背景：劇院炭黑
                accentColor: gold,                                                  // 強調色：金黃
                cardBackground: Color(red: 33/255, green: 32/255, blue: 38/255),    // 卡片底：石板深灰紫
                textPrimary: .white,                                                // 主要文字：白
                textTitle: Color(red: 35/255, green: 45/255, blue: 50/255),         // 卡片內標題：深藍灰
                backgroundTransition1: Color(red: 60/255, green: 58/255, blue: 71/255),    // 背景漸層1：石板紫灰
                backgroundTransition2: Color(red: 18/255, green: 18/255, blue: 20/255),    // 背景漸層2：近黑
                pageTitleColor: Color(red: 35/255, green: 45/255, blue: 50/255),     // 頁面大標題：深藍灰
                buttonBackground: .black,                                            // 全域按鈕底：黑
                buttonForeground: gold                                               // 全域按鈕字：金黃
            )
        }
    }
}

// MARK: - Theme store
final class ThemeStore: ObservableObject {
    @Published var kind: ThemeKind = .anime
    var c: ThemeColors { kind.colors }

    func apply(_ newKind: ThemeKind) {
        withAnimation(.easeInOut(duration: 0.35)) { kind = newKind }
        UserDefaults.standard.set(newKind.rawValue, forKey: "theme.kind")
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "theme.kind"),
           let loaded = ThemeKind(rawValue: raw) {
            kind = loaded
        }
    }
}

// MARK: - Global button styles
/// Solid pill button using the unified theme button colors
struct PillButtonStyle: ButtonStyle {
    let colors: ThemeColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(colors.buttonForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.buttonBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colors.buttonForeground.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Background-only variant for labels that are not Buttons (e.g., PhotosPicker's label)
struct PillButtonBackground: View {
    let colors: ThemeColors
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colors.buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colors.buttonForeground.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

// MARK: - App entry
@main
struct PicTunesApp: App {
    @StateObject private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .preferredColorScheme(.light)
                .accentColor(theme.c.accentColor)
        }
    }
}
