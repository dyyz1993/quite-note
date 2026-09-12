import SwiftUI
import AppKit

/// 应用启动器面板内容：搜索框 + 结果列表 + 键位提示（深色主题）
///
/// 崩溃红线（同剪贴板面板）：本窗口内容禁止 withAnimation/transition，
/// 键盘操作全部经控制器的 localMonitor → onKeyAction → VM，不走 SwiftUI onKeyPress。
/// 搜索结果从 VM 缓存读取（按键时同步算好），body 不做任何搜索计算。
struct AppLauncherView: View {
    let controller: AppLauncherPanelController

    @ObservedObject private var store = AppCatalogStore.shared
    @StateObject private var vm = AppLauncherViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Rectangle().fill(Color.themeWhite10).frame(height: 1)
            listArea
            Rectangle().fill(Color.themeWhite10).frame(height: 1)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
        // 隐藏标题栏仍会预留 ~28pt 安全区，顶进该区域让搜索栏贴顶（用户要求紧凑）
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            wireKeyHandler()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.appLauncherPanelDidShow.name)) { _ in
            // 面板每次唤起：清空输入、聚焦搜索框、重接键盘处理器
            //（hosted view 不随面板隐藏销毁，onAppear 只触发一次）
            vm.resetInput()
            searchFocused = true
            wireKeyHandler()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.appLauncherCatalogDidUpdate.name)) { _ in
            // 扫描在后台异步完成，落库时重算当前查询的结果
            //（不用 .onChange(of: store.apps)：那会在每次按键 body 重算时对全目录做 Equatable 扫描）
            vm.recompute()
        }
        .onChange(of: vm.results.count) { _ in syncPanelHeight() }
        .onChange(of: vm.calculatorResult) { _ in syncPanelHeight() }
        .onChange(of: vm.isRecentMode) { _ in syncPanelHeight() }
    }

    // MARK: - 高度自适应（结果几条面板就多高，Alfred 式）

    /// 按当前内容计算面板目标高度；结果数/模式/算式卡变化时经 onChange 同步
    private func syncPanelHeight() {
        controller.applyContentHeight(preferredPanelHeight())
    }

    private func preferredPanelHeight() -> CGFloat {
        let searchBar: CGFloat = 34   // 搜索行（上下 4pt 边距 + 文本行高）
        let dividers: CGFloat = 2
        let footerH: CGFloat = 30
        var h = searchBar + dividers + footerH
        if vm.results.isEmpty {
            h += 118                  // 空态（含上下留白）
        } else {
            h += 24 + CGFloat(vm.results.count) * 42  // 区段标题 + 行（icon 28 + 上下 6pt 边距）
        }
        if vm.calculatorResult != nil { h += 50 }
        return h
    }

    // MARK: - 搜索区

    private var searchRow: some View {
        HStack(spacing: 10) {
            LucideView(name: .search, size: 20, color: .themeTextTertiary)
            TextField("搜索应用…", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.themeTextPrimary)
                .focused($searchFocused)
            if !vm.searchText.isEmpty {
                LucideView(name: .x, size: 14, color: .themeTextTertiary)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.searchText = "" }
                    .pointingHandCursor()
            }
            Text("esc 关闭")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.themeWhite5)
                .cornerRadius(5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 列表

    private var listArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let calcResult = vm.calculatorResult {
                        calculatorCard(calcResult)
                    }
                    if !vm.results.isEmpty {
                        sectionTitle
                    }
                    ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, item in
                        row(index, item)
                    }
                    if vm.results.isEmpty && vm.calculatorResult == nil {
                        emptyState
                    }
                }
            }
            .onChange(of: vm.selectedIndex) { _ in
                guard vm.results.indices.contains(vm.selectedIndex) else { return }
                proxy.scrollTo(vm.results[vm.selectedIndex].id, anchor: .center)
            }
        }
    }

    /// 计算结果卡（输入算式时置顶显示，回车/点击复制）
    private func calculatorCard(_ result: String) -> some View {
        HStack(spacing: 10) {
            Text("=")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.themeBlue300)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.themeBlue600.opacity(0.25)))
            VStack(alignment: .leading, spacing: 1) {
                Text(result)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(.themeTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("计算结果 · ↵ 复制 · ⌘↵ 整式")
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
            }
            Spacer()
            Text("↵ 复制")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.themeBlue400)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.copyCalculatorResult(controller: controller)
        }
    }

    private var sectionTitle: some View {
        HStack {
            Text(vm.isFileMode ? "文件结果" : (vm.isRecentMode ? "最近使用" : "搜索结果"))
            Spacer()
            Text(vm.isFileMode ? "\(vm.results.count) 个文件" : "\(vm.results.count) 个应用")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.themeTextTertiary)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 3)
    }

    @ViewBuilder
    private func row(_ index: Int, _ item: LauncherItem) -> some View {
        switch item {
        case .app(let app): appRow(index, app)
        case .command(let cmd): commandRow(index, cmd)
        case .file(let file): fileRow(index, file)
        case .text(let item): textRow(index, item)
        }
    }

    /// 收藏片段/备忘行：↵ 复制内容/图片到剪贴板
    private func textRow(_ index: Int, _ item: LauncherTextItem) -> some View {
        let selected = index == vm.selectedIndex
        let isFav = item.kind == .favorite
        let tint = isFav ? Color(red: 0.2, green: 0.83, blue: 0.6) : Color(red: 0.98, green: 0.75, blue: 0.14)
        return HStack(spacing: 10) {
            Text(index < 9 ? String(index + 1) : "·")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .themeBlue400 : .themeTextTertiary)
                .frame(width: 14)

            if item.imagePath != nil {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.14)))
            } else {
                LucideView(name: isFav ? .star : .fileText, size: 15, color: tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.14)))
            }

            VStack(alignment: .leading, spacing: 1) {
                titleText(item.title)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.themeTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(isFav ? "收藏" : "备忘")
                .font(.system(size: 10))
                .foregroundColor(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.13)))
                .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))

            if selected {
                HStack(spacing: 4) {
                    Text("↵").font(.system(size: 11, weight: .semibold))
                    Text("复制").font(.system(size: 11))
                }
                .foregroundColor(.themeBlue400)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.themeBlue600.opacity(0.20) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.themeBlue500).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && vm.selectedIndex != index {
                vm.selectedIndex = index
            }
        }
        .onTapGesture {
            vm.copyTextItem(item, controller: controller)
        }
    }

    private func fileRow(_ index: Int, _ file: LauncherFile) -> some View {
        let selected = index == vm.selectedIndex
        return HStack(spacing: 10) {
            Text(index < 9 ? String(index + 1) : "·")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .themeBlue400 : .themeTextTertiary)
                .frame(width: 14)

            Image(nsImage: store.fileIcon(for: file.url))
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 1) {
                titleText(file.name)
                Text(Self.abbreviatedPath(file.url.path))
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(file.badgeText)
                .font(.system(size: 10))
                .foregroundColor(.themeBlue300)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.themeBlue600.opacity(0.14)))
                .overlay(Capsule().stroke(Color.themeBlue600.opacity(0.35), lineWidth: 1))
                .lineLimit(1)

            if let date = file.modifiedDate {
                Text(Self.relativeTime(from: date))
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.themeBlue600.opacity(0.20) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.themeBlue500).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && vm.selectedIndex != index {
                vm.selectedIndex = index
            }
        }
        .onTapGesture {
            openFileDirect(file)
        }
    }

    /// 文件路径 ~ 缩写（/Users/xxx → ~）
    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// 应用行副标题：任一搜索 token 命中 bundleID → 显示 bundleID（解释命中原因）；
    /// 否则显示应用所在目录（~ 缩写），比裸 bundleID 有信息量
    static func subtitle(for app: LauncherApp, tokens: [String]) -> String {
        if !app.bundleID.isEmpty,
           tokens.contains(where: { app.bundleIDLower.contains($0) }) {
            return app.bundleID
        }
        return abbreviatedPath(app.url.deletingLastPathComponent().path)
    }

    private func openFileDirect(_ file: LauncherFile) {
        vm.openFileTap(file, controller: controller)
    }

    private func commandRow(_ index: Int, _ cmd: LauncherCommand) -> some View {
        let selected = index == vm.selectedIndex
        let confirming = vm.pendingConfirmCommandID == cmd.id
        return HStack(spacing: 10) {
            Text(index < 9 ? String(index + 1) : "·")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .themeBlue400 : .themeTextTertiary)
                .frame(width: 14)

            LucideView(name: cmd.icon, size: 16, color: .themeBlue300)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.themeBlue600.opacity(0.18)))

            VStack(alignment: .leading, spacing: 1) {
                titleText(cmd.title)
                Text(cmd.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("命令")
                .font(.system(size: 10))
                .foregroundColor(.themePurple300)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.themePurple600.opacity(0.15)))
                .overlay(Capsule().stroke(Color.themePurple600.opacity(0.35), lineWidth: 1))

            if confirming {
                Text("再按一次 ↵ 确认")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.themeStatusError)
            } else if selected {
                HStack(spacing: 4) {
                    Text("↵").font(.system(size: 11, weight: .semibold))
                    Text("执行").font(.system(size: 11))
                }
                .foregroundColor(.themeBlue400)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.themeBlue600.opacity(0.20) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.themeBlue500).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && vm.selectedIndex != index {
                vm.selectedIndex = index
            }
        }
        .onTapGesture {
            vm.handleCommandTap(cmd, controller: controller)
        }
    }

    private func appRow(_ index: Int, _ app: LauncherApp) -> some View {
        let selected = index == vm.selectedIndex
        return HStack(spacing: 10) {
            // ⌘1–9 序号（第 10 条及以后淡化）
            Text(index < 9 ? String(index + 1) : "·")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .themeBlue400 : .themeTextTertiary)
                .frame(width: 14)

            Image(nsImage: store.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 1) {
                titleText(app.name)
                // 副标题：默认显示所在目录（比 bundleID 有信息量）；搜索词命中
                // bundleID 时才显示 bundleID（告诉用户为什么这条能搜出来）
                Text(Self.subtitle(for: app, tokens: vm.queryTokens))
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selected {
                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 11, weight: .semibold))
                    Text("打开")
                        .font(.system(size: 11))
                }
                .foregroundColor(.themeBlue400)
            } else if vm.isRecentMode {
                if let date = store.lastLaunchedDate(for: app.id) {
                    Text(Self.relativeTime(from: date))
                        .font(.system(size: 11))
                        .foregroundColor(.themeTextTertiary)
                }
            } else {
                Text(app.isSystem ? "系统" : "应用")
                    .font(.system(size: 10))
                    .foregroundColor(app.isSystem ? .themeBlue300 : .themeTextTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(app.isSystem ? Color.themeBlue600.opacity(0.18) : Color.themeWhite5)
                    )
                    .overlay(
                        Capsule().stroke(app.isSystem ? Color.themeBlue600.opacity(0.4) : Color.themeWhite10, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.themeBlue600.opacity(0.20) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.themeBlue500).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && vm.selectedIndex != index {
                vm.selectedIndex = index
            }
        }
        .onTapGesture {
            vm.launch(app, controller: controller)
        }
    }

    /// 标题 + 命中高亮（应用名/命令名通用；所有 token 命中区间染蓝）
    @ViewBuilder
    private func titleText(_ title: String) -> some View {
        let ranges = Self.highlightRanges(in: title, tokens: vm.queryTokens)
        if ranges.isEmpty {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.themeTextPrimary)
        } else {
            Self.highlightedName(title, ranges: ranges)
        }
    }

    /// 按区间切片拼接 Text：命中段蓝色加粗，其余原色（普通函数，ViewBuilder 不允许循环+控制流）
    private static func highlightedName(_ name: String, ranges: [Range<String.Index>]) -> Text {
        let normal = { (s: Substring) in
            Text(s).font(.system(size: 13, weight: .medium)).foregroundColor(.themeTextPrimary)
        }
        let hit = { (s: Substring) in
            Text(s).font(.system(size: 13, weight: .semibold)).foregroundColor(.themeBlue400)
        }
        var text = Text("")
        var cursor = name.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                text = text + normal(name[cursor..<range.lowerBound])
            }
            text = text + hit(name[range])
            cursor = range.upperBound
        }
        if cursor < name.endIndex {
            text = text + normal(name[cursor...])
        }
        return text
    }

    /// 收集各 token 在名称中的命中区间（大小写/变音符不敏感），排序并合并重叠
    static func highlightRanges(in name: String, tokens: [String]) -> [Range<String.Index>] {
        guard !tokens.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        for token in tokens where !token.isEmpty {
            if let range = name.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                ranges.append(range)
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        // 合并重叠区间
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            if vm.isFileMode {
                Text("没有找到匹配的文件")
                Text("覆盖家目录常用位置（桌面/文档/下载等）；要搜全部位置请在 系统设置 → Siri 与聚焦 开启 Spotlight 索引")
            } else if !store.isLoaded {
                ProgressView()
                    .scaleEffect(0.8)
                Text("正在扫描应用目录…")
            } else if !vm.queryTokens.isEmpty {
                Text("没有找到匹配 “\(vm.searchText)” 的应用")
            } else {
                Text("还没有最近使用记录")
                Text("输入应用名称、拼音或首字母缩写搜索（如 wx → 微信）")
            }
        }
        .font(.system(size: 13))
        .foregroundColor(.themeTextTertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↑↓ 选择")
            Text("↵ 打开")
            Text("⌘1–9 直接打开")
            Text("⌘W 关闭")
            Spacer()
            Text("QuiteNote · \(store.apps.count) 个应用")
        }
        .font(.system(size: 11))
        .foregroundColor(.themeTextTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.25))
    }

    // MARK: - 接线

    private func wireKeyHandler() {
        controller.onKeyAction = { [weak vm] action in
            guard let vm else { return }
            vm.handle(action, controller: AppLauncherPanelController.shared)
        }
    }

    /// 相对时间（最近使用列表右栏）
    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }
}
