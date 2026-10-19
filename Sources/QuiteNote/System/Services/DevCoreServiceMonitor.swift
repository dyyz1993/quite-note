import Foundation

/// Dev 常驻核心状态快照。字段与 QuiteNoteCoreService 的状态文件保持一致。
struct DevCoreServiceStatus: Codable, Equatable {
    var running: Bool
    var startedAt: Date
    var heartbeatAt: Date?
    var capturedCount: Int
    var lastCapturedAt: Date?
    var databasePath: String
    var pid: Int32
    var lastError: String?
}

enum DevCoreServiceMonitorError: LocalizedError, Equatable {
    case notDevBuild
    case stateUnreadable
    case serviceUnavailable
    case stateStale

    var errorDescription: String? {
        switch self {
        case .notDevBuild:
            return "常驻核心仅允许在 Dev 变体中启用"
        case .stateUnreadable:
            return "核心状态文件缺失或损坏"
        case .serviceUnavailable:
            return "LaunchAgent 未加载，请先运行 tools/manage-quitenote-dev-core.sh install"
        case .stateStale:
            return "核心心跳超时"
        }
    }
}

/// 只观察和重启 launchd 已托管的 Dev Core，绝不直接拉起第二个进程。
@MainActor
final class DevCoreServiceMonitor: ObservableObject {
    static let label = "com.quitenote.app.dev.core"

    @Published private(set) var snapshot: DevCoreServiceStatus?
    @Published private(set) var launchdPID: Int32?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRestarting = false
    @Published private(set) var lastStateUpdatedAt: Date?
    @Published private(set) var isHeartbeatStale = false
    private let heartbeatTimeout: TimeInterval

    private(set) var isDevBuild = false
    private let stateURL: URL
    private let domain: String
    private var timer: Timer?

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        userID: UInt32 = getuid(),
        stateURL: URL? = nil,
        heartbeatTimeout: TimeInterval = 5
    ) {
        self.isDevBuild = bundleIdentifier == "com.quitenote.app.dev"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        self.stateURL = stateURL
            ?? support.appendingPathComponent("com.quitenote.app.dev/CoreService/state.json", isDirectory: false)
        self.domain = "gui/\(userID)"
        self.heartbeatTimeout = heartbeatTimeout
    }

    deinit {
        timer?.invalidate()
    }

    func startObserving() {
        guard isDevBuild else { return }
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard isDevBuild else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        do {
            launchdPID = try launchctlPID()
            guard launchdPID != nil else {
                throw DevCoreServiceMonitorError.serviceUnavailable
            }
            let parsed = try Self.readStatus(at: stateURL)
            guard let heartbeat = parsed.heartbeatAt,
                   Date().timeIntervalSince(heartbeat) <= heartbeatTimeout else {
                throw DevCoreServiceMonitorError.stateStale
            }
            snapshot = parsed
            isHeartbeatStale = false
            lastStateUpdatedAt = Date()
        } catch {
            snapshot = nil
            launchdPID = nil
            lastStateUpdatedAt = nil
            lastError = error.localizedDescription
        }
    }

    func restart() {
        guard isDevBuild else {
            lastError = DevCoreServiceMonitorError.notDevBuild.localizedDescription
            return
        }
        do {
            isRestarting = true
            defer { isRestarting = false }
            _ = try runLaunchctl(["print", "\(domain)/\(Self.label)"])
            _ = try runLaunchctl(["kickstart", "-k", "\(domain)/\(Self.label)"])
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    nonisolated static func readStatus(at url: URL) throws -> DevCoreServiceStatus {
        guard let data = try? Data(contentsOf: url) else {
            throw DevCoreServiceMonitorError.stateUnreadable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let status = try? decoder.decode(DevCoreServiceStatus.self, from: data) else {
            throw DevCoreServiceMonitorError.stateUnreadable
        }
        return status
    }

    private func launchctlPID() throws -> Int32? {
        let output = try runLaunchctl(["print", "\(domain)/\(Self.label)"])
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid = ") else { continue }
            let value = trimmed.dropFirst("pid = ".count).trimmingCharacters(in: .whitespaces)
            return Int32(value)
        }
        return nil
    }

    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ""
        }
        // launchctl can block indefinitely if its service lookup wedges; keep UI
        // and tests bounded rather than waiting on waitUntilExit.
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            throw DevCoreServiceMonitorError.serviceUnavailable
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw DevCoreServiceMonitorError.serviceUnavailable
        }
        return output
    }
}
