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
            let ok = NSImage.image(lucideId: name) != nil
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
}

