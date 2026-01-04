import SwiftUI

/// 记录缩略图组件
struct RecordThumbnailView: View {
    let record: Record
    let size: CGFloat
    
    @State private var loadedImage: NSImage?
    
    var body: some View {
        Group {
            if let nsImage = loadedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
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
        // 如果已经加载过，不再重复加载
        if loadedImage != nil { return }

        guard let urlString = record.sourceUrl else { return }
        
        // 1. 解析虚拟路径或原始路径
        guard let sourceURL = FileCoordinator.shared.resolveVirtualPath(urlString) else { return }
        
        // 2. 异步获取缩略图
        ThumbnailGenerator.shared.getThumbnailURLAsync(for: sourceURL) { url in
            guard let url = url else { return }
            
            // 3. 预加载图片到内存，避免 AsyncImage 的一闪一闪
            DispatchQueue.global(qos: .userInteractive).async {
                if let nsImage = NSImage(contentsOf: url) {
                    DispatchQueue.main.async {
                        self.loadedImage = nsImage
                    }
                }
            }
        }
    }
    
    private var fallbackIcon: some View {
        LucideView(name: typeIconLucide, size: size * 0.5, color: .themeTextTertiary)
            .frame(width: size, height: size)
    }
    
    private var typeIconLucide: IconName {
        record.type.icon
    }
}
