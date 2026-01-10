import Foundation
import AppKit

/// 监控与采集系统剪贴板文本，支持去重策略并写入存储
final class ClipboardService {
    private let pasteboard = NSPasteboard.general
    private let store: RecordStore
    private var lastHash: String?

    /// 初始化服务并订阅蓝牙按钮事件
    init(store: RecordStore) {
        self.store = store
        NotificationCenter.default.addObserver(self, selector: #selector(onBluetoothCapture(_:)), name: QuiteNoteNotification.bluetoothCaptureClipboard.name, object: nil)
    }

    /// 蓝牙“采集剪贴板”事件处理
    @objc private func onBluetoothCapture(_ note: Notification) {
        captureClipboard()
    }

    /// 读取剪贴板并写入记录（空剪贴板与去重处理）
    func captureClipboard() {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.postLightHint("剪贴板无有效文本")
            return
        }

        let (sourceApp, sourceUrl) = Self.getSourceInfo()

        // 判断是否为纯URL，如果是则设置为.url类型
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordType: RecordType = Self.isPureURL(trimmedText) ? .url : .text

        let hash = Self.sha1(text)
        lastHash = hash
        store.addRecord(content: text, hash: hash, sourceApp: sourceApp, sourceUrl: sourceUrl, type: recordType)
    }

    /// 获取当前剪贴板内容的来源信息
    static func getSourceInfo() -> (app: String?, url: String?) {
        let pasteboard = NSPasteboard.general
        // 1. 尝试获取前端应用程序名
        // 注意：如果是通过全局快捷键触发，此时 frontmostApplication 通常是用户正在使用的 App
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName
        
        // 2. 尝试从剪贴板获取 URL（通常浏览器会放入 URL）
        var sourceUrl: String? = nil
        // 检查常见的 URL 类型
        let urlTypes: [NSPasteboard.PasteboardType] = [
            .init(rawValue: "public.url"),
            .URL,
            .init(rawValue: "WebURLsWithTitlesPboardType")
        ]
        
        for type in urlTypes {
            if let urlString = pasteboard.string(forType: type) {
                sourceUrl = urlString
                break
            }
        }
        
        return (appName, sourceUrl)
    }

    /// 判断是否为纯URL（用于识别URL类型记录）
    static func isPureURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 简单判断：以 http:// 或 https:// 开头
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    /// 计算文本 SHA1 用于去重
    static func sha1(_ text: String) -> String {
        let data = Data(text.utf8)
        return data.reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}
