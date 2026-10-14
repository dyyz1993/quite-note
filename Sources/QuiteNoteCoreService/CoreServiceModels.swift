import Foundation

enum CoreServiceError: Error, Equatable {
    case invalidArguments(String)
    case databaseUnavailable(String)
}

/// 常驻核心状态快照，供 CLI/LaunchAgent/未来 IPC 查询。
struct CoreServiceStatus: Codable, Equatable {
    var running: Bool
    var startedAt: Date
    var capturedCount: Int
    var lastCapturedAt: Date?
    var databasePath: String
    var pid: Int32
}

/// 第三阶段最小核心配置。所有路径显式传入，避免 headless 进程误用 UI App 目录。
struct CoreServiceConfiguration {
    var databaseURL: URL
    var stateURL: URL
    var pollInterval: TimeInterval

    static func parse(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CoreServiceConfiguration {
        var databasePath: String?
        var statePath: String?
        var interval = 0.5

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value(after name: String, into sink: inout String?) throws {
                guard argument == name else { return }
                guard index + 1 < arguments.count else {
                    throw CoreServiceError.invalidArguments("\(name) requires a path")
                }
                sink = arguments[index + 1]
                index += 1
            }
            try value(after: "--database", into: &databasePath)
            try value(after: "--state", into: &statePath)
            if argument == "--interval" {
                guard index + 1 < arguments.count,
                      let parsed = Double(arguments[index + 1]),
                      parsed > 0,
                      parsed <= 5 else {
                    throw CoreServiceError.invalidArguments("--interval requires a value in (0, 5]")
                }
                interval = parsed
                index += 1
            }
            index += 1
        }

        guard let databasePath else {
            throw CoreServiceError.invalidArguments("--database is required")
        }
        let resolvedStatePath = statePath
            ?? environment["QN_CORE_STATE_PATH"]
            ?? NSTemporaryDirectory() + "/quitenote-core-state.json"

        return CoreServiceConfiguration(
            databaseURL: URL(fileURLWithPath: databasePath),
            stateURL: URL(fileURLWithPath: resolvedStatePath),
            pollInterval: interval
        )
    }
}
