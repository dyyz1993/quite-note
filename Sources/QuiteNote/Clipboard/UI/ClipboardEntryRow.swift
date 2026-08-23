import SwiftUI
import AppKit
import ImageIO

/// 剪贴板条目行（紧凑单行，对齐 Alfred 密度）
///
/// 结构：图标/缩略图/favicon | 单行内容（截断） | 来源图标 | 时间 | ⌘N 直贴序号（1–9 清晰，之后淡化）
/// 行内不放操作按钮——操作全走底部快捷键（↩ 粘贴 / ⌘S 闪记 / ⌘P 置顶 / ⌫ 删除），单击=复制。
struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let index: Int
    /// 页内序号（1–9，Alfred 分页模型：⌘1 永远是当前视口顶行）；nil = 页外淡化
    let pageSlot: Int?
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onSaveToFlash: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            leadingVisual

            // 单行内容（截断；图片条目把元信息和 OCR 摘要拼进同一行）
            Text(singleLineContent)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(isSelected ? .white : ClipboardPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusBadges

            // 来源应用图标（拉不到回退文字）
            if let icon = ClipboardSourceAppIcon.icon(bundleID: entry.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else if let app = entry.sourceApp {
                Text(app)
                    .font(.system(size: 10.5))
                    .foregroundColor(isSelected ? .white.opacity(0.75) : ClipboardPalette.textTertiary)
                    .lineLimit(1)
            }

            // 时间：固定宽度右对齐列（各行对齐成竖列）
            Text(ClipboardTimeFormatter.short(entry.createdAt))
                .font(.system(size: 10.5))
                .foregroundColor(isSelected ? .white.opacity(0.75) : ClipboardPalette.textTertiary)
                .frame(minWidth: 68, alignment: .trailing)
                .fixedSize()

            // 尾标：选中行显示 ⏎（回车粘贴）；未选中显示 ⌘N（页内 1–9 清晰，页外淡化）
            if isSelected {
                Text("⏎")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 28, alignment: .trailing)
                    .fixedSize()
            } else if let slot = pageSlot {
                Text("⌘\(slot)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(ClipboardPalette.accent)
                    .frame(minWidth: 28, alignment: .trailing)
                    .fixedSize()
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(ClipboardPalette.textTertiary)
                    .opacity(0.4)
                    .frame(minWidth: 28, alignment: .trailing)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(rowBackground)
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
            if hovering { onSelect() }
        }
    }

    // MARK: - 单行内容

    private var singleLineContent: String {
        switch entry.type {
        case .text:
            return (entry.plainText ?? "")
                .replacingOccurrences(of: "\n", with: " ")
        case .link:
            let domain = ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "") ?? "链接"
            return domain
        case .file:
            return (entry.plainText as NSString?)?.lastPathComponent ?? "文件"
        case .image:
            var parts = [imageMetaTitle]
            if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                parts.append("OCR：\(ocr.replacingOccurrences(of: "\n", with: " "))")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// 图片元信息（参考图「Image: 720x560 (6.2 MB)」风格）
    private var imageMetaTitle: String {
        var parts: [String] = ["图片"]
        if let size = imagePixelSize {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        if entry.byteSize > 0 {
            parts.append("(\(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)))")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 左侧视觉（28px：类型图标 / 图片缩略图 / 站点 favicon）

    @ViewBuilder
    private var leadingVisual: some View {
        if entry.type == .image {
            ClipboardImageThumbnail(entry: entry, side: 26)
        } else if entry.type == .link, let domain = linkDomain {
            ClipboardFaviconView(domain: domain, side: 26)
        } else {
            LucideView(name: typeIcon, size: 16, color: ClipboardPalette.typeColor(entry.type))
                .frame(width: 26, height: 26)
                .background(ClipboardPalette.typeColor(entry.type).opacity(0.10))
                .cornerRadius(5)
        }
    }

    private var typeIcon: IconName {
        switch entry.type {
        case .text: return .type
        case .link: return .link
        case .file: return .fileText
        case .image: return .image
        }
    }

    private var linkDomain: String? {
        guard let url = entry.sourceURL ?? entry.plainText else { return nil }
        return ClipboardTypeDetector.domain(ofURL: url)
    }

    private var imagePixelSize: CGSize? {
        // 只读图片头部的宽高元数据（不解码像素，不加载原图）
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - 状态标记（置顶 / 已加闪记）

    private var statusBadges: some View {
        HStack(spacing: 3) {
            if entry.isPinned {
                miniBadge(icon: .pin, color: ClipboardPalette.accent)
            }
            if entry.savedRecordID != nil {
                miniBadge(icon: .check, color: ClipboardPalette.statusActive)
            }
        }
    }

    private func miniBadge(icon: IconName, color: Color) -> some View {
        LucideView(name: icon, size: 9, color: color)
            .padding(2)
            .background(color.opacity(0.10))
            .cornerRadius(3)
    }

    // MARK: - 选中/悬停态（参考图：选中行紫底白字，hover #f5f5f5）

    private var rowBackground: Color {
        if isSelected { return ClipboardPalette.header } // 深紫 + 白字
        if isHovering { return ClipboardPalette.rowHover }
        return ClipboardPalette.row
    }
}

/// 来源应用图标（按 bundleID 经 NSWorkspace 解析 app 路径取真实图标，带缓存）
enum ClipboardSourceAppIcon {
    private static var cache: [String: NSImage?] = [:]

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let hit = cache[bundleID] { return hit }
        let resolved: NSImage? = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = resolved
        return resolved
    }
}

/// OCR 状态徽章（预览条用；列表行内不展示）
struct OCRStatusBadge: View {
    let status: ClipboardOCRStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .waiting:
                LucideView(name: .clock, size: 10, color: ClipboardPalette.textTertiary)
                Text("OCR 排队中")
            case .processing:
                LucideView(name: .refreshCw, size: 10, color: ClipboardPalette.accent)
                Text("OCR 识别中…")
            case .success:
                LucideView(name: .check, size: 10, color: ClipboardPalette.statusActive)
                Text("OCR 完成")
            case .failed:
                LucideView(name: .alertTriangle, size: 10, color: ClipboardPalette.statusError)
                Text("OCR 失败")
            case .disabled:
                LucideView(name: .eyeOff, size: 10, color: ClipboardPalette.textTertiary)
                Text("OCR 已关闭")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(ClipboardPalette.textSecondary)
    }
}

/// 图片缩略图（异步取 ThumbnailGenerator 缓存，不加载原图；文件丢失显示占位）
struct ClipboardImageThumbnail: View {
    let entry: ClipboardEntry
    let side: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
                    .cornerRadius(4)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ClipboardPalette.background)
                    if isFileMissing {
                        VStack(spacing: 2) {
                            LucideView(name: .circleX, size: 13, color: ClipboardPalette.statusError)
                            Text("丢失")
                                .font(.system(size: 8))
                                .foregroundColor(ClipboardPalette.textTertiary)
                        }
                    } else {
                        LucideView(name: .image, size: 14, color: ClipboardPalette.textTertiary)
                    }
                }
                .frame(width: side, height: side)
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private var isFileMissing: Bool {
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath) else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private func loadThumbnail() {
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath) else { return }
        ThumbnailGenerator.shared.getThumbnailURLAsync(for: url) { thumbnailURL in
            guard let thumbnailURL else {
                if let original = NSImage(contentsOf: url) {
                    image = original
                }
                return
            }
            image = NSImage(contentsOf: thumbnailURL)
        }
    }
}

/// 链接条目的站点 favicon（https://<domain>/favicon.ico，缓存优先，失败回退通用链接图标）
struct ClipboardFaviconView: View {
    let domain: String
    var side: CGFloat = 32

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side - 10, height: side - 10)
                    .frame(width: side, height: side)
                    .background(ClipboardPalette.typeColor(.link).opacity(0.08))
                    .cornerRadius(5)
            } else if failed {
                LucideView(name: .link, size: 16, color: ClipboardPalette.typeColor(.link))
                    .frame(width: side, height: side)
                    .background(ClipboardPalette.typeColor(.link).opacity(0.10))
                    .cornerRadius(5)
            } else {
                LucideView(name: .link, size: 16, color: ClipboardPalette.textTertiary)
                    .frame(width: side, height: side)
                    .background(ClipboardPalette.typeColor(.link).opacity(0.06))
                    .cornerRadius(5)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let hit = ClipboardFaviconService.shared.cachedFavicon(for: domain) {
            image = hit
            return
        }
        ClipboardFaviconService.shared.loadFavicon(for: domain) { result in
            if let result {
                image = result
            } else {
                failed = true
            }
        }
    }
}

/// 选中图片时的底部预览条（PRD 7.4；常驻固定高度防列表抖动）
struct ClipboardImagePreviewStrip: View {
    let entry: ClipboardEntry
    var onRetryOCR: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ClipboardImageThumbnail(entry: entry, side: 52)
            VStack(alignment: .leading, spacing: 3) {
                if entry.ocrStatus == .failed {
                    HStack(spacing: 8) {
                        OCRStatusBadge(status: .failed)
                        Button("重试 OCR") { onRetryOCR?() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                } else if let status = entry.ocrStatus {
                    OCRStatusBadge(status: status)
                }
                if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                    Text(ocr)
                        .font(.system(size: 10.5))
                        .foregroundColor(ClipboardPalette.textSecondary)
                        .lineLimit(2)
                }
                Text("粘贴时复制原图（非 OCR 文本）")
                    .font(.system(size: 9.5))
                    .foregroundColor(ClipboardPalette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// 时间展示：刚刚 / N 分钟前 / 今天 HH:mm / 昨天 HH:mm / N 天前（7 天内）/ MM-dd / yyyy-MM-dd
enum ClipboardTimeFormatter {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let minutes = Int(-date.timeIntervalSinceNow / 60)
            if minutes < 1 { return "刚刚" }
            if minutes < 60 { return "\(minutes) 分钟前" }
            return "今天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeFormatter.string(from: date))"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        if (2...7).contains(days) {
            return "\(days) 天前"
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return dateFormatter.string(from: date)
        }
        return fullDateFormatter.string(from: date)
    }
}
