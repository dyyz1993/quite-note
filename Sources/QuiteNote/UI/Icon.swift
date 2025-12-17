import SwiftUI
#if canImport(LucideIcons)
import LucideIcons
#elseif canImport(LucideIconsSwift)
import LucideIconsSwift
#endif

/// 图标名称枚举，保持与 note.jsx 中 lucide-react 用法一致
enum IconName: String {
    case activity = "activity"
    case clipboard = "clipboard"
    case settings = "settings"
    case arrowLeft = "arrow-left"
    case sparkles = "sparkles"
    case bot = "bot"
    case check = "check"
    case save = "save"
    case fileText = "file-text"
    case rss = "rss"
    case trash2 = "trash-2"
    case star = "star"
    case starOff = "star-off"
    case search = "search"
    case minimize2 = "minimize-2"
    case maximize2 = "maximize-2"
    case database = "database"
    case link = "link"
    case zap = "zap"
    case clock = "clock"
    case bluetooth = "bluetooth"
    case bluetoothOff = "bluetooth-off"
    case bluetoothConnected = "bluetooth-connected"
    case chevronRight = "chevron-right"
    case copy = "copy"
    case x = "x"
    case cpu = "cpu"
    case appWindowMac = "app-window-mac"
    case refreshCw = "refresh-cw"
    case eye = "eye"
    case eyeOff = "eye-off"
    case alertTriangle = "alert-triangle"
    case filter = "filter"
    case slidersHorizontal = "sliders-horizontal"
    case funnelPlus = "funnel-plus"
    case eraser = "eraser"
    case circleX = "circle-x"
}

/// SwiftUI 包装，渲染 Lucide 图标（不使用 SF Symbols 回退）
struct LucideView: View {
    let name: IconName
    let size: CGFloat
    let color: Color

    var body: some View {
        Group {
            if let img = nsImage(for: name.rawValue) {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundColor(color)
            } else if let ph = nsImage(for: "x") { // Lucide 内部占位
                Image(nsImage: ph)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundColor(color)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
            }
        }
    }

    /// 根据 lucideId 加载 NSImage
    private func nsImage(for lucideId: String) -> NSImage? {
        #if canImport(AppKit)
        // 1) 首选 Lucide 扩展按 id 访问
        if let img = NSImage.image(lucideId: lucideId) { return img }
        
        // 2) 直接从已知的 LucideIcons bundle 路径加载图标
        if let img = loadFromKnownBundle(lucideId) { return img }
        
        // 3) swift run 场景：手动扫描 .build 目录下的 Lucide 资源 bundle
        return searchLucideImageInBuild(lucideId)
        #else
        return nil
        #endif
    }
    
    /// 直接从已知的 LucideIcons bundle 路径加载图标
    private func loadFromKnownBundle(_ id: String) -> NSImage? {
        let lucideBundleURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/LucideIcons_LucideIcons.bundle")
        if let lucideBundle = Bundle(url: lucideBundleURL) {
            return lucideBundle.image(forResource: NSImage.Name(id))
        }
        return nil
    }

    /// 在 swift run 的 .build 目录中寻找 Lucide 资源 bundle 并加载图标
    private func searchLucideImageInBuild(_ id: String) -> NSImage? {
        let fm = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build"),
            Bundle.main.bundleURL,
            // 显式检查 Frameworks 目录
        Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks")
        ]
        for root in candidates {
            if !fm.fileExists(atPath: root.path) { continue }
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in en {
                    if url.pathExtension == "bundle" && url.lastPathComponent.lowercased().contains("lucide") {
                        if let b = Bundle(url: url), let img = b.image(forResource: NSImage.Name(id)) {
                            return img
                        }
                    }
                }
            }
        }
        return nil
    }

}

/// 图标 + 文本组合标签，统一尺寸与对齐
struct LucideLabel: View {
    let icon: IconName
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            LucideView(name: icon, size: size, color: color)
            Text(text)
        }
    }
}
