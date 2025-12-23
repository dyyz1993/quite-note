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
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case layout = "layout"
    case box = "box"
    case rotateCcw = "rotate-ccw"
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
    case minus = "minus"
    case settings2 = "settings-2"
    case caseSensitive = "case-sensitive"
    case regex = "regex"
}

/// SwiftUI 包装，渲染 Lucide 图标（不使用 SF Symbols 回退）
struct LucideView: View {
    let name: IconName
    let size: CGFloat
    let color: Color

    /// 全局图标缓存，避免重复文件操作
    private static var iconCache = NSCache<NSString, NSImage>()
    /// 已扫描过的 Bundle 缓存
    private static var foundBundles: [Bundle] = []
    /// 是否已经执行过初始扫描
    private static var hasScannedBundles = false

    var body: some View {
        Group {
            if let img = getCachedImage(for: name.rawValue) {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundColor(color)
            } else if let ph = getCachedImage(for: "x") { // Lucide 内部占位
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

    /// 获取缓存或加载图标
    private func getCachedImage(for id: String) -> NSImage? {
        if let cached = Self.iconCache.object(forKey: id as NSString) {
            return cached
        }
        
        if let loaded = nsImage(for: id) {
            Self.iconCache.setObject(loaded, forKey: id as NSString)
            return loaded
        }
        
        return nil
    }

    /// 根据 lucideId 加载 NSImage
    private func nsImage(for lucideId: String) -> NSImage? {
        #if canImport(AppKit)
        // 1) 首选 Lucide 扩展按 id 访问
        if let img = NSImage.image(lucideId: lucideId) { return img }
        
        // 2) 尝试从已发现的 bundle 中加载
        for bundle in Self.foundBundles {
            if let img = bundle.image(forResource: NSImage.Name(lucideId)) {
                return img
            }
        }

        // 3) 直接从已知的 LucideIcons bundle 路径加载图标
        if let img = loadFromKnownBundle(lucideId) { return img }
        
        // 4) 只有在没有扫描过的情况下才执行全盘扫描（非常耗时）
        if !Self.hasScannedBundles {
            Self.hasScannedBundles = true
            return searchLucideImageInBuild(lucideId)
        }
        
        return nil
        #else
        return nil
        #endif
    }
    
    /// 直接从已知的 LucideIcons bundle 路径加载图标
    private func loadFromKnownBundle(_ id: String) -> NSImage? {
        // 首先尝试从 Resources 目录中的 icons.xcassets 加载
        if let imagePath = Bundle.main.path(forResource: id, ofType: "pdf", inDirectory: "icons.xcassets/\(id).imageset") {
            return NSImage(contentsOfFile: imagePath)
        }
        
        // 然后尝试从 Frameworks 目录中的 bundle 加载
        let lucideBundleURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/LucideIcons_LucideIcons.bundle")
        if let lucideBundle = Bundle(url: lucideBundleURL) {
            if !Self.foundBundles.contains(where: { $0.bundleURL == lucideBundleURL }) {
                Self.foundBundles.append(lucideBundle)
            }
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
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks")
        ]
        
        var foundImage: NSImage? = nil
        
        for root in candidates {
            if !fm.fileExists(atPath: root.path) { continue }
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in en {
                    if url.pathExtension == "bundle" && url.lastPathComponent.lowercased().contains("lucide") {
                        if let b = Bundle(url: url) {
                            // 记录发现的 bundle，以便下次直接使用
                            if !Self.foundBundles.contains(where: { $0.bundleURL == url }) {
                                Self.foundBundles.append(b)
                            }
                            if foundImage == nil {
                                foundImage = b.image(forResource: NSImage.Name(id))
                            }
                        }
                    }
                }
            }
        }
        return foundImage
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
