import SwiftUI
import AppKit

/// 左栏列表的 AppKit 原生实现（NSTableView）
///
/// 为什么不用 SwiftUI ScrollView：scrollTo 是跳变式的，做不到 Alfred 的
/// 逐行平滑跟随手感。NSTableView 的键盘导航 + scrollRowToVisible 原生
/// 就是 Alfred 的交互；rows(in: visibleRect) 可精确拿到可见行（⌘1–⌘9 锚定视口）。
struct ClipboardListTableView: NSViewRepresentable {
    let entries: [ClipboardEntry]
    @Binding var selectedIndex: Int
    let onSingleClick: (Int) -> Void   // 单击 = 选中 + 复制
    let onDoubleClick: (Int) -> Void   // 双击 = 粘贴
    /// 可见首行变化回调（⌘N 序号锚定视口用）
    let onVisibleTopChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 38
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.selectionHighlightStyle = .none // 选中态由行内容自绘（紫底白字）
        table.doubleAction = #selector(Coordinator.onDoubleAction(_:))
        table.target = context.coordinator
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.sizeLastColumnToFit()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.verticalScroller?.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear

        context.coordinator.table = table
        context.coordinator.observeScrolling(scroll)
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let table = scrollView.documentView as? NSTableView
        context.coordinator.parent = self

        let reloadNeeded = context.coordinator.entriesSignature != signature
        if reloadNeeded {
            context.coordinator.entriesSignature = signature
            table?.reloadData()
            // 数据变化后保持选中在范围内
            let safe = min(max(0, selectedIndex), max(0, entries.count - 1))
            if safe != selectedIndex { selectedIndex = safe }
        }
        // 外部（↑↓ 键盘/⌘N）驱动的选中变化：同步表格选择并逐行滚到可见
        if let table, table.selectedRow != selectedIndex, entries.indices.contains(selectedIndex) {
            context.coordinator.suppressSelectionCallback = true
            table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            table.scrollRowToVisible(selectedIndex)
            context.coordinator.suppressSelectionCallback = false
        }
        // 选中行刷新（数据签名没变但选中变了也要重绘新旧选中行）
        if reloadNeeded == false, let table {
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<max(1, entries.count)), columnIndexes: IndexSet(integer: 0))
        }
    }

    /// 轻量数据签名（内容 id + 选中相关字段变化才整表重载）
    private var signature: String {
        entries.map { "\($0.id.uuidString.prefix(8))-\($0.isPinned ? 1 : 0)-($0.savedRecordID != nil ? 1 : 0)-\($0.ocrStatus?.rawValue ?? "")" }
            .joined(separator: ",")
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ClipboardListTableView
        var table: NSTableView?
        var entriesSignature = ""
        /// 当前可见首行（序号锚定视口）
        var visibleTop = 0
        /// 外部程序化选择时抑制 selectionDidChange 的单击回调（防误复制）
        var suppressSelectionCallback = false

        init(_ parent: ClipboardListTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("row")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ClipRowCell ?? ClipRowCell()
            let slot = row - visibleTop + 1
            cell.configure(
                entry: parent.entries[row],
                index: row,
                isSelected: row == parent.selectedIndex,
                paletteNumber: (1...9).contains(slot) ? slot : nil
            )
            return cell
        }

        /// 用户点选行（真实交互才回调；程序化 selectRowIndexes 被抑制）
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table, !suppressSelectionCallback else { return }
            let row = table.selectedRow
            guard row >= 0, parent.entries.indices.contains(row) else { return }
            if parent.selectedIndex != row {
                parent.selectedIndex = row
            }
            parent.onSingleClick(row)
        }

        @objc func onDoubleAction(_ sender: Any?) {
            guard let table, table.clickedRow >= 0, parent.entries.indices.contains(table.clickedRow) else { return }
            parent.onDoubleClick(table.clickedRow)
        }

        /// 滚动位置变化 → 上报可见首行 + 刷新可见行序号
        func observeScrolling(_ scroll: NSScrollView) {
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                self?.reportVisibleTop()
            }
        }

        func reportVisibleTop() {
            guard let table, let scroll = table.enclosingScrollView else { return }
            let visible = table.rows(in: scroll.contentView.visibleRect)
            guard visible.length > 0, visible.location != visibleTop else { return }
            let oldTop = visibleTop
            visibleTop = visible.location
            parent.onVisibleTopChanged(visibleTop)
            // 只刷新受序号变化影响的可见行区间（滚动一行只波及约两行的编号边界）
            let lo = max(0, min(oldTop, visibleTop))
            let hi = min(parent.entries.count - 1, max(oldTop, visibleTop) + 11)
            if hi >= lo {
                table.reloadData(forRowIndexes: IndexSet(integersIn: lo...hi), columnIndexes: IndexSet(integer: 0))
            }
        }
    }
}

/// 单行单元格（纯 AppKit：图标 + 内容 + 来源图标 + 时间 + ⌘N）
final class ClipRowCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let sourceIconView = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    private var entry: ClipboardEntry?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 不支持") }

    private func setup() {
        for label in [titleLabel, timeLabel, shortcutLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(sourceIconView)
        addSubview(timeLabel)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceIconView.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -6),
            sourceIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 14),
            sourceIconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sourceIconView.leadingAnchor, constant: -8),
        ])
    }

    func configure(entry: ClipboardEntry, index: Int, isSelected: Bool, paletteNumber: Int?) {
        self.entry = entry
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.white.cgColor

        let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let metaFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

        if isSelected {
            layer?.backgroundColor = NSColor(red: 0.424, green: 0.204, blue: 0.514, alpha: 1).cgColor
            titleLabel.textColor = .white
            timeLabel.textColor = NSColor.white.withAlphaComponent(0.75)
            shortcutLabel.textColor = .white
        } else {
            layer?.backgroundColor = NSColor.white.cgColor
            titleLabel.textColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
            timeLabel.textColor = NSColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1)
            let accent = NSColor(red: 0.424, green: 0.204, blue: 0.514, alpha: 1)
            shortcutLabel.textColor = paletteNumber != nil ? accent : NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.6)
        }
        titleLabel.font = titleFont
        timeLabel.font = metaFont
        shortcutLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

        titleLabel.stringValue = ClipRowContent.singleLine(entry)
        timeLabel.stringValue = ClipboardTimeFormatter.short(entry.createdAt)
        shortcutLabel.stringValue = isSelected ? "⏎" : (paletteNumber.map { "⌘\($0)" } ?? "\(index + 1)")
        shortcutLabel.alphaValue = (isSelected || paletteNumber != nil) ? 1 : 0.4

        // 图标：图片缩略图异步 / favicon 异步 / 类型符号同步
        ClipRowContent.icon(entry) { [weak self] image in
            self?.iconView.image = image
        }
        sourceIconView.image = ClipboardSourceAppIcon.icon(bundleID: entry.sourceBundleID)
        sourceIconView.isHidden = sourceIconView.image == nil
    }
}

/// 行内容组装（AppKit 单元格用）
enum ClipRowContent {
    static func singleLine(_ entry: ClipboardEntry) -> String {
        switch entry.type {
        case .text:
            return (entry.plainText ?? "").replacingOccurrences(of: "\n", with: " ")
        case .link:
            return ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "") ?? "链接"
        case .file:
            return (entry.plainText as NSString?)?.lastPathComponent ?? "文件"
        case .image:
            var parts = ["图片"]
            if let size = pixelSize(entry) {
                parts.append("\(Int(size.width))×\(Int(size.height))")
            }
            if entry.ocrStatus == .success, let ocr = entry.ocrText, !ocr.isEmpty {
                parts.append("OCR：\(ocr.replacingOccurrences(of: "\n", with: " "))")
            }
            return parts.joined(separator: " ")
        }
    }

    static func icon(_ entry: ClipboardEntry, completion: @escaping (NSImage?) -> Void) {
        switch entry.type {
        case .image:
            guard let virtualPath = entry.assetPath,
                  let url = FileCoordinator.shared.resolveVirtualPath(virtualPath) else {
                completion(NSImage(systemSymbolName: "photo", accessibilityDescription: nil)); return
            }
            ThumbnailGenerator.shared.getThumbnailURLAsync(for: url) { thumbURL in
                completion(NSImage(contentsOfFile: (thumbURL ?? url).path))
            }
        case .link:
            let domain = ClipboardTypeDetector.domain(ofURL: entry.sourceURL ?? entry.plainText ?? "")
            guard let domain else {
                completion(NSImage(systemSymbolName: "link", accessibilityDescription: nil)); return
            }
            if let cached = ClipboardFaviconService.shared.cachedFavicon(for: domain) {
                completion(cached)
            } else {
                completion(NSImage(systemSymbolName: "link", accessibilityDescription: nil))
                ClipboardFaviconService.shared.loadFavicon(for: domain) { _ in
                    // 下一轮 reloadData 时会拿到缓存；此处不主动刷
                }
            }
        default:
            let symbol = entry.type == .file ? "doc.text" : "textformat"
            completion(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        }
    }

    static func pixelSize(_ entry: ClipboardEntry) -> CGSize? {
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}

import ImageIO
