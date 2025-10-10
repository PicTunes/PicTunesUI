import SwiftUI
import PhotosUI

struct UploadSectionView: View {
    @EnvironmentObject var theme: ThemeStore

    @Binding var pickerItem: PhotosPickerItem?
    @Binding var image: UIImage?
    let onAnalyze: () -> Void
    let isUploading: Bool

    // Inverted scheme: background is black; text follows theme
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
        VStack(spacing: 12) {
            HStack {
                Text("上傳圖片")
                    .font(.title2)
                    .foregroundColor(theme.c.textTitle)
                Spacer()
            }

            // Pick image button (black background + themed text)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("選擇圖片")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(buttonBackground)
                    )
                    .foregroundColor(buttonForeground)
            }
            .onChange(of: pickerItem) { _ in
                Task {
                    if let data = try? await pickerItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        image = ui
                    }
                }
            }

            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 250)
                    .cornerRadius(15)
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if image != nil {
                // Analyze button (black background + themed text)
                Button(action: onAnalyze) {
                    HStack(spacing: 8) {
                        if isUploading { ProgressView().tint(buttonForeground) }
                        Text("辨認圖片")
                            .foregroundColor(buttonForeground)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonBackground)
                    .cornerRadius(8)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 5)
        .padding(.horizontal)
    }
}
