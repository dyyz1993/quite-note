import QuiteNoteSharedStorage
import Foundation
import AppKit

/// Headless 常驻核心运行时。
final class CoreServiceRuntime {
    private let store: CoreClipboardStore
    private let repository: ClipboardHistoryRepository
    private let configuration: CoreServiceConfiguration
    private var timer: Timer?
    private var lastChangeCount = 0
    private var lastHeartbeatPersistedAt: Date?
    private var status: CoreServiceStatus
    private let pasteboard = NSPasteboard.general

    init(store: CoreClipboardStore, configuration: CoreServiceConfiguration) {
        self.store = store
        self.repository = store.makeRepository()
        self.configuration = configuration
        self.lastChangeCount = pasteboard.changeCount
        self.status = CoreServiceStatus(
            running: false,
            startedAt: Date(),
            heartbeatAt: nil,
            capturedCount: 0,
            lastCapturedAt: nil,
            databasePath: store.storeURL.path,
            pid: ProcessInfo.processInfo.processIdentifier,
            lastError: nil
        )
    }

    func start() {
        guard timer == nil else { return }
        // Continue across UI-app launches: a resident core must not miss changes
        // merely because the app process started and initialized its own monitor.
        lastChangeCount = lastChangeCount > 0 ? lastChangeCount : pasteboard.changeCount
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
        status.running = true
        let now = Date()
        status.heartbeatAt = now
        let count = pasteboard.changeCount
        guard count != lastChangeCount else {
            persistStatusIfNeeded(heartbeat: now)
            return
        }
        lastChangeCount = count

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            persistStatusIfNeeded(heartbeat: now)
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        do {
            if try repository.insertText(
            text,
            sourceApp: frontApp?.localizedName,
            sourceBundleID: frontApp?.bundleIdentifier
            ).inserted {
                status.capturedCount += 1
                status.lastCapturedAt = Date()
            }
            status.lastError = nil
        } catch {
            status.lastError = "Clipboard write failed: \(error.localizedDescription)"
        }
        persistStatus()
    }

    private func persistStatus() {
        lastHeartbeatPersistedAt = status.heartbeatAt
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

    /// Avoid 172,800 idle atomic writes/day while keeping heartbeat age below 5s.
    private func persistStatusIfNeeded(heartbeat: Date, interval: TimeInterval = 3) {
        guard heartbeat.timeIntervalSince(lastHeartbeatPersistedAt ?? .distantPast) >= interval else { return }
        persistStatus()
    }
}
