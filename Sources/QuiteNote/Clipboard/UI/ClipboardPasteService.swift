import Foundation
import AppKit
import Carbon.HIToolbox

/// 剪贴板条目「粘贴回原应用」服务（PRD 6 / 15）
///
/// 流程：记住打开面板前的前台应用 → 写入剪贴板（登记自写抑制）→ 隐藏面板 →
/// 激活目标应用 → CGEvent 模拟 ⌘V → 回调。缺少辅助功能权限时降级为「仅复制」
/// （PRD：写入剪贴板并保持窗口打开）。
@MainActor
final class ClipboardPasteService {
    static let shared = ClipboardPasteService()

    /// 打开面板时记录的粘贴目标（此时面板尚未激活、用户还在原应用里）
    private(set) var targetApp: NSRunningApplication?

    private init() {}

    func rememberTargetApp() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        targetApp = front
    }

    /// 是否具备模拟粘贴的辅助功能权限
    static var canSimulatePaste: Bool { AXIsProcessTrusted() }

    /// 把条目内容写入系统剪贴板（图片写原图、文件写文件引用、其余写文本）
    func writeToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.type {
        case .image:
            if let virtualPath = entry.assetPath,
               let url = FileCoordinator.shared.resolveVirtualPath(virtualPath),
               let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            } else if let text = entry.ocrText {
                // 原图文件丢失时退化为 OCR 文本（PRD 7.5 图片文件丢失状态）
                pasteboard.setString(text, forType: .string)
            }
        case .file:
            if let path = entry.plainText {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    pasteboard.writeObjects([url as NSURL])
                } else {
                    pasteboard.setString(path, forType: .string)
                }
            }
        case .text, .link:
            if let text = entry.plainText {
                pasteboard.setString(text, forType: .string)
            }
        }

        ClipboardMonitor.suppressCurrentChange()
    }

    /// 粘贴结果
    enum PasteOutcome {
        case pasted
        /// 无辅助功能权限：内容已在剪贴板，未模拟按键
        case copiedOnly
        /// 没有可粘贴的目标应用（理论上极少）
        case noTarget
    }

    /// 粘贴到目标应用：写剪贴板 → 面板关闭 → 激活目标 → 模拟 ⌘V
    func paste(_ entry: ClipboardEntry, panelClose: () -> Void, completion: @escaping (PasteOutcome) -> Void) {
        writeToPasteboard(entry)

        let hasPermission = Self.canSimulatePaste
        let target = targetApp

        panelClose()

        // 降级：无辅助功能权限时不模拟按键（内容已在剪贴板）
        guard hasPermission else {
            completion(.copiedOnly)
            return
        }
        guard let target, !target.isTerminated else {
            completion(.noTarget)
            return
        }

        // 等面板收起、目标应用完成激活后再发按键
        target.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.postCommandV(to: target)
            completion(.pasted)
        }
    }

    /// 仅复制（右键/按钮）：写入剪贴板并保持窗口打开
    func copy(_ entry: ClipboardEntry) {
        writeToPasteboard(entry)
    }

    /// 模拟按下并松开 ⌘V（发给指定进程）
    private func postCommandV(to app: NSRunningApplication) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        func post(_ keyDown: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown) else { return }
            event.flags = .maskCommand
            event.postToPid(app.processIdentifier)
        }

        post(true)
        usleep(35_000) // 35ms，确保目标应用先收到 keyDown
        post(false)
    }
}
