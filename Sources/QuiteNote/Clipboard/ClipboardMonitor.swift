import Foundation
import AppKit
import UniformTypeIdentifiers

/// 剪贴板自动捕获监控（PRD 5）
///
/// 轮询 NSPasteboard.general.changeCount（0.5s，主线程——NSPasteboard 非线程安全），
/// 内容类型识别优先级：文件引用 > 图片 > 链接 > 文本。
/// 自身写入剪贴板（粘贴服务等）通过 suppressChangeCount 登记跳过，避免回环捕获。
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    /// 应用自身写剪贴板产生的 changeCount 集合（捕获时跳过并移除）
    private static var selfWriteChangeCounts: Set<Int> = []
    private static let lock = NSLock()

    /// 单条文本最大存储长度（1MB，防御性截断）
    static let maxTextLength = 1_048_576
    /// 图片最大存储字节数（50MB，超过跳过捕获）
    static let maxImageBytes = 52_428_800

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        // 重启时重置基线，不捕获启动前残留的剪贴板内容
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: 0.5, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DiagnosticCenter.info("Clipboard", "剪贴板监控已启动")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        DiagnosticCenter.info("Clipboard", "剪贴板监控已停止")
    }

    func restart() {
        stop()
        start()
    }

    /// 按当前设置同步运行状态（偏好变化时调用）
    func syncWithPreferences() {
        let active = Self.shouldCapture
        if active && timer == nil {
            start()
        } else if !active && timer != nil {
            stop()
        }
    }

    /// 是否处于可捕获状态（总开关 + 已完成首次引导 + 未暂停）
    static var shouldCapture: Bool {
        let prefs = PreferencesManager.shared
        guard prefs.clipboardHistoryEnabled, prefs.clipboardOnboarded else { return false }
        if let until = prefs.clipboardPausedUntil, Date() < until { return false }
        return true
    }

    // MARK: - 自写抑制

    /// 应用自身写剪贴板后调用：登记该次 changeCount，监控将跳过这次变化
    static func suppressCurrentChange() {
        let count = NSPasteboard.general.changeCount
        lock.lock()
        defer { lock.unlock() }
        selfWriteChangeCounts.insert(count)
    }

    // MARK: - 轮询

    @objc @MainActor private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // 自写抑制：跳过自己写入的变化
        Self.lock.lock()
        let isSelfWrite = Self.selfWriteChangeCounts.remove(count) != nil
        Self.lock.unlock()
        if isSelfWrite { return }

        captureNow(recordReason: "auto")
    }

    /// 立即采集当前剪贴板（轮询触发 / 手动触发共用）
    /// - Note: 必须在主线程调用（NSPasteboard 限制）
    @MainActor func captureNow(recordReason reason: String) {
        guard Self.shouldCapture else { return }

        let types = pasteboard.types ?? []
        let hasFileURL = types.contains(.fileURL)
        let hasImage = types.contains(where: { Self.imageTypes.contains($0) })
        let text = pasteboard.string(forType: .string)
        let detectorType = ClipboardTypeDetector.detect(hasFileURL: hasFileURL, hasImage: hasImage, text: text)

        // 记录内容开关（PRD 8.2）
        let prefs = PreferencesManager.shared
        switch detectorType {
        case .text where !prefs.clipboardRecordText,
             .link where !prefs.clipboardRecordLink,
             .image where !prefs.clipboardRecordImage,
             .file where !prefs.clipboardRecordFile:
            return
        default:
            break
        }

        // 来源应用与排除列表（PRD 8.6：密码管理器等敏感 App 不记录）
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let appName = prefs.clipboardRecordSourceApp ? frontApp?.localizedName : nil
        if let bundleID, Self.isExcluded(bundleID: bundleID) {
            DiagnosticCenter.info("Clipboard", "来源应用 \(bundleID) 在排除列表，跳过捕获")
            return
        }

        switch detectorType {
        case .file:
            captureFile(bundleID: bundleID, appName: appName)
        case .image:
            captureImage(bundleID: bundleID, appName: appName)
        case .text, .link:
            captureText(text: text, type: detectorType, bundleID: bundleID, appName: appName, pasteboardURL: readPasteboardURL())
        }
    }

    // MARK: - 分类型捕获

    @MainActor private func captureText(text: String?, type: ClipboardEntryType, bundleID: String?, appName: String?, pasteboardURL: String?) {
        guard var content = text,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if content.count > Self.maxTextLength {
            content = String(content.prefix(Self.maxTextLength))
        }

        let urlText: String?
        if type == .link {
            urlText = pasteboardURL ?? content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            urlText = nil
        }

        let entry = ClipboardEntry(
            type: type,
            plainText: content,
            sourceURL: urlText,
            sourceApp: appName,
            sourceBundleID: bundleID,
            contentHash: ClipboardService.sha1(content),
            byteSize: Int64(content.utf8.count)
        )
        ClipboardHistoryStore.shared.insertOrUpdate(entry)
    }

    @MainActor private func captureFile(bundleID: String?, appName: String?) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              let url = urls.first else { return }

        let path = url.path
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            size = attrs[.size] as? Int64 ?? 0
        }

        let entry = ClipboardEntry(
            type: .file,
            plainText: path,
            sourceApp: appName,
            sourceBundleID: bundleID,
            contentHash: ClipboardService.sha1("file:\(path):\(size)"),
            byteSize: size
        )
        ClipboardHistoryStore.shared.insertOrUpdate(entry)
    }

    @MainActor private func captureImage(bundleID: String?, appName: String?) {
        // NSPasteboard 读取必须主线程；拿到数据后重活（PNG 编码/落盘/缩略图）全部后台
        guard let image = readImageFromPasteboard() else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            guard png.count <= Self.maxImageBytes else {
                DiagnosticCenter.warning("Clipboard", "图片过大（\(png.count / 1024 / 1024)MB），跳过捕获")
                return
            }

            let hash = ClipboardService.sha1(png.baseEncodedString)
            // 落盘原图（FileCoordinator 独立子目录）+ 预生成缩略图
            var virtualPath: String?
            if let stored = try? FileCoordinator.shared.storeImage(image, type: .clipboard) {
                virtualPath = FileCoordinator.shared.convertToVirtualPath(from: stored)
                _ = ThumbnailGenerator.shared.getThumbnailURL(for: stored)
            }

            let enableOCR = PreferencesManager.shared.clipboardEnableOCR
            let entry = ClipboardEntry(
                type: .image,
                plainText: nil,
                sourceApp: appName,
                sourceBundleID: bundleID,
                contentHash: hash,
                assetPath: virtualPath,
                ocrStatus: enableOCR ? .waiting : .disabled,
                byteSize: Int64(png.count)
            )

            Task { @MainActor in
                ClipboardHistoryStore.shared.insertOrUpdate(entry)
            }
        }
    }

    // MARK: - 读取辅助

    private func readImageFromPasteboard() -> NSImage? {
        for type in Self.imageTypes {
            if let data = pasteboard.data(forType: type) {
                if let image = NSImage(data: data) { return image }
            }
        }
        return nil
    }

    private func readPasteboardURL() -> String? {
        for type in [NSPasteboard.PasteboardType(rawValue: "public.url"), .URL] {
            if let s = pasteboard.string(forType: type) { return s }
        }
        return nil
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]

    static func isExcluded(bundleID: String) -> Bool {
        let list = PreferencesManager.shared.clipboardExcludedBundleIDs
        return list.contains { bundleID == $0 || bundleID.hasPrefix("\($0).") }
    }
}

private extension Data {
    /// 二进制内容哈希用（与 ClipboardService.sha1 同口径的稳定十六进制串，非加密用途）
    var baseEncodedString: String {
        reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}
