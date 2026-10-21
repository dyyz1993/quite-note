import AppKit

// The isolated Dev smoke run can snapshot its own window without Screen Recording TCC.
// Requests and output stay inside the run's evidence directory.
final class UIEvidenceCaptureService {
    private let requests: URL
    private let frames: URL
    private var timer: Timer?

    init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard Bundle.main.bundleIdentifier == "com.quitenote.app.dev",
              CommandLine.arguments.contains("--ui-smoke-run"),
              environment["QN_TEST_STORAGE_ROOT"] != nil,
              let directory = environment["QN_UI_EVIDENCE_DIR"] else { return nil }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        requests = root.appendingPathComponent("requests", isDirectory: true)
        frames = root.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.processRequests()
        }
    }

    private func processRequests() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: requests, includingPropertiesForKeys: nil
        ) else { return }
        for request in entries where request.pathExtension == "request" {
            let filename = request.deletingPathExtension().lastPathComponent
            guard filename.hasPrefix("frame-") else { continue }
            let output = frames.appendingPathComponent(filename + ".png")
            let windows = NSApp.windows.filter {
                $0.isVisible && $0.contentView != nil && $0.frame.width > 100 && $0.frame.height > 60
            }
            let preferred = windows.first { window in
                if filename.contains("clipboard") { return window.frame.width >= 700 }
                if filename.contains("launcher") { return window.frame.width >= 620 && window.frame.width < 700 }
                return false
            }
            let selected = preferred ?? windows.max(by: { $0.level.rawValue < $1.level.rawValue })
            let inventory = windows.map { window -> [String: Any] in
                ["number": window.windowNumber, "width": Double(window.frame.width),
                 "height": Double(window.frame.height), "level": window.level.rawValue,
                 "key": window.isKeyWindow, "selected": window === selected]
            }
            if let data = try? JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted]) {
                try? data.write(to: frames.appendingPathComponent(filename + ".windows.json"), options: .atomic)
            }
            if let window = selected, let content = window.contentView {
                var wrote = false
                // 1) 按窗口 ID 合成抓取（含 SwiftUI 的 CA 层内容）。抓取对象是
                //    本 App 自己的窗口，不依赖 Screen Recording TCC——runner 会话
                //    没有 TCC，外部 screencapture 与 CGDisplayCreateImage 全部
                //    返回 nil（错题本 2026-10-15/10-21）。
                if let cg = CGWindowListCreateImage(
                    .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: output, options: .atomic)
                        wrote = data != nil
                    }
                }
                // 2) layer 树离屏渲染：cacheDisplay 只走 drawRect，SwiftUI 的
                //    hosting 内容在 CA 层，离屏位图会得到纯背景色。
                if !wrote, let layer = content.layer,
                   let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds),
                   let context = bitmap.graphicsContext {
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: 0, y: content.bounds.height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: output, options: .atomic)
                        wrote = data != nil
                    }
                }
                // 3) 旧路径兜底（AppKit 自绘内容仍有效）
                if !wrote, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: output, options: .atomic)
                    }
                }
            }
            try? FileManager.default.removeItem(at: request)
        }
    }
}
