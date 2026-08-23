import SwiftUI
import AppKit

/// 剪贴板条目行（PRD 7.2）
///
/// 结构：类型图标/缩略图 + 内容预览（时间·来源）+ 状态标记（OCR/置顶/闪记）+ 右侧操作。
/// 键盘选中态用背景+边框双通道表达（PRD 14：不依赖颜色单独表达）。
struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // ⌘N 序号提示（前 9 条）
            Text("\(index + 1)")
                .font(.themeCaptionSmall)
                .monospaced()
                .foregroundColor(index < 9 ? .themeTextTertiary : .clear)
                .frame(width: 16)

            leadingVisual

            VStack(alignment: .leading, spacing: 4) {
                previewText
                HStack(spacing: 6) {
                    Text(ClipboardTimeFormatter.short(entry.createdAt))
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    if let app = entry.sourceApp {
                        Text("· \(app)")
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                    }
                    statusBadges
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(rowBorder, lineWidth: isSelected ? 1.5 : 0))
        .onHover { hovering in
            isHovering = hovering
            if hovering { onSelect() }
        }
    }

    // MARK: - 左侧视觉（类型图标或缩略图，PRD 7.4：列表不加载原图）

    @ViewBuilder
    private var leadingVisual: some View {
        if entry.type == .image {
            ClipboardImageThumbnail(entry: entry, side: 44)
        } else {
            LucideView(name: typeIcon, size: 18, color: typeColor)
                .frame(width: 44, height: 44)
                .background(typeColor.opacity(0.08))
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

    private var typeColor: Color {
        switch entry.type {
        case .text: return .themeTextSecondary
        case .link: return .themeBlue400
        case .file: return .themePurple400
        case .image: return .themeGreen500
        }
    }

    // MARK: - 内容预览（PRD 7.2 示例格式）

    @ViewBuilder
    private var previewText: some View {
        Group {
            switch entry.type {
            case .text:
                Text(entry.plainText ?? "")
                    .lineLimit(2)
            case .link:
                VStack(alignment: .leading, spacing: 1) {
                    Text(ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "") ?? "链接")
                        .lineLimit(1)
                    if let url = entry.sourceURL ?? entry.plainText {
                        Text(url)
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                            .lineLimit(1)
                    }
                }
            case .file:
                VStack(alignment: .leading, spacing: 1) {
                    Text((entry.plainText as NSString?)?.lastPathComponent ?? "文件")
                        .lineLimit(1)
                    if let path = entry.plainText {
                        Text(path)
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                            .lineLimit(1)
                    }
                }
            case .image:
                // 图片条目：OCR 文本作为预览（PRD 7.2 示例）
                if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                    Text("OCR：\(ocr)")
                        .lineLimit(2)
                } else if let status = entry.ocrStatus {
                    OCRStatusBadge(status: status)
                } else {
                    Text("图片")
                        .foregroundColor(.themeTextTertiary)
                }
            }
        }
        .font(.themeBody)
        .foregroundColor(.themeTextPrimary)
    }

    // MARK: - 状态标记（PRD 7.2：OCR 状态 / 置顶 / 已加闪记）

    private var statusBadges: some View {
        HStack(spacing: 4) {
            if entry.isPinned {
                miniBadge(icon: .pin, color: .themeBlue400)
            }
            if entry.savedRecordID != nil {
                miniBadge(icon: .check, color: .themeGreen500)
            }
            if entry.type == .image, entry.ocrStatus == .success, entry.ocrText?.isEmpty == false {
                miniBadge(icon: .scanText, color: .themePurple400)
            }
        }
    }

    private func miniBadge(icon: IconName, color: Color) -> some View {
        LucideView(name: icon, size: 10, color: color)
            .padding(3)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }

    // MARK: - 右侧操作（PRD 7.2：置顶 / 粘贴 / 删除；悬停或选中时显示）

    private var actionButtons: some View {
        HStack(spacing: 4) {
            rowButton(icon: entry.isPinned ? .pinOff : .pin,
                      help: entry.isPinned ? "取消置顶 (⌘P)" : "置顶 (⌘P)",
                      color: entry.isPinned ? .themeBlue400 : .themeTextSecondary,
                      action: onPin)
            rowButton(icon: .copy, help: "复制", color: .themeTextSecondary, action: onCopy)
            rowButton(icon: .trash2, help: "删除", color: .themeTextSecondary, action: onDelete)
        }
        .opacity(isHovering || isSelected ? 1 : 0.25)
    }

    private func rowButton(icon: IconName, help: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideView(name: icon, size: 13, color: color)
                .frame(width: 26, height: 26)
                .background(Color.themeHoverMedium.opacity(0.6))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }

    // MARK: - 选中/悬停态

    private var rowBackground: Color {
        if isSelected { return .themeSelected }
        if isHovering { return .themeHoverLight }
        return .themeGray900.opacity(0.35)
    }

    private var rowBorder: Color {
        isSelected ? .themeBlue500 : .clear
    }
}

/// OCR 状态徽章（PRD 7.5：等待/处理中/成功/失败可重试）
struct OCRStatusBadge: View {
    let status: ClipboardOCRStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .waiting:
                LucideView(name: .clock, size: 11, color: .themeTextTertiary)
                Text("OCR 排队中")
            case .processing:
                LucideView(name: .refreshCw, size: 11, color: .themeBlue400)
                Text("OCR 识别中…")
            case .success:
                LucideView(name: .check, size: 11, color: .themeGreen500)
                Text("OCR 完成")
            case .failed:
                LucideView(name: .alertTriangle, size: 11, color: .themeStatusError)
                Text("OCR 失败")
            case .disabled:
                LucideView(name: .eyeOff, size: 11, color: .themeTextTertiary)
                Text("OCR 已关闭")
            }
        }
        .font(.themeCaptionSmall)
        .foregroundColor(.themeTextSecondary)
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
                    .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.themeGray800)
                    if isFileMissing {
                        VStack(spacing: 2) {
                            LucideView(name: .circleX, size: 14, color: .themeStatusError)
                            Text("丢失")
                                .font(.themeCaptionTiny)
                                .foregroundColor(.themeTextTertiary)
                        }
                    } else {
                        LucideView(name: .image, size: 16, color: .themeTextTertiary)
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

/// 选中图片时的更大预览条（PRD 7.4：选中显示更大预览；复制原图而非 OCR 文本）
struct ClipboardImagePreviewStrip: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(spacing: 14) {
            ClipboardImageThumbnail(entry: entry, side: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("图片预览")
                    .font(.themeH3)
                    .foregroundColor(.themeTextPrimary)
                if let status = entry.ocrStatus {
                    OCRStatusBadge(status: status)
                }
                if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                    Text(ocr)
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                        .lineLimit(4)
                }
                Text("粘贴时复制原图（非 OCR 文本）")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
