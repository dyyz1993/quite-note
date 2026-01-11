import SwiftUI
import AppKit

/// 符号工具栏按钮 - StickyNote 工具栏中的符号入口
struct SymbolToolbarButton: View {
    @State private var showFloatingMenu = false
    @StateObject private var configManager = SymbolConfigManager.shared

    var categories: [SymbolMenu] {
        configManager.enabledConfigs.flatMap { $0.menus }.sorted { $0.sort < $1.sort }
    }

    var body: some View {
        GeometryReader { geometry in
            Button(action: {
                let frame = geometry.frame(in: .global)
                SymbolFloatingMenuManager.shared.showMenu(
                    at: NSPoint(x: frame.midX, y: frame.maxY + 8),
                    categories: categories,
                    sourceView: nil
                )
            }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("符号快捷输入")
        }
        .frame(height: 24)
    }
}

/// 浮层菜单管理器 - 使用 NSPanel 避免被父视图裁剪
class SymbolFloatingMenuManager {
    static let shared = SymbolFloatingMenuManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingSymbolContentView>?

    func showMenu(at point: NSPoint, categories: [SymbolMenu], sourceView: NSView?) {
        // 如果已显示，先关闭
        closeMenu()

        // 创建面板
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true

        // 创建内容视图
        let contentView = FloatingSymbolContentView(
            categories: categories,
            onClose: { [weak self] in
                self?.closeMenu()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // 计算位置（确保在屏幕内）
        var origin = point
        origin.y -= 280  // 向上展开280像素

        // 确保不超出屏幕边界
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            if origin.x + 280 > screenFrame.maxX {
                origin.x = screenFrame.maxX - 290
            }
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX + 10
            }
            if origin.y < screenFrame.minY {
                origin.y = point.y + 10  // 改为向下展开
            }
        }

        panel.setFrameOrigin(origin)

        // 显示面板
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView

        // 监听窗口关闭
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )
    }

    func closeMenu() {
        panel?.close()
        panel = nil
        hostingView = nil
    }

    @objc private func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        panel = nil
        hostingView = nil
    }
}

/// 浮层符号菜单内容视图
struct FloatingSymbolContentView: View {
    let categories: [SymbolMenu]
    let onClose: () -> Void

    @State private var selectedCategoryIndex = 0

    var currentCategory: SymbolMenu? {
        guard selectedCategoryIndex < categories.count else { return nil }
        return categories[selectedCategoryIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 分类图标行
            HStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    FloatingCategoryIcon(
                        icon: category.icon ?? "📁",
                        isSelected: selectedCategoryIndex == index
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategoryIndex = index
                        }
                    }
                }

                Spacer()

                // 关闭按钮
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.themeTextTertiary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.themeGray800)

            // 符号网格
            if let category = currentCategory {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4),
                        GridItem(.flexible(), spacing: 4)
                    ], spacing: 4) {
                        ForEach(category.symbols) { symbol in
                            FloatingSymbolItem(symbol: symbol) {
                                insertSymbol(symbol)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.themeGray700)
            }

            // 底部提示
            HStack(spacing: 8) {
                Text("点击符号插入")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
                Text("ESC 关闭")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.themeGray800)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.themeGray800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .shadow(color: Color.themeShadowMedium, radius: 12, x: 0, y: 4)
        .onAppear {
            // 监听 ESC 键关闭
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    onClose()
                    return nil  // 消费事件
                }
                return event
            }
        }
    }

    private func insertSymbol(_ symbol: SymbolItem) {
        NotificationCenter.default.post(
            name: .insertSymbolFromBrowser,
            object: nil,
            userInfo: ["symbol": symbol, "mode": "floating"]
        )
        onClose()
    }
}

/// 浮层分类图标
struct FloatingCategoryIcon: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.themeBlue500.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.themeBlue500 : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 浮层符号项
struct FloatingSymbolItem: View {
    let symbol: SymbolItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(symbol.content)
                    .font(.system(size: 16))

                Text(String(symbol.desc.prefix(3)))
                    .font(.system(size: 7))
                    .foregroundColor(.themeTextTertiary)
                    .lineLimit(1)
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.themeHoverLight)
            )
        }
        .buttonStyle(.plain)
        .help(symbol.desc)
    }
}
