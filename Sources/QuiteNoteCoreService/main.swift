import QuiteNoteSharedStorage
import Foundation
import AppKit

// 常驻核心第一阶段：headless 剪贴板采集 + 状态快照 + SIGTERM/SIGINT 优雅退出。
// 使用 `swift run QuiteNoteCoreService --database <sqlite>` 直接验证。
setbuf(stdout, nil)

func printUsage() {
    print("""
    QuiteNote Core Service

    USAGE:
      QuiteNoteCoreService --database <ClipboardHistory.sqlite> [--state <state.json>] [--interval <seconds>]
    """)
}

do {
    let configuration = try CoreServiceConfiguration.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let store = try CoreClipboardStore(databaseURL: configuration.databaseURL)
    let runtime = CoreServiceRuntime(store: store, configuration: configuration)

    let signals: [(Int32, String)] = [(SIGTERM, "SIGTERM"), (SIGINT, "SIGINT")]
    for signalNumber in signals.map({ $0.0 }) {
        signal(signalNumber) { number in
            // signal handler cannot safely touch Foundation; wake run loop through async source.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("CoreService.terminate"), object: NSNumber(value: number))
            }
        }
    }

    let terminateObserver = NotificationCenter.default.addObserver(
        forName: .init("CoreService.terminate"),
        object: nil,
        queue: .main
    ) { _ in
        runtime.stop()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    defer { NotificationCenter.default.removeObserver(terminateObserver) }

    runtime.start()
    print("QuiteNoteCoreService running")
    print("database: \(configuration.databaseURL.path)")
    print("state: \(configuration.stateURL.path)")
    CFRunLoopRun()
    print("QuiteNoteCoreService stopped")
} catch let error as CoreServiceError {
    FileHandle.standardError.write("QuiteNoteCoreService error: \(error)\n".data(using: .utf8)!)
    printUsage()
    exit(2)
} catch {
    FileHandle.standardError.write("QuiteNoteCoreService error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
