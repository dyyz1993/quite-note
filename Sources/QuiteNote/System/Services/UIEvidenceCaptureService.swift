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
            if let window = selected,
               let content = window.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: output, options: .atomic)
                }
            }
            try? FileManager.default.removeItem(at: request)
        }
    }
}
