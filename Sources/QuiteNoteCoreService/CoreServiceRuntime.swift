import QuiteNoteSharedStorage
import Foundation
import AppKit

/// Headless 常驻核心运行时。
final class CoreServiceRuntime {
    private let store: CoreClipboardStore
    private let configuration: CoreServiceConfiguration
    private var timer: Timer?
    private var lastChangeCount = 0
    private var status: CoreServiceStatus
    private let pasteboard = NSPasteboard.general

    init(store: CoreClipboardStore, configuration: CoreServiceConfiguration) {
        self.store = store
        self.configuration = configuration
        self.lastChangeCount = pasteboard.changeCount
        self.status = CoreServiceStatus(
            running: false,
            startedAt: Date(),
            capturedCount: 0,
            lastCapturedAt: nil,
            databasePath: store.storeURL.path,
            pid: ProcessInfo.processInfo.processIdentifier
        )
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        status.running = true
        status.startedAt = Date()
        persistStatus()

        let timer = Timer(timeInterval: configuration.pollInterval, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        status.running = false
        persistStatus()
    }

    @objc private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            persistStatus()
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if (try? store.insert(
            text: text,
            sourceApp: frontApp?.localizedName,
            sourceBundleID: frontApp?.bundleIdentifier
        )) == true {
            status.capturedCount += 1
            status.lastCapturedAt = Date()
        }
        persistStatus()
    }

    private func persistStatus() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(status) else { return }
        let url = configuration.stateURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
