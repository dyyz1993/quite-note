import SwiftUI
import AppKit
import Cocoa
import UniformTypeIdentifiers
import Combine

// MARK: - Keyboard Intercept View

/// 键盘事件拦截视图（AppKit 包装）
struct KeyboardInterceptViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = KeyboardInterceptView()
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 自定义 NSView 用于拦截键盘事件（特别是 ESC 键）
class KeyboardInterceptView: NSView {
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // 监听本地键盘事件（不要求成为第一响应者）
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC key code
                    print("[DEBUG AppKit] ESC key detected via local monitor")
                    NotificationCenter.default.post(name: .escKeyPressed, object: nil)
                    return nil // 消费事件，不让其他控件处理
                }
                return event
            }
        } else {
            localMonitor = nil
        }
    }

    deinit {
        localMonitor = nil
    }
}

extension Notification.Name {
    static let escKeyPressed = Notification.Name("escKeyPressed")
}

/// 悬浮窗根视图
struct FloatingRootView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var heatmapVM: HeatmapViewModel
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject var focus: WindowFocusProvider
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onInteractionChanged: ((Bool) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil
    @State private var showSettings = false
    @State private var settingsTab: String = "ai"
    @State private var expandedId: UUID? = nil
    @State private var searchTerm: String = ""
    @State private var searchResults: [Record] = [] // 缓存搜索结果
    @State private var isLoadingMore: Bool = false // 是否正在加载更多
    @State private var hasMoreRecords: Bool = true // 是否还有更多记录
    @State private var isDroppingFiles: Bool = false // 是否正在拖入文件

    var body: some View {
        ZStack(alignment: .center) {
            // 键盘拦截层（最底层，不阻挡点击事件）
            KeyboardInterceptViewRepresentable()
                .allowsHitTesting(false)

            if focus.mode == .floatingBall {
                FloatingBallView(store: store, focus: focus)
                    .transition(.opacity) // 简化转换，移除复杂的 scale 转换以提升性能
                    .zIndex(1)
            } else {
                baseContentView
                    .background(Color.themeBackground.opacity(0.9))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
                    .shadow(color: Color.themeShadowHeavy, radius: 20, x: 0, y: 10)
                    .transition(.opacity) // 简化转换，移除复杂的 scale 转换以提升性能
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onHover { hovering in onHoverChanged?(hovering) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { _ in onInteractionChanged?(true) }
                .onEnded { _ in onInteractionChanged?(false) }
        )
        .allowsHitTesting(true)
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.showSettings.name)) { _ in
            // 响应显示设置界面的通知
            showSettings = true
            settingsTab = "ai"
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.expandRecord.name)) { notification in
            // 响应展开特定记录的通知
            if let recordId = notification.object as? UUID {
                expandedId = recordId
                showSettings = false // 确保不在设置界面
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .escKeyPressed)) { _ in
            print("[DEBUG] ESC notification received")
            // ESC键缩小到浮球或取消展开
            if expandedId != nil {
                expandedId = nil
            } else if showSettings {
                showSettings = false
            } else {
                print("[DEBUG] ESC calling onMinimize via notification")
                onMinimize?()
            }
        }
    }

    // MARK: - 子视图组件

    /// 基础内容视图，包含主要的布局结构
    private var baseContentView: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Left Sidebar (Activity)
                sidebarView

                // Right Main Content
                mainContentView
            }

            // Toast Overlay (Elevated to top level)
            toastOverlayView
        }
    }

    /// Toast 覆盖层视图
    @ViewBuilder
    private var toastOverlayView: some View {
        if let toast = store.toast {
            ToastView(message: toast)
                .padding(.top, 32)
                .padding(.trailing, 32)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
        }
    }

    /// 左侧边栏视图
    private var sidebarView: some View {
        ZStack(alignment: .top) {
            Color.themePanel // 使用主题文件中的面板颜色
            // 移除了 WindowDragHandler() - 侧边栏不再支持窗口拖拽

            VStack(spacing: 20) {
                Spacer().frame(height: 40) // 顶部留空

                // 类型筛选按钮组
                filterButton(type: RecordType.text, icon: .fileText)
                filterButton(type: RecordType.file, icon: .paperclip)
                filterButton(type: RecordType.folder, icon: .folder)

                // 分隔线
                Rectangle()
                    .fill(Color.themeBorderSubtle)
                    .frame(width: 32, height: 1)
                    .padding(.vertical, 4)

                // 未来可以增加图片和视频
                // filterButton(type: .image, icon: .image)
                // filterButton(type: .video, icon: .video)

                Spacer()

                // 热力图移至侧边栏底部
                HeatmapView(vm: heatmapVM)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 64) // 调整为固定 64px
        .zIndex(10)
        .overlay(Rectangle().frame(width: ThemeSpacing.border1, height: nil, alignment: .trailing).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .trailing)
    }

    /// 类型筛选按钮
    private func filterButton(type: RecordType, icon: IconName) -> some View {
        let isSelected = store.filterType == type

        return Button(action: {
            withAnimation(.spring(response: 0.3)) {
                store.toggleFilterType(type)
            }
        }) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.themeBlue600.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .transition(.scale.combined(with: .opacity))
                }

                LucideView(
                    name: icon,
                    size: 20,
                    color: isSelected ? .themeBlue400 : .themeGray400
                )
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(isSelected ? "取消筛选" : "筛选\(type.rawValue)")
    }

    /// 右侧主内容视图
    private var mainContentView: some View {
        ZStack {
            Color.themeBackground.opacity(0.9) // bg-gray-900/90

            VStack(spacing: 0) {
                headerView
                contentView
            }
        }
    }
    
    /// 头部视图
    private var headerView: some View {
        ZStack(alignment: .top) {
            // 原有内容
            HStack {
                // Window Controls (Custom Red Dot)
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    // Close (Red)
                    CloseButton(onClose: onClose)

                    // Minimize (Yellow)
                    ShrinkButton(onMinimize: onMinimize)
                }
                .padding(.leading, ThemeSpacing.px4.rawValue)

                Spacer()

                Text(showSettings ? "偏好设置" : "闪记")
                    .font(.themeH2) // 使用主题文件中的字体定义
                    .foregroundColor(.themeTextPrimary) // 使用主题文件中的文本颜色

                Spacer()

                // Bluetooth Icon (Lucide)
                bluetoothView
            }
            .frame(height: ThemeSpacing.h12.rawValue) // 使用主题文件中的高度定义
            .background(Color.themeBackground.opacity(0.5)) // bg-gray-900/50
            .overlay(Rectangle().frame(width: nil, height: ThemeSpacing.border1, alignment: .bottom).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)

            // 拖拽手柄 - 只在顶部 24px 区域有效
            Color.clear
                .frame(height: 24)
                .contentShape(Rectangle())
                .background(WindowDragHandler())
                .allowsHitTesting(true)
        }
    }

    /// 蓝牙视图
    private var bluetoothView: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            // 截图按钮
            HStack(spacing: 4) {
                HoverButton(icon: .camera, size: 16) {
                    ScreenshotService.shared.startScreenshot()
                }
                .help("截图 (⌥⌘C)")

                HoverButton(icon: .bug, size: 14) {
                    V2ScreenshotDebugController.show()
                }
                .help("验证截图布局 (Debug)")
            }

            Group {
                if let name = bluetooth.connectedDeviceName {
                    LucideView(name: .bluetoothConnected, size: 14, color: .themeBlue400)
                        .help("已连接: \(name)")
                } else if bluetooth.state == .poweredOn {
                    LucideView(name: .bluetooth, size: 14, color: .themeYellow500)
                        .help("蓝牙已开启，未连接")
                } else {
                    LucideView(name: .bluetoothOff, size: 14, color: .themeTextTertiary)
                        .help("蓝牙未开启")
                }
            }
            .font(.themeBody)
            .frame(width: ThemeSpacing.px4.rawValue, height: ThemeSpacing.px4.rawValue) // Ensure it has size
            .contentShape(Rectangle()) // Make sure it's clickable/hoverable
            .onTapGesture {
                settingsTab = "bluetooth"
                withAnimation(.easeInOut(duration: ThemeDuration._300.rawValue)) { showSettings = true }
            }
            .pointingHandCursor()

            HoverButton(icon: .settings, size: 16, isActive: showSettings) {
                settingsTab = "ai"
                withAnimation(.easeInOut(duration: ThemeDuration._300.rawValue)) { showSettings.toggle() }
            }
        }
        .padding(.trailing, ThemeSpacing.px4.rawValue)
    }

    /// 内容视图
    @ViewBuilder
    private var contentView: some View {
        if showSettings {
            SettingsOverlayView(store: store, bluetooth: bluetooth, showSettings: $showSettings, initialTab: settingsTab)
                .transition(.slideRight) // 使用主题文件中的过渡动画
        } else {
            mainListView
        }
    }

    /// 主列表视图
    private var mainListView: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBarView

            // List Content
            listContentView

            // Bottom Status Bar
            statusBarView
        }
    }

    /// 搜索栏视图
    private var searchBarView: some View {
        EnhancedSearchBar(store: store, searchTerm: $searchTerm)
            .disabled(!focus.isKeyWindow)
    }

    /// 列表内容视图
    private var listContentView: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) { // 使用LazyVStack提高性能，并固定Header
                    if searchTerm.isEmpty {
                        if store.records.isEmpty {
                            emptyStateView
                        } else {
                            let starred = store.records.filter { $0.starred }
                            let others = store.records.filter { !$0.starred }

                            // 收藏部分
                            if !starred.isEmpty {
                                Section(header: starredSectionHeader(count: starred.count)) {
                                    // 使用动画包裹收藏列表内容，根据收藏数量调整动画时间
                                    animatedStarredListView(starred: starred)
                                        .padding(.top, 4) // 增加与 Header 的间距
                                }
                            }

                            // 其他记录部分
                            if !others.isEmpty {
                                Section(header: !starred.isEmpty ? otherSectionHeader : nil) {
                                    listViewContent(items: others)
                                }
                            }

                            // 加载更多指示器
                            if hasMoreRecords {
                                loadMoreIndicatorView
                                    .onAppear {
                                        loadMoreRecords()
                                    }
                            }
                        }
                    } else {
                        let items = Array(searchResults.prefix(50))
                        if items.isEmpty {
                            emptyStateView
                        } else {
                            listViewContent(items: items)
                        }
                    }
                }
                .padding(16) // p-4
            }
            .onDrop(of: [.item, .fileURL, .text, .url], isTargeted: $isDroppingFiles) { providers in
                print("[DEBUG] onDrop 被调用！providers 数量: \(providers.count)")
                handleDroppedFiles(providers: providers)
                return true
            }

            // 拖入视觉反馈动画
            if isDroppingFiles {
                dropFeedbackOverlay
                    .allowsHitTesting(false)  // 让事件穿透到下层的 onDrop
            }
        }
        .onChange(of: searchTerm) { newValue in
            // 使用防抖搜索，避免频繁搜索
            store.debouncedSearch(newValue) { results in
                searchResults = results
                // 重置分页状态
                hasMoreRecords = results.count >= 50
            }
        }
        .onAppear {
            // 初始化时设置搜索结果
            if searchTerm.isEmpty {
                // 确保记录已加载
                if store.records.isEmpty {
                    store.loadFromStore(pageSize: 50, offset: 0)
                }
                // 检查是否还有更多记录
                hasMoreRecords = store.records.count >= 50
            } else {
                // 使用防抖搜索，避免频繁搜索
                store.debouncedSearch(searchTerm) { results in
                    searchResults = results
                    hasMoreRecords = results.count >= 50
                }
            }
        }
    }

    /// 拖入文件的视觉反馈覆盖层
    private var dropFeedbackOverlay: some View {
        ZStack {
            // 半透明蒙层
            Color.themeBlue500.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // 上传图标（带脉冲动画）
                ZStack {
                    Circle()
                        .fill(Color.themeBlue500.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isDroppingFiles ? 1.2 : 1.0)
                        .opacity(isDroppingFiles ? 0.5 : 0.0)

                    Circle()
                        .fill(Color.themeBlue500.opacity(0.3))
                        .frame(width: 60, height: 60)

                    LucideView(name: .upload, size: 32, color: .themeBlue400)
                }

                Text("松开即可导入文件")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.themeBlue400)

                Text("支持单个文件或整个文件夹")
                    .font(.system(size: 12))
                    .foregroundColor(.themeTextSecondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.themeBackground)
                    .shadow(color: Color.themeShadowBlue, radius: 20, x: 0, y: 4)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDroppingFiles)
    }

    /// 处理拖入的文件
    private func handleDroppedFiles(providers: [NSItemProvider]) {
        print("[DEBUG] handleDroppedFiles 被调用，providers 数量: \(providers.count)")

        let dispatchGroup = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            dispatchGroup.enter()

            let types = provider.registeredTypeIdentifiers
            print("[DEBUG] provider 注册的类型: \(types)")

            // 优先尝试 URL
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        print("[DEBUG] 成功解析为 URL: \(url.path)")
                        urls.append(url)
                    }
                    dispatchGroup.leave()
                }
            }
            // 其次尝试 String
            else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { str, error in
                    if let str = str {
                        print("[DEBUG] 成功解析为 String: \(str)")
                        if str.starts(with: "/") {
                            let url = URL(fileURLWithPath: str)
                            urls.append(url)
                        }
                    }
                    dispatchGroup.leave()
                }
            }
            else {
                // 如果都失败了，尝试通过 loadItem 加载原始数据
                if let firstType = types.first {
                    print("[DEBUG] 尝试加载第一个类型的数据: \(firstType)")
                    provider.loadItem(forTypeIdentifier: firstType, options: nil) { item, error in
                        if let url = item as? URL {
                            print("[DEBUG] loadItem 成功获取 URL: \(url.path)")
                            urls.append(url)
                        } else if let data = item as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) {
                            print("[DEBUG] loadItem 从 Data 获取到 URL: \(url.path)")
                            urls.append(url)
                        } else if let item = item {
                            print("[DEBUG] loadItem 获取到未知对象类型: \(type(of: item))")
                        }
                        dispatchGroup.leave()
                    }
                } else {
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: DispatchQueue.main) {
            if !urls.isEmpty {
                print("[DEBUG] 最终接收到 \(urls.count) 个文件")
                store.handleDroppedUrls(urls)
                HapticFeedbackManager.shared.mediumImpact()
                store.postToast("已导入 \(urls.count) 个文件", type: "success")
            } else {
                print("[DEBUG] 未能解析到任何有效内容")
                store.postToast("未能解析文件", type: "error")
            }
        }
    }

    /// 收藏部分 Header
    private func starredSectionHeader(count: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.isStarredCollapsed.toggle()
            }
        }) {
            HStack(spacing: 8) {
                LucideView(name: .star, size: 14, color: .themeYellow500)
                Text("已收藏 (\(count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeTextPrimary)

                Spacer()

                LucideView(name: .chevronRight, size: 12, color: .themeGray400)
                    .rotationEffect(.degrees(store.isStarredCollapsed ? 0 : 90))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.themeBackground) // 使用背景色，让它看起来像个真正的 Section Header
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .padding(.bottom, 4)
    }

    /// 其他部分 Header
    private var otherSectionHeader: some View {
        HStack {
            Text("所有记录")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeGray400)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.themeBackground)
    }

    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .opacity(0.2)
            Text("没有找到匹配的记录。")
                .font(.system(size: 14)) // text-sm
                .foregroundColor(.themeTextSecondary)
        }
        .frame(height: 300)
    }

    /// 列表内容视图
    @ViewBuilder
    private func listViewContent(items: [Record]) -> some View {
        let filtered = store.filterType == nil ? items : items.filter { $0.type == store.filterType }
        
        ForEach(filtered, id: \.id) { record in // 明确指定 id
            RecordCardView(
                record: record,
                expandedId: $expandedId,
                searchTerm: $searchTerm,
                store: store
            )
            .equatable() // 使用 Equatable 减少重绘
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
        }
    }

    /// 为收藏列表提供动画效果的视图
    /// - Parameter starred: 收藏的记录数组
    /// - Returns: 带动画效果的收藏列表视图
    @ViewBuilder
    private func animatedStarredListView(starred: [Record]) -> some View {
        // 根据收藏数量动态调整动画时间
        let animationDuration = calculateAnimationDuration(for: starred.count)

        // 如果收藏数量很多（比如超过50条），只显示前50条，并提供"查看更多"的提示
        let displayCount = min(starred.count, 50)
        let displayRecords = Array(starred.prefix(displayCount))

        VStack(spacing: 12) {
            // 显示前50条记录
            ForEach(displayRecords) { record in
                RecordCardView(
                    record: record,
                    expandedId: $expandedId,
                    searchTerm: $searchTerm,
                    store: store
                )
                .equatable() // 使用 Equatable 减少重绘
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.8, anchor: .top))
                ))
            }

            // 如果还有更多记录，显示"查看更多"提示
            if starred.count > 50 {
                HStack {
                    Spacer()
                    Text("还有 \(starred.count - 50) 条收藏记录...")
                        .font(.system(size: 12))
                        .foregroundColor(.themeTextTertiary)
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 可以在这里实现展开全部的逻辑，暂时先不做
                }
            }
        }
        .opacity(store.isStarredCollapsed ? 0 : 1)
        .scaleEffect(y: store.isStarredCollapsed ? 0.1 : 1.0, anchor: .top)
        .frame(height: store.isStarredCollapsed ? 0 : nil)
        .clipped()
        .animation(.easeInOut(duration: animationDuration), value: store.isStarredCollapsed)
    }

    /// 根据列表大小计算动画持续时间
    /// - Parameter count: 列表项数量
    /// - Returns: 动画持续时间（秒）
    private func calculateAnimationDuration(for count: Int) -> Double {
        if count <= 10 {
            return 0.15
        } else if count <= 20 {
            return 0.2
        } else if count <= 50 {
            return 0.25
        } else {
            return 0.3
        }
    }

    /// 加载更多记录的方法
    private func loadMoreRecords() {
        guard !isLoadingMore && hasMoreRecords else { return }

        isLoadingMore = true

        // 使用 RecordStore 的 loadMoreRecords 方法
        let previousCount = store.records.count
        store.loadMoreRecords()

        // 检查是否还有更多记录
        hasMoreRecords = store.records.count > previousCount && store.records.count >= 50
        isLoadingMore = false
    }

    /// 加载更多指示器视图
    private var loadMoreIndicatorView: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
                    .scaleEffect(0.8)
                Text("加载更多...")
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
            } else {
                Text("向上滑动加载更多")
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// 状态栏视图
    private var statusBarView: some View {
        let base = heatmapVM.filteredRecords()
        // 使用缓存的搜索结果，避免重复搜索
        let items = searchTerm.isEmpty ? base : searchResults

        return HStack {
            Text("记录条数: \(store.records.count) 条 (已过滤: \(store.records.count - items.count))")
            Spacer()
            Text("AI: \(store.enableAI ? "ON (阈值 > \(store.summaryTrigger) 字符)" : "OFF")")
        }
        .font(.system(size: 10)) // text-[10px]
        .foregroundColor(.themeTextSecondary) // 使用主题文件中的文本颜色
        .padding(.horizontal, 16)
        .frame(height: 32) // h-8
        .background(Color.black.opacity(0.2)) // bg-black/20
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .top)
    }
}

// MARK: - 键盘事件处理修饰符

/// 键盘事件处理修饰符，处理不同 macOS 版本的兼容性
struct KeyboardHandlerModifier: ViewModifier {
    @Binding var expandedId: UUID?
    @Binding var showSettings: Bool
    var onMinimize: (() -> Void)?

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.escape) {
                    // ESC键缩小到浮球或取消展开
                    print("[DEBUG] ESC pressed: expandedId=\(expandedId?.uuidString ?? "nil"), showSettings=\(showSettings)")
                    if expandedId != nil {
                        expandedId = nil
                        return .handled
                    } else if showSettings {
                        showSettings = false
                        return .handled
                    } else {
                        print("[DEBUG] ESC calling onMinimize")
                        onMinimize?()
                        return .handled
                    }
                }
        } else {
            // 对于旧版本 macOS，暂时不提供键盘快捷键支持
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
