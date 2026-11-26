import QuiteNoteSharedStorage
import SwiftUI
import AppKit
import ImageIO

/// 来源应用图标（按 bundleID 经 NSWorkspace 解析 app 路径取真实图标，带缓存）
enum ClipboardSourceAppIcon {
    private static var cache: [String: NSImage?] = [:]

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let hit = cache[bundleID] { return hit }
        // 预缩放为 28px 位图（14pt@2x）：NSWorkspace 原始图标带 1024px representation，
        // 行渲染时现场光栅化是滚动卡顿来源之一（同启动器 87ms 首建问题）
        let resolved: NSImage? = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { AppCatalogStore.downscaledIcon(url: $0, side: 28) }
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
