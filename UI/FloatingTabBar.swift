import SwiftUI

// MARK: 4 main view
enum PictunesTab {
    case upload
    case analysis
    case recommendation
    case preview
}

// MARK: function
struct FloatingTabBar: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var selectedTab: PictunesTab

    var body: some View {
        HStack {
            Button(action: { selectedTab = .upload }) {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                    Text("上傳").font(.caption)
                }
            }
            .foregroundColor(selectedTab == .upload ? theme.c.backgroundTransition1 : theme.c.textTitle)

            Spacer()

            Button(action: { selectedTab = .analysis }) {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text("辨認").font(.caption)
                }
            }
            .foregroundColor(selectedTab == .analysis ? theme.c.backgroundTransition1 : theme.c.textTitle)

            Spacer()

            Button(action: { selectedTab = .recommendation }) {
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                    Text("推薦").font(.caption)
                }
            }
            .foregroundColor(selectedTab == .recommendation ? theme.c.backgroundTransition1 : theme.c.textTitle)

            Spacer()

            Button(action: { selectedTab = .preview }) {
                VStack(spacing: 4) {
                    Image(systemName: "film")
                    Text("合成").font(.caption)
                }
            }
            .foregroundColor(selectedTab == .preview ? theme.c.backgroundTransition1 : theme.c.textTitle)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 16)
        .shadow(radius: 4)
    }
}

struct FloatingTabBar_Previews: PreviewProvider {
    @State static var currentTab: PictunesTab = .upload
    static var previews: some View {
        FloatingTabBar(selectedTab: $currentTab)
            .environmentObject(ThemeStore())
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
