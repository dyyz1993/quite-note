import Foundation
import AppKit
import Darwin

/// 应用诊断中心：文件日志 + 崩溃捕获 + 主线程卡死看门狗 + 会话异常退出检测
///
/// 目的：把"闪退/卡死/异常退出"这类事后难以复现的问题留下可溯源的记录。
///
/// 日志位置: ~/Library/Application Support/com.quitenote.app/Logs/
///   - app-YYYY-MM-DD.log   日常运行日志（按天滚动，保留 7 天）
///   - crash-<时间戳>.log    崩溃记录（信号/未捕获异常 + 崩溃线程调用栈）
///   - session.state        会话标记（running / clean_exit / crashed），
///                           下次启动时据此判断上次是否异常退出
///
/// 使用方式（业务代码请用这些静态方法，不要再裸 print 关键链路）：
///   DiagnosticCenter.info("Screenshot", "截图会话开始")
///   DiagnosticCenter.error("Save", "导出失败: \(error)")
///
/// 局限（已知并接受）：信号处理器内使用 Swift API 非严格 async-signal-safe，
/// 极端情况下崩溃记录本身可能写不完整；需要工业级崩溃报告时再引入 PLCrashReporter。
final class DiagnosticCenter {

    static let shared = DiagnosticCenter()

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let logDirectory: URL
    private let fileLock = NSLock()
    private var fileHandle: FileHandle?
    private var currentLogFileName: String = ""

    /// 会话标记文件（区分正常退出 / 异常退出 / 崩溃）
    var sessionStateURL: URL { logDirectory.appendingPathComponent("session.state") }

    // MARK: - 看门狗状态

    private let watchdogLock = NSLock()
    private var lastHeartbeat = Date()
    private var hangEpisodeReported = false
    private var hangStartTime: Date?

    private(set) var isStarted = false

    // MARK: - 崩溃捕获所需的静态路径（信号处理器闭包不能捕获上下文）

    private static var crashDirectoryPath: String = ""

    init(logDirectory: URL? = nil) {
        if let dir = logDirectory {
            self.logDirectory = dir
        } else if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            // 数据隔离红线：测试进程的日志也进隔离目录，不污染生产日志
            self.logDirectory = URL(fileURLWithPath: testRoot, isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            // 按 Bundle ID 分目录：开发变体（com.quitenote.app.dev）日志与生产分开
            let dirName = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
            self.logDirectory = appSupport.appendingPathComponent(dirName, isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
        }
    }

    // MARK: - 启动

    func start() {
        guard !isStarted else { return }
        isStarted = true

        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        Self.crashDirectoryPath = logDirectory.path

        cleanupOldLogs()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let macos = ProcessInfo.processInfo.operatingSystemVersionString
        writeLine(level: .info, category: "App", message: "会话启动 — 版本 \(version), macOS \(macos), pid \(ProcessInfo.processInfo.processIdentifier)")

        checkPreviousSession()
        markSessionRunning()
        installCrashHandlers()
        startWatchdog()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleWillTerminate() {
        writeLine(level: .info, category: "App", message: "应用正常退出")
        try? "clean_exit".write(toFile: sessionStateURL.path, atomically: true, encoding: .utf8)
    }

    // MARK: - 对外日志 API

    static func debug(_ category: String, _ message: String) { shared.writeLine(level: .debug, category: category, message: message) }
    static func info(_ category: String, _ message: String) { shared.writeLine(level: .info, category: category, message: message) }
    static func warning(_ category: String, _ message: String) { shared.writeLine(level: .warning, category: category, message: message) }
    static func error(_ category: String, _ message: String) { shared.writeLine(level: .error, category: category, message: message) }

    /// 日志目录（设置界面/导出诊断用）
    var logDirectoryURL: URL { logDirectory }

    // MARK: - 慢操作埋点（用户反馈排查链路）

    /// 性能日志阈值：同步慢操作超过此值落 [PERF] 日志
    static let perfLogThreshold: TimeInterval = 0.3

    /// 同步慢操作埋点：仅当耗时超过 threshold 才落 [PERF] 日志（避免刷屏）。
    /// 用户反馈排查时在 app-*.log 里 grep "[PERF]" 即可看到所有慢操作。
    @discardableResult
    static func measure<T>(_ category: String, _ name: String,
                           threshold: TimeInterval = DiagnosticCenter.perfLogThreshold,
                           _ block: () throws -> T) rethrows -> T {
        let start = DispatchTime.now()
        let result = try block()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if ms >= threshold * 1000 {
            shared.writeLine(level: .warning, category: "PERF",
                             message: "慢操作 \(category)/\(name)：\(String(format: "%.0f", ms))ms（阈值 \(Int(threshold * 1000))ms）")
        }
        return result
    }

    /// 异步操作埋点句柄：begin 后在完成时调 end()，超阈值才落日志
    struct MeasureToken {
        let category: String
        let name: String
        let threshold: TimeInterval
        let start: DispatchTime
        var extra: String = ""

        func end() {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            guard ms >= threshold * 1000 else { return }
            let suffix = extra.isEmpty ? "" : " · \(extra)"
            shared.writeLine(level: .warning, category: "PERF",
                             message: "慢操作 \(category)/\(name)：\(String(format: "%.0f", ms))ms（阈值 \(Int(threshold * 1000))ms）\(suffix)")
        }
    }

    static func beginMeasure(_ category: String, _ name: String,
                             threshold: TimeInterval = DiagnosticCenter.perfLogThreshold) -> MeasureToken {
        MeasureToken(category: category, name: name, threshold: threshold, start: DispatchTime.now())
    }

    // MARK: - 文件写入

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func writeLine(level: LogLevel, category: String, message: String) {
        let ts = Self.timestampFormatter.string(from: Date())
        let line = "\(ts) [\(level.rawValue)][\(category)] \(message)\n"

        fileLock.lock()
        defer { fileLock.unlock() }

        // DateFormatter 非线程安全，全部在锁内使用
        let fileName = "app-\(Self.dayFormatter.string(from: Date())).log"
        if fileName != currentLogFileName {
            fileHandle?.closeFile()
            let url = logDirectory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            fileHandle = FileHandle(forWritingAtPath: url.path)
            fileHandle?.seekToEndOfFile()
            currentLogFileName = fileName
        }
        guard let data = line.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    /// 清理过期日志（app-*.log 保留 keepDays 天；crash-*.log 一并纳入清理）
    @discardableResult
    func cleanupOldLogs(keepDays: Int = 7) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        var removed = 0
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("app-") || name.hasPrefix("crash-") else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
                removed += 1
            }
        }
        return removed
    }

    /// 读取今日日志尾部（反馈"附带运行日志"用）。
    /// 日志规范（见 AGENTS.md）本身不落用户内容：仅类别/级别/计数/尺寸/长度/哈希/来源 App 等打点信息，
    /// 因此这里只做行数与字节截断，不做内容脱敏——新增日志埋点时必须继续遵守该规范。
    func recentLogs(maxLines: Int = 150, maxBytes: Int = 32 * 1024) -> String {
        fileLock.lock()
        defer { fileLock.unlock() }

        fileHandle?.synchronizeFile()
        let fileName = currentLogFileName ?? "app-\(Self.dayFormatter.string(from: Date())).log"
        let url = logDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return "" }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        var output = lines.joined(separator: "\n")
        if output.utf8.count > maxBytes {
            output = String(output.suffix(maxBytes))
        }
        return output
    }

    // MARK: - 会话异常退出检测

    private func markSessionRunning() {
        try? "running".write(toFile: sessionStateURL.path, atomically: true, encoding: .utf8)
    }

    /// 检查上一次会话的退出方式
    /// - Returns: true 表示上次会话是异常退出（崩溃或被强制退出）
    @discardableResult
    func checkPreviousSession() -> Bool {
        guard let raw = try? String(contentsOf: sessionStateURL, encoding: .utf8) else { return false }
        let state = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state {
        case "running":
            writeLine(level: .error, category: "Session", message: "检测到上次会话异常退出（无正常退出标记，可能是崩溃或被强制退出）——请对照 Logs 目录下相近时间戳的 crash-*.log")
            return true
        case "crashed":
            writeLine(level: .error, category: "Session", message: "检测到上次会话崩溃退出，崩溃详情见上一次的 crash-*.log")
            return true
        default:
            return false
        }
    }

    // MARK: - 崩溃捕获

    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticCenter.writeCrashRecord(
                reason: "未捕获异常: \(exception.name.rawValue) — \(exception.reason ?? "无描述")",
                stack: exception.callStackSymbols.joined(separator: "\n")
            )
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            signal(sig) { sig in
                DiagnosticCenter.handleCrashSignal(sig)
            }
        }
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT (abort，多为 fatalError/数组越界等致命错误)"
        case SIGSEGV: return "SIGSEGV (非法内存访问)"
        case SIGBUS: return "SIGBUS (总线错误)"
        case SIGILL: return "SIGILL (非法指令)"
        case SIGFPE: return "SIGFPE (算术异常)"
        case SIGTRAP: return "SIGTRAP (陷阱，Swift 运行时 fatalError 通常走这里)"
        default: return "信号 \(sig)"
        }
    }

    /// 信号处理器：写崩溃记录后恢复默认处理并重新触发，保持系统崩溃语义
    fileprivate static func handleCrashSignal(_ sig: Int32) {
        writeCrashRecord(reason: signalName(sig), stack: Thread.callStackSymbols.joined(separator: "\n"))
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// 写崩溃记录（未捕获异常与信号共用）
    /// 防覆盖：未捕获异常处理器先执行（信息最全），信号处理器后执行会覆盖同名文件——
    /// 用此标记保证只写一次（实测 2026-08-17 的布局崩溃因此丢失了异常原因）
    fileprivate static var crashRecordWritten = false

    fileprivate static func writeCrashRecord(reason: String, stack: String) {
        guard !crashRecordWritten else { return }
        crashRecordWritten = true
        guard !crashDirectoryPath.isEmpty else {
            crashRecordWritten = false  // 目录未就绪时允许 start() 后再写
            return
        }
        let path = crashDirectoryPath + "/crash-\(Int(Date().timeIntervalSince1970)).log"
        let content = """
        ===== 崩溃捕获 =====
        时间: \(Date())
        原因: \(reason)
        进程: QuiteNote pid \(getpid())

        崩溃线程调用栈:
        \(stack)

        （提示：主线程卡死类问题请看同目录 app-*.log 中 [Hang] 记录）
        """
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        try? "crashed".write(toFile: crashDirectoryPath + "/session.state", atomically: true, encoding: .utf8)
    }

    // MARK: - 主线程卡顿/卡死看门狗（分级）

    /// 卡顿分级阈值：超过 minor 归为"卡顿"（[PERF]，滚动/渲染类），超过 major 归为"卡死"（[Hang]）
    static let stallMinorThreshold: TimeInterval = 0.5
    static let stallMajorThreshold: TimeInterval = 5.0

    private func startWatchdog() {
        // 主线程心跳：每 0.25s 打点（可感知 0.5s 级卡顿）；主线程被阻塞时打点自然停止
        func beat() {
            watchdogLock.lock()
            lastHeartbeat = Date()
            watchdogLock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { beat() }
        }
        DispatchQueue.main.async { beat() }

        // 看门狗线程：每 0.25s 监测心跳滞后，episode 状态机分级上报：
        //   滞后 > 5s → 立即 [Hang] ERROR（卡死，只报一次）
        //   episode（>0.5s 的滞后段）恢复时 → [PERF] WARN 记录持续时长（卡顿）
        Thread.detachNewThread {
            var perfEpisodeStart: Date?
            while true {
                Thread.sleep(forTimeInterval: 0.25)
                self.watchdogLock.lock()
                let lag = Date().timeIntervalSince(self.lastHeartbeat)
                self.watchdogLock.unlock()

                // 卡死级（立即报，一次）
                if lag > Self.stallMajorThreshold {
                    if !self.hangEpisodeReported {
                        self.hangEpisodeReported = true
                        self.hangStartTime = Date().addingTimeInterval(-lag)
                        self.writeLine(level: .error, category: "Hang", message: "⚠️ 主线程无响应 \(Int(lag)) 秒（疑似卡死，超过 \(Int(Self.stallMajorThreshold)) 秒阈值）")
                    }
                }

                // 卡顿级 episode 跟踪（0.5s ~ 5s 的滞后段）
                if lag > Self.stallMinorThreshold {
                    if perfEpisodeStart == nil {
                        perfEpisodeStart = Date().addingTimeInterval(-lag)
                    }
                } else if lag < Self.stallMinorThreshold * 0.6, let start = perfEpisodeStart {
                    perfEpisodeStart = nil
                    let duration = Date().timeIntervalSince(start)
                    if duration >= Self.stallMinorThreshold {
                        self.writeLine(level: .warning, category: "PERF",
                                       message: "主线程卡顿约 \(String(format: "%.1f", duration))s（滚动/渲染类卡顿，看此时间段前后的其他日志定位来源）")
                    }
                }

                // 卡死 episode 恢复（保留原语义）
                if self.hangEpisodeReported && lag < 2.0 {
                    self.hangEpisodeReported = false
                    if let start = self.hangStartTime {
                        let duration = Date().timeIntervalSince(start)
                        self.hangStartTime = nil
                        self.writeLine(level: .warning, category: "Hang", message: "✅ 主线程恢复响应，本次卡死持续约 \(Int(duration)) 秒")
                    }
                }
            }
        }
    }
}
