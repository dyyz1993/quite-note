import SwiftUI
import AppKit

/// 右栏详情：展示选中条目的完整内容（参考图双栏布局的右半区）
struct ClipboardDetailPane: View, Equatable {
    let entry: ClipboardEntry?
    var onRetryOCR: (() -> Void)? = nil

    /// 详情大图（异步降采样加载——body 里同步 NSImage(contentsOf:) 解码全分辨率
    /// 原图，每按一次 ↑↓ 换选中都在主线程解码几 MB，是方向键切换卡顿的元凶）
    @State private var detailImage: NSImage?
    @State private var loadedImageID: UUID?

    /// 按身份比较而非全字段：synthesized == 会逐字段比较 plainText/ocrText
    /// （可达 1MB），每次按键的视图 diff 都付这个成本（打字卡顿源）。
    /// 内容变化（OCR 完成等）由 store.entriesVersion → 全表 reload 覆盖
    static func == (lhs: ClipboardDetailPane, rhs: ClipboardDetailPane) -> Bool {
        lhs.entry?.id == rhs.entry?.id
            && lhs.entry?.ocrStatus == rhs.entry?.ocrStatus
            && lhs.entry?.isPinned == rhs.entry?.isPinned
    }

    var body: some View {
        Group {
            if let entry {
                detail(for: entry)
            } else {
                VStack(spacing: 8) {
                    LucideView(name: .mousePointer2, size: 28, color: ClipboardPalette.textTertiary)
                    Text("↑↓ 选择条目查看内容")
                        .font(.system(size: 12))
                        .foregroundColor(ClipboardPalette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
    }

    @ViewBuilder
    private func detail(for entry: ClipboardEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(entry)

                switch entry.type {
                case .text:
                    Text(entry.plainText ?? "")
                        .font(.system(size: 12.5))
                        .foregroundColor(ClipboardPalette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .link:
                    VStack(alignment: .leading, spacing: 8) {
                        if let domain = ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "") {
                            ClipboardFaviconView(domain: domain, side: 40)
                            Text(domain)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(ClipboardPalette.textPrimary)
                        }
                        Text(entry.sourceURL ?? entry.plainText ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(ClipboardPalette.accent)
                            .textSelection(.enabled)
                    }
                case .file:
                    VStack(alignment: .leading, spacing: 8) {
                        Text((entry.plainText as NSString?)?.lastPathComponent ?? "文件")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ClipboardPalette.textPrimary)
                        if entry.byteSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file))
                                .font(.system(size: 11))
                                .foregroundColor(ClipboardPalette.textSecondary)
                        }
                        Text(entry.plainText ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ClipboardPalette.textTertiary)
                            .textSelection(.enabled)
                    }
                case .image:
                    imageDetail(entry)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 头部：类型 + 来源 + 时间

    private func headerRow(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            LucideView(name: typeIcon(entry.type), size: 14, color: ClipboardPalette.typeColor(entry.type))
            Text(entry.type.localizedName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ClipboardPalette.textSecondary)
            Spacer()
            if let icon = ClipboardSourceAppIcon.icon(bundleID: entry.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else if let app = entry.sourceApp {
                Text(app).font(.system(size: 11)).foregroundColor(ClipboardPalette.textTertiary)
            }
            Text(ClipboardTimeFormatter.short(entry.createdAt))
                .font(.system(size: 11))
                .foregroundColor(ClipboardPalette.textTertiary)
            if entry.pasteCount > 0 {
                Text("粘贴 \(entry.pasteCount) 次")
                    .font(.system(size: 11))
                    .foregroundColor(ClipboardPalette.textTertiary)
            }
        }
    }

    private func typeIcon(_ type: ClipboardEntryType) -> IconName {
        switch type {
        case .text: return .type
        case .link: return .link
        case .file: return .fileText
        case .image: return .image
        }
    }

    /// 两阶段加载（用户方案，2026-09-12）：
    /// ① 缩略图秒出——捕获时已生成的 256px 缩略图解码毫秒级，↑↓ 每步都有图看
    /// ② 停稳 300ms 后原图降采样（1400px）换上——Task.sleep 期间被取消
    ///   （.task(id:) 换选中即取消）= 快速连按时**不发起任何全图解码**，
    ///   只有用户停下才加载，彻底消除解码并发抢主线程
    private func loadDetailImage(entry: ClipboardEntry, url: URL) async {
        guard loadedImageID != entry.id else { return }
        loadedImageID = entry.id
        detailImage = nil
        let entryID = entry.id

        // 阶段 ①：已有缩略图（512px 内解码，后台低开销）
        let thumb = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let thumbURL = ThumbnailGenerator.shared.existingThumbnailURL(for: url) else { return nil }
            return Self.decodeDownsampled(at: thumbURL, maxPixel: 512)
        }.value
        if entryID == entry.id {
            detailImage = thumb   // 可能为 nil（无缩略图）→ 继续显示 ProgressView
        }

        // 阶段 ②：停稳窗口（快速 ↑↓ 时任务在此被取消，不浪费解码）
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, entryID == entry.id else { return }

        let full = await Task.detached(priority: .utility) {   // 低优先级，不抢主线程
            Self.decodeDownsampled(at: url, maxPixel: 1400)
        }.value
        if entryID == entry.id, full != nil {
            detailImage = full
        }
    }

    nonisolated static func decodeDownsampled(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - 图片详情：大图 + OCR 全文 + 重试

    @ViewBuilder
    private func imageDetail(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let virtualPath = entry.assetPath,
               let url = FileCoordinator.shared.resolveVirtualPath(virtualPath),
               FileManager.default.fileExists(atPath: url.path) {
                if let image = detailImage, loadedImageID == entry.id {
                    // 宽高双向约束：保持比例完整适配（宽图贴宽、长图贴高，不裁切不溢出）
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 340)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ClipboardPalette.inputBorder))
                        .task(id: entry.id) {
                            await loadDetailImage(entry: entry, url: url)
                        }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .task(id: entry.id) {
                            await loadDetailImage(entry: entry, url: url)
                        }
                }
            } else {
                HStack(spacing: 6) {
                    LucideView(name: .circleX, size: 13, color: ClipboardPalette.statusError)
                    Text("原图文件已丢失")
                        .font(.system(size: 12))
                        .foregroundColor(ClipboardPalette.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(ClipboardPalette.background)
                .cornerRadius(6)
            }

            if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        LucideView(name: .scanText, size: 12, color: ClipboardPalette.accent)
                        Text("OCR 文字")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ClipboardPalette.textSecondary)
                    }
                    Text(ocr)
                        .font(.system(size: 12))
                        .foregroundColor(ClipboardPalette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(ClipboardPalette.background)
                .cornerRadius(6)
            } else if entry.ocrStatus == .failed {
                HStack(spacing: 8) {
                    OCRStatusBadge(status: .failed)
                    Button("重试 OCR") { onRetryOCR?() }
                        .focusable(false) // 键盘导航不可达 → 不画焦点环
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if let status = entry.ocrStatus {
                OCRStatusBadge(status: status)
            }
        }
    }
}
