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
        NotificationCenter.default.addObserver(self, selector: #selector(onBluetoothCapture(_:)), name: .bluetoothCaptureClipboard, object: nil)
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
        let hash = Self.sha1(text)
        if store.dedupEnabled, store.isRecentDuplicate(hash: hash, withinMinutes: 10) {
            store.updateTimestampForHash(hash)
            store.postToast("记录已去重，更新了时间戳", type: "info")
            return
        }
        lastHash = hash
        store.addRecord(content: text, hash: hash)
    }

    /// 计算文本 SHA1 用于去重
    static func sha1(_ text: String) -> String {
        let data = Data(text.utf8)
        return data.reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}
