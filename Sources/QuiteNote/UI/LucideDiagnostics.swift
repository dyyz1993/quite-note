import Foundation
import AppKit
#if canImport(LucideIcons)
import LucideIcons
#elseif canImport(LucideIconsSwift)
import LucideIconsSwift
#endif

/// 运行时检测 Lucide 图标资源是否可用
/// - 检查 note.jsx 中使用的全部图标 id
/// - 在控制台输出每个图标是否加载成功，以及汇总统计
struct LucideDiagnostics {
    /// 执行检测并打印结果
    static func run() {
        #if canImport(LucideIcons) || canImport(LucideIconsSwift)
        let ids = [
            "bluetooth","bluetooth-connected","bluetooth-off",
            "copy","chevron-right","clipboard","activity","x","cpu","settings","arrow-left",
            "sparkles","bot","check","save","align-left","trash-2","star","search",
            "maximize-2","database","link","zap","clock","app-window-mac"
        ]
        var missing: [String] = []
        for name in ids {
            // 使用与 Icon.swift 相同的加载逻辑检查图标
            let ok = checkIconAvailability(name)
            print("[Lucide] \(name): \(ok ? "OK" : "MISSING")")
            if !ok { missing.append(name) }
        }
        if missing.isEmpty {
            print("[Lucide] 所有图标均可加载，共 \(ids.count) 个")
        } else {
            print("[Lucide] 缺失 \(missing.count) 个图标：\(missing.joined(separator: ", "))")
        }
        #else
        print("[Lucide] 模块未加载：LucideIcons/LucideIconsSwift 均不可导入")
        #endif
    }
    
    /// 使用与 Icon.swift 相同的加载逻辑检查图标可用性
    private static func checkIconAvailability(_ lucideId: String) -> Bool {
        #if canImport(AppKit)
        // 1) 首选 Lucide 扩展按 id 访问
        if NSImage.image(lucideId: lucideId) != nil { return true }
        
        // 2) 直接从已知的 LucideIcons bundle 路径加载图标
        if loadFromKnownBundle(lucideId) != nil { return true }
        
        // 3) swift run 场景：手动扫描 .build 目录下的 Lucide 资源 bundle
        return searchLucideImageInBuild(lucideId) != nil
        #else
        return false
        #endif
    }
    
    /// 直接从已知的 LucideIcons bundle 路径加载图标
    private static func loadFromKnownBundle(_ id: String) -> NSImage? {
        let lucideBundleURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/LucideIcons_LucideIcons.bundle")
        if let lucideBundle = Bundle(url: lucideBundleURL) {
            return lucideBundle.image(forResource: NSImage.Name(id))
        }
        return nil
    }
    
    /// 在 swift run 的 .build 目录中寻找 Lucide 资源 bundle 并加载图标
    private static func searchLucideImageInBuild(_ id: String) -> NSImage? {
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

