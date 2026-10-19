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
            let windows = NSApp.orderedWindows.filter {
                $0.isVisible && $0.contentView != nil && $0.frame.width > 100 && $0.frame.height > 60
            }
            // Clipboard and launcher panels use .popUpMenu, above the main panel.
            if let window = windows.max(by: { $0.level.rawValue < $1.level.rawValue }),
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
