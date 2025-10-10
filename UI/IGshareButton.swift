import SwiftUI
import UIKit

/// SwiftUI button: share to Instagram Stories
struct InstagramShareButton: View {
    enum Media {
        case image(UIImage)
        case video(URL)
    }

    @EnvironmentObject var theme: ThemeStore
    let media: Media

    // Inverted scheme for this page
    private var buttonBackground: Color {
        switch theme.kind {
        case .film:
            return Color(.black)                                       // film: black background
        case .anime:
            return Color(red: 210/255, green: 235/255, blue: 245/255) // anime: light-blue background
        }
    }
    private var buttonForeground: Color {
        switch theme.kind {
        case .film:
            return Color(red: 228/255, green: 199/255, blue: 112/255) // film: gold text
        case .anime:
            return Color(.black)                              // anime: black text
        }
    }
    var body: some View {
        Button(action: shareToStory) {
            Text("分享至限時動態")
                .frame(maxWidth: .infinity)
                .padding()
                .background(buttonBackground)
                .foregroundColor(buttonForeground)
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }

    private func shareToStory() {
        // Prepare pasteboard payload for Instagram Stories
        var item: [String: Any] = [:]
        let expiration = Date().addingTimeInterval(300) // 5 minutes

        switch media {
        case .image(let uiImage):
            guard let imgData = uiImage.pngData() else { return }
            item["com.instagram.sharedSticker.backgroundImage"] = imgData
        case .video(let url):
            guard let vidData = try? Data(contentsOf: url) else { return }
            item["com.instagram.sharedSticker.backgroundVideo"] = vidData
        }

        UIPasteboard.general.setItems([item], options: [.expirationDate: expiration])

        guard let url = URL(string: "instagram-stories://share?source_application=1377558706877252") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            print("Instagram is not installed or unsupported")
        }
    }
}
