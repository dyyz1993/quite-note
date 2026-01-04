import SwiftUI

/// 记录缩略图组件
struct RecordThumbnailView: View {
    let record: Record
    let size: CGFloat
    
    @State private var thumbnailURL: URL?
    
    var body: some View {
        Group {
            if let url = thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: size, height: size)
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .background(Color.themeHoverLight)
        .cornerRadius(ThemeRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                .stroke(Color.themeBorderSubtle, lineWidth: 1)
        )
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let urlString = record.sourceUrl else { return }
        
        // 1. 解析虚拟路径或原始路径
        guard let sourceURL = FileCoordinator.shared.resolveVirtualPath(urlString) else { return }
        
        // 2. 异步获取缩略图
        ThumbnailGenerator.shared.getThumbnailURLAsync(for: sourceURL) { url in
            self.thumbnailURL = url
        }
    }
    
    private var fallbackIcon: some View {
        LucideView(name: typeIconLucide, size: size * 0.5, color: .themeTextTertiary)
            .frame(width: size, height: size)
    }
    
    private var typeIconLucide: IconName {
        switch record.type {
        case .folder: return .folder
        case .file: return .paperclip
        case .text: return .fileText
        case .image: return .image
        case .video: return .video
        case .screenshot: return .camera
        }
    }
}
