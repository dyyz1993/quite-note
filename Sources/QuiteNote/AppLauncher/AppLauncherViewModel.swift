import SwiftUI
import AppKit

/// 启动器结果条目：应用 / 系统命令 / 文件 / 收藏·备忘文本 / 范围入口混合列表的统一身份
enum LauncherItem: Identifiable {
    case app(LauncherApp)
    case command(LauncherCommand)
    case file(LauncherFile)
    case text(LauncherTextItem)
    case scope(LauncherScopeParser.Match)
    case web(LauncherWebSearch.Query)
    case quit(LauncherQuitService.Target)

    var id: String {
        switch self {
        case .app(let app): return "app:" + app.id
        case .command(let cmd): return "cmd:" + cmd.id
        case .file(let file): return "file:" + file.id
        case .text(let item): return "text:" + item.id
        case .scope: return "scope:files"
        case .web(let q): return "web:" + q.presetName + q.term
        case .quit(let t): return "quit:" + t.bundleID
        }
    }
}

/// 启动器输入状态（class 承载：延迟回调写状态在 NSHostingView 下要引用语义才可靠）
///
/// 性能设计（2026-09-11 第二轮）：搜索计算本身 <1ms（LauncherApp 预计算字段），
/// 剩余卡点在**视图更新层**——每个按键都全量刷新列表会引发连续的行重建/重排。
/// 因此：① 30ms 合并防抖（远低于 ~100ms 感知阈值，快速连击"12345"只刷一次）；
/// ② 列表上限 20 行（Alfred 级）；③ 选中态只在变化时发布。
@MainActor
final class AppLauncherViewModel: ObservableObject {
    /// 列表展示上限：宽泛查询（如单字符）bundleID/子序列会命中大量应用，封顶控制列表规模
    static let maxVisible = 20

    /// 快速输入合并窗口：连击期间只做一次搜索+发布
    private let coalesceInterval: TimeInterval = 0.03
    private var coalesceWork: DispatchWorkItem?

    @Published var searchText = "" {
        didSet { scheduleRecompute() }
    }
    @Published private(set) var results: [LauncherItem] = []
    @Published var selectedIndex = 0

    /// 非空 = 当前输入是可求值算式（"12+34"），面板顶部显示结果卡，回车复制
    @Published private(set) var calculatorResult: String?

    /// 破坏性系统命令（重启/关机/清废纸篓）第一次回车只亮确认提示，
    /// 该字段记录等待二次确认的命令 id（视图据此显示"再按一次 ↵ 确认"）
    @Published private(set) var pendingConfirmCommandID: String?
    private var pendingConfirmDate: Date?
    private let confirmWindow: TimeInterval = 4

    /// 当前查询分词（归一化后），供名称高亮与区段判断
    private(set) var queryTokens: [String] = []

    /// `f ` 前缀文件搜索模式
    private(set) var isFileMode = false

    var isRecentMode: Bool { queryTokens.isEmpty && !isFileMode }

    /// 按键入口：30ms 窗口内合并连击（延迟远低于感知阈值，但把逐键的列表刷新合并成一次）
    private func scheduleRecompute() {
        coalesceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recompute()
        }
        coalesceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
    }

    /// 全量重算：搜索 + 截断 + 选中归零（防抖到期、目录扫描完成、面板重开时调用）
    func recompute() {
        let t0 = DispatchTime.now()
        pendingConfirmCommandID = nil

        // `f ` 前缀：文件搜索模式（Spotlight 异步查询，结果回调后落列表）
        if FileModeParser.isFileMode(searchText) {
            isFileMode = true
            queryTokens = []
            calculatorResult = nil
            results = []
            let term = FileModeParser.fileTerm(searchText)
            LauncherFileSearch.shared.search(term) { [weak self] files in
                guard let self, self.isFileMode else { return }
                self.results = files.prefix(Self.maxVisible).map { .file($0) }
            }
            return
        }
        isFileMode = false
        LauncherFileSearch.shared.cancel()

        queryTokens = AppSearchService.tokenize(searchText)
        // 算式优先：输入像算式且可求值 → 顶部出结果卡（输入中途 "12+" 也切计算模式，求值失败不显示）
        if LauncherCalculator.looksLikeExpression(searchText),
           let value = LauncherCalculator.evaluate(searchText) {
            calculatorResult = LauncherCalculator.formatResult(value)
        } else {
            calculatorResult = nil
        }
        let store = AppCatalogStore.shared
        // 排序：范围入口 → 收藏片段/备忘（用户高频内容）→ 系统命令 → 应用
        var items: [LauncherItem] = []
        // 网页搜索："搜索 swift 泛型" → 首行"在 Google 搜索"（退出应用的结果混排其后）
        if let web = LauncherWebSearch.parse(searchText) {
            items.append(.web(web))
        }
        if let quitTargets = LauncherQuitService.parse(searchText) {
            items += quitTargets.map { .quit($0) }
        }
        if let scope = LauncherScopeParser.parse(searchText) {
            // 输入范围词：未跟词 → 亮范围行等 ↵/空格；已跟词 → 直接进文件模式
            if scope.entered {
                isFileMode = true
                calculatorResult = nil
                results = []
                LauncherFileSearch.shared.search(scope.term) { [weak self] files in
                    guard let self, self.isFileMode else { return }
                    self.results = files.prefix(Self.maxVisible).map { .file($0) }
                }
                return
            }
            items.append(.scope(scope))
        }
        items += LauncherTextSearch.matchingItems(
            tokens: queryTokens, in: LauncherTextSearch.collect()
        ).map { .text($0) }
        items += SystemCommandService.matchingCommands(tokens: queryTokens)
            .map { .command($0) }
        items += AppSearchService.search(searchText, in: store.apps, recentIDs: store.recentIDs)
            .prefix(Self.maxVisible)
            .map { .app($0) }
        results = items
        pendingConfirmCommandID = nil
        if selectedIndex != 0 { selectedIndex = 0 }
        // 性能埋点：只在异常（计算 >5ms）时落盘，正常按键不打日志（防刷屏）；
        // 需要全量数据定位时临时放开此条件即可
        let t1 = DispatchTime.now()
        DispatchQueue.main.async {
            let t2 = DispatchTime.now()
            let searchMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            let commitMs = Double(t2.uptimeNanoseconds - t1.uptimeNanoseconds) / 1_000_000
            if searchMs > 5 || commitMs > 50 {
                DiagnosticCenter.warning("Launcher", "搜索性能异常：计算 \(String(format: "%.2f", searchMs))ms · 提交 \(String(format: "%.1f", commitMs))ms · 目录 \(store.apps.count) → 结果 \(self.results.count)")
            }
        }
    }

    func resetInput() {
        coalesceWork?.cancel()
        searchText = ""
        recompute()   // 面板重开要立即可见，不走防抖
    }

    // MARK: - 键盘动作（由面板控制器 onKeyAction 分发）

    func handle(_ action: AppLauncherKeyAction, controller: AppLauncherPanelController) {
        switch action {
        case .moveUp:
            guard !results.isEmpty else { return }
            pendingConfirmCommandID = nil
            selectedIndex = (selectedIndex - 1 + results.count) % results.count
        case .moveDown:
            guard !results.isEmpty else { return }
            pendingConfirmCommandID = nil
            selectedIndex = (selectedIndex + 1) % results.count
        case .copyCalcFull:
            copyCalculatorFull(controller: controller)
        case .launchSelected:
            // 算式模式下回车 = 复制结果（Alfred 同款优先级；⌘1–9 仍可直开下方应用）
            if calculatorResult != nil {
                copyCalculatorResult(controller: controller)
                return
            }
            activateItem(at: selectedIndex, controller: controller)
        case .launchIndex(let digit):
            activateItem(at: digit - 1, controller: controller)
        case .escape:
            // Alfred 式：ESC 直接关面板（有二次确认态先撤确认）。
            // 不做"先清搜索词"——搜狗等中文输入法会吞 ESC（关它自己的候选窗），
            // keyDown 到不了 app；若第一跳被吞，用户按第二个 ESC 时必须能立刻退出，
            // 中间再多一层"清词"会变成"按了没反应"的坏体验
            if pendingConfirmCommandID != nil {
                pendingConfirmCommandID = nil
            } else {
                controller.hide()
            }
        }
    }

    /// 激活结果条目：命令走执行（破坏性的先二次确认），应用走启动，文件走默认应用打开
    private func activateItem(at index: Int, controller: AppLauncherPanelController) {
        guard results.indices.contains(index) else { return }
        switch results[index] {
        case .app(let app):
            launch(app, controller: controller)
        case .command(let cmd):
            confirmOrExecute(cmd, controller: controller)
        case .file(let file):
            openFile(file, controller: controller)
        case .text(let item):
            copyTextItem(item, controller: controller)
        case .scope:
            enterFileScope(controller: controller)
        case .web(let query):
            controller.hide()
            NSWorkspace.shared.open(query.url)
            DiagnosticCenter.info("Launcher", "网页搜索：\(query.presetName)「\(query.term)」")
        case .quit(let target):
            controller.hide()
            let ok = target.terminate()
            DiagnosticCenter.info("Launcher", "\(ok ? "已退出" : "退出失败")「\(target.appName)」")
        }
    }

    /// 用默认应用打开文件（目录 = 在 Finder 打开）
    private func openFile(_ file: LauncherFile, controller: AppLauncherPanelController) {
        controller.hide()
        NSWorkspace.shared.open(file.url)
        DiagnosticCenter.info("Launcher", "打开文件：\(file.url.path)")
    }

    /// 进入文件搜索范围（↵/点击范围行）：搜索框变成 ' 前缀，保留已输入的词
    func enterFileScope(controller: AppLauncherPanelController) {
        let term = queryTokens.dropFirst().joined(separator: " ")
        coalesceWork?.cancel()
        searchText = term.isEmpty ? "'" : "' " + term
        recompute()
    }

    /// 点击网页搜索行（与回车同语义）
    func activateWeb(_ query: LauncherWebSearch.Query, controller: AppLauncherPanelController) {
        controller.hide()
        NSWorkspace.shared.open(query.url)
        DiagnosticCenter.info("Launcher", "网页搜索：\(query.presetName)「\(query.term)」")
    }

    /// 点击退出应用行（与回车同语义）
    func activateQuit(_ target: LauncherQuitService.Target, controller: AppLauncherPanelController) {
        controller.hide()
        let ok = target.terminate()
        DiagnosticCenter.info("Launcher", "\(ok ? "已退出" : "退出失败")「\(target.appName)」")
    }

    /// 点击文件行（与回车同语义）
    func openFileTap(_ file: LauncherFile, controller: AppLauncherPanelController) {
        openFile(file, controller: controller)
    }

    /// 复制收藏片段/备忘到剪贴板（↵ 与点击同语义；面板收起后 ⌘V 粘贴）。
    /// 文本条目写字符串；图片条目写原始图片数据。
    /// 复制会经剪贴板监控进入历史（成为最新一条），属预期行为
    func copyTextItem(_ item: LauncherTextItem, controller: AppLauncherPanelController) {
        controller.hide()
        if let imagePath = item.imagePath {
            if LauncherTextSearch.copyImageToPasteboard(imagePath: imagePath) {
                DiagnosticCenter.info("Launcher", "已复制收藏图片「\(item.title)」")
            } else {
                DiagnosticCenter.error("Launcher", "收藏图片读取失败：\(imagePath)")
            }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.copyText, forType: .string)
        DiagnosticCenter.info("Launcher", "已复制\(item.kind == .favorite ? "收藏片段" : "备忘")「\(item.title)」（\(item.copyText.utf8.count) 字节）")
    }

    /// 点击命令行（与回车同语义：破坏性命令也要二次点击确认）
    func handleCommandTap(_ cmd: LauncherCommand, controller: AppLauncherPanelController) {
        confirmOrExecute(cmd, controller: controller)
    }

    /// 破坏性命令 4 秒内二次回车/点击才执行；换词/移动/按 Esc 都会撤销确认态
    private func confirmOrExecute(_ cmd: LauncherCommand, controller: AppLauncherPanelController) {
        if cmd.requiresConfirmation {
            if pendingConfirmCommandID == cmd.id,
               let date = pendingConfirmDate,
               Date().timeIntervalSince(date) < confirmWindow {
                executeCommand(cmd, controller: controller)
            } else {
                pendingConfirmCommandID = cmd.id
                pendingConfirmDate = Date()
            }
        } else {
            executeCommand(cmd, controller: controller)
        }
    }

    private func executeCommand(_ cmd: LauncherCommand, controller: AppLauncherPanelController) {
        pendingConfirmCommandID = nil
        controller.hide()
        SystemCommandService.execute(cmd.action, title: cmd.title)
    }

    /// 复制计算结果并收起面板（↵ 默认路径，99% 场景）
    func copyCalculatorResult(controller: AppLauncherPanelController) {
        guard let result = calculatorResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        controller.hide()
        DiagnosticCenter.info("Launcher", "计算结果已复制：\(searchText) = \(result)")
    }

    /// 复制整式（⌘↵）："12+34 = 46"，用归一化算式（全角已转 ASCII）
    func copyCalculatorFull(controller: AppLauncherPanelController) {
        guard let result = calculatorResult else { return }
        let full = "\(LauncherCalculator.normalizeExpression(searchText)) = \(result)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        controller.hide()
        DiagnosticCenter.info("Launcher", "计算整式已复制：\(full)")
    }

    /// 先收面板再启动（避免面板抢焦点），启动结果落日志
    func launch(_ app: LauncherApp, controller: AppLauncherPanelController) {
        AppCatalogStore.shared.recordLaunch(app)
        controller.hide()
        let url = app.url
        let name = app.name
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                DiagnosticCenter.error("Launcher", "启动「\(name)」失败：\(error.localizedDescription)")
            } else {
                DiagnosticCenter.info("Launcher", "已启动「\(name)」")
            }
        }
    }
}
