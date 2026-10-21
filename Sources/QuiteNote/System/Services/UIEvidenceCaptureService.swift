import AppKit
import ScreenCaptureKit

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
                //    CGWindowListCreateImage 对 layer-backed 面板可能返回非 nil 的
                //    纯黑图，需要拒绝并落到 layer 渲染层。
                if let cg = CGWindowListCreateImage(
                    .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]),
                   !Self.isSolidBlank(cg) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: output, options: .atomic)
                        wrote = true
                    }
                }
                // 2) layer 树离屏渲染：cacheDisplay 只走 drawRect，SwiftUI 的
                //    hosting 内容在 CA 层，离屏位图会得到纯背景色。
                if !wrote, let layer = content.layer,
                   let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds),
                   let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: 0, y: content.bounds.height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                    if let data = bitmap.representation(using: .png, properties: [:]),
                       let cg = bitmap.cgImage {
                        wrote = !Self.isSolidBlank(cg)
                    }
                }
                // 2.5) App 进程内调系统 screencapture：macOS 13 上子进程继承父
                //    进程的 Screen Recording 授权，且走真实 WindowServer 合成。
                if !wrote {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    proc.arguments = ["-x", "-m", output.path]
                    try? proc.run()
                    proc.waitUntilExit()
                    wrote = proc.terminationStatus == 0 && Self.checkNonBlank(output)
                }
                // 3) ScreenCaptureKit 全屏单帧：SwiftUI 内容只有 WindowServer 合成器
                //    能拍出来；App 自身持有 Screen Recording 授权，SCK 走真实合成。
                if !wrote {
                    wrote = Self.captureDisplayWithScreenCaptureKit(to: output)
                }
                // 4) 旧路径兜底（AppKit 自绘内容仍有效）
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

    /// ScreenCaptureKit 全屏单帧（macOS 14+）。同步包装，超时 5 秒。
    private static func captureDisplayWithScreenCaptureKit(to url: URL) -> Bool {
        if #available(macOS 14.0, *) {
            let semaphore = DispatchSemaphore(value: 0)
            var succeeded = false
            // SCShareableContent / SCScreenshotManager 是 nonisolated——Task 跑在
            // 并发池即可；@MainActor 会与下方主线程 semaphore.wait 互锁。
            Task {
                defer { semaphore.signal() }
                guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                      let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return }
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: url, options: .atomic)
                    succeeded = true
                }
            }
            _ = semaphore.wait(timeout: .now() + 5)
            return succeeded
        }
        return false
    }

    /// 帧是否为纯色空内容（全黑/全背景都算）。
    private static func checkNonBlank(_ path: URL) -> Bool {
        guard let image = NSImage(contentsOf: path),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return false }
        return !isSolidBlank(rep)
    }

    /// CGWindowListCreateImage 偶发返回整幅同色（黑）的位图；抽样判断是否空内容。
    private static func isSolidBlank(_ image: CGImage) -> Bool {
        isSolidBlank(NSBitmapImageRep(cgImage: image))
    }

    private static func isSolidBlank(_ rep: NSBitmapImageRep) -> Bool {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return true }
        var minLuminance = Double.greatestFiniteMagnitude
        var maxLuminance = -Double.greatestFiniteMagnitude
        for i in 0..<64 {
            let x = (i * 8 + 3) % width
            let y = (i * 13 + 5) % height
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let r = Double(color.redComponent)
            let g = Double(color.greenComponent)
            let b = Double(color.blueComponent)
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
        }
        return (maxLuminance - minLuminance) < 0.02
    }
}
