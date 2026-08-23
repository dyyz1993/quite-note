import SwiftUI
import AppKit
import ImageIO

/// 剪贴板条目行（视觉按 Alfred「All Snippets」参考样式：白色卡片行 + 左侧类型
/// 图标 + 主/次两级文字 + 右侧紫色序号；键盘选中态用浅紫背景+紫边框双通道表达）
struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onSaveToFlash: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                previewText
                HStack(spacing: 6) {
                    Text(ClipboardTimeFormatter.short(entry.createdAt))
                    if let app = entry.sourceApp {
                        Text("· \(app)")
                    }
                    statusBadges
                }
                .font(.system(size: 11))
                .foregroundColor(ClipboardPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ⌘N 序号（参考图：右侧紫色数字，仅前 9 条）
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(index < 9 ? ClipboardPalette.accent : .clear)
                .frame(width: 16)

            actionButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(rowBackground)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(rowBorder, lineWidth: isSelected ? 1.5 : 0))
        .onHover { hovering in
            isHovering = hovering
            if hovering { onSelect() }
        }
    }

    // MARK: - 左侧视觉（参考图：24px 类型图标；图片用 32px 缩略图，不加载原图）

    @ViewBuilder
    private var leadingVisual: some View {
        if entry.type == .image {
            ClipboardImageThumbnail(entry: entry, side: 32)
        } else {
            LucideView(name: typeIcon, size: 20, color: ClipboardPalette.typeColor(entry.type))
                .frame(width: 32, height: 32)
                .background(ClipboardPalette.typeColor(entry.type).opacity(0.10))
                .cornerRadius(6)
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

    // MARK: - 内容预览（主文字 14 黑 / 次文字 11 灰，参考图层级）

    @ViewBuilder
    private var previewText: some View {
        Group {
            switch entry.type {
            case .text:
                Text(entry.plainText ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ClipboardPalette.textPrimary)
                    .lineLimit(1)
            case .link:
                VStack(alignment: .leading, spacing: 1) {
                    Text(ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "") ?? "链接")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ClipboardPalette.textPrimary)
                        .lineLimit(1)
                    if let url = entry.sourceURL ?? entry.plainText {
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundColor(ClipboardPalette.textTertiary)
                            .lineLimit(1)
                    }
                }
            case .file:
                VStack(alignment: .leading, spacing: 1) {
                    Text((entry.plainText as NSString?)?.lastPathComponent ?? "文件")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ClipboardPalette.textPrimary)
                        .lineLimit(1)
                    Text(fileMetaLine)
                        .font(.system(size: 11))
                        .foregroundColor(ClipboardPalette.textTertiary)
                        .lineLimit(1)
                }
            case .image:
                // 图片条目：参考图「Image: 720x560 (6.2 MB)」风格 + OCR 文本
                VStack(alignment: .leading, spacing: 1) {
                    Text(imageMetaLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ClipboardPalette.textPrimary)
                        .lineLimit(1)
                    if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                        Text("OCR：\(ocr)")
                            .font(.system(size: 11))
                            .foregroundColor(ClipboardPalette.textTertiary)
                            .lineLimit(1)
                    } else if let status = entry.ocrStatus, status != .success {
                        OCRStatusBadge(status: status)
                    }
                }
            }
        }
    }

    /// 图片元信息行（参考图格式：Image: 720x560 (6.2 MB)）
    private var imageMetaLine: String {
        var parts: [String] = ["图片"]
        if let size = imagePixelSize {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        if entry.byteSize > 0 {
            parts.append("(\(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)))")
        }
        return parts.joined(separator: " ")
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

    /// 文件元信息行（大小 + 目录）
    private var fileMetaLine: String {
        var parts: [String] = []
        if entry.byteSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file))
        }
        if let path = entry.plainText {
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty { parts.append(dir) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 状态标记（置顶 / 已加闪记 / 含OCR）

    private var statusBadges: some View {
        HStack(spacing: 4) {
            if entry.isPinned {
                miniBadge(icon: .pin, color: ClipboardPalette.accent)
            }
            if entry.savedRecordID != nil {
                miniBadge(icon: .check, color: ClipboardPalette.statusActive)
            }
            if entry.type == .image, entry.ocrStatus == .success, entry.ocrText?.isEmpty == false {
                miniBadge(icon: .scanText, color: ClipboardPalette.accent)
            }
        }
    }

    private func miniBadge(icon: IconName, color: Color) -> some View {
        LucideView(name: icon, size: 10, color: color)
            .padding(2.5)
            .background(color.opacity(0.10))
            .cornerRadius(3)
    }

    // MARK: - 右侧操作（悬停或选中时显示）

    private var actionButtons: some View {
        HStack(spacing: 3) {
            rowButton(icon: entry.isPinned ? .pinOff : .pin,
                      help: entry.isPinned ? "取消置顶 (⌘P)" : "置顶 (⌘P)",
                      color: entry.isPinned ? ClipboardPalette.accent : ClipboardPalette.textSecondary,
                      action: onPin)
            rowButton(icon: entry.savedRecordID != nil ? .check : .save,
                      help: entry.savedRecordID != nil ? "打开对应闪记" : "加入闪记 (⌘S)",
                      color: entry.savedRecordID != nil ? ClipboardPalette.statusActive : ClipboardPalette.textSecondary,
                      action: onSaveToFlash)
            rowButton(icon: .copy, help: "复制", color: ClipboardPalette.textSecondary, action: onCopy)
            rowButton(icon: .trash2, help: "删除", color: ClipboardPalette.textSecondary, action: onDelete)
        }
        .opacity(isHovering || isSelected ? 1 : 0)
    }

    private func rowButton(icon: IconName, help: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideView(name: icon, size: 12, color: color)
                .frame(width: 24, height: 24)
                .background(Color.white)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(ClipboardPalette.inputBorder))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }

    // MARK: - 选中/悬停态（参考图：白卡 / hover #f5f5f5 / 选中 #e8eaf6）

    private var rowBackground: Color {
        if isSelected { return ClipboardPalette.rowSelected }
        if isHovering { return ClipboardPalette.rowHover }
        return ClipboardPalette.row
    }

    private var rowBorder: Color {
        isSelected ? ClipboardPalette.accent : .clear
    }
}

/// OCR 状态徽章（PRD 7.5：等待/处理中/成功/失败可重试）
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
                // 缩略图没有就直接读原图（小图可接受），大图交给失败态
                if let original = NSImage(contentsOf: url) {
                    image = original
                }
                return
            }
            image = NSImage(contentsOf: thumbnailURL)
        }
    }
}

/// 选中图片时的更大预览条（PRD 7.4：选中显示更大预览；复制原图而非 OCR 文本；失败可重试）
struct ClipboardImagePreviewStrip: View {
    let entry: ClipboardEntry
    var onRetryOCR: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ClipboardImageThumbnail(entry: entry, side: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("图片预览")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ClipboardPalette.textPrimary)
                if entry.ocrStatus == .failed {
                    HStack(spacing: 8) {
                        OCRStatusBadge(status: .failed)
                        Button("重试 OCR") { onRetryOCR?() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else if let status = entry.ocrStatus {
                    OCRStatusBadge(status: status)
                }
                if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                    Text(ocr)
                        .font(.system(size: 11))
                        .foregroundColor(ClipboardPalette.textSecondary)
                        .lineLimit(3)
                }
                Text("粘贴时复制原图（非 OCR 文本）")
                    .font(.system(size: 10))
                    .foregroundColor(ClipboardPalette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// 时间展示：今天 HH:mm / 昨天 HH:mm / MM-dd（与 PRD 7.2 示例一致）
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

    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeFormatter.string(from: date))"
        }
        return dateFormatter.string(from: date)
    }
}
