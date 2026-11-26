import AppKit
import Foundation

/// 梯子操作的面板最小接口（NSPanel 天然满足；单测用假面板替身）
@MainActor
protocol KeyWindowLadderPanel: AnyObject {
    var isVisible: Bool { get }
    var isKeyWindow: Bool { get }
    func orderFrontRegardless()
    func makeKey()
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSPanel: KeyWindowLadderPanel {}

/// key 就位梯子（剪贴板面板 2026-11-20 生产验证版的共享实现）
///
/// 解决同一类问题：accessory 应用唤起速查面板时激活被系统拒绝，面板可见但
/// 不是 key window——用户打字/导航全部漏进前一个应用；被拒状态跌回后台后
/// macOS 26 的 App Nap 还会把主线程挂起（hang-sample 实锤：冻结 15s 量级）。
///
/// 三件套（剪贴板面板生产验证过；启动器面板 2026-11-26 接入同一份实现）：
/// 1. 补拉重试：前密后疏（0.05~0.7s，长间隔重试落在激活归因窗口之外全部无效），
///    每步 activate + orderFrontRegardless + makeKey 并逐步计时——某步 >0.8s
///    即熔断（被拒状态下 activate/makeKey 会同步阻塞，别把主线程堵满，
///    跳等重锤接管）；每步之后**无条件**补焦一拍（只在 makeKey 成功才补焦
///    会让"晚到的 key"无人聚焦——key✓ 但打不了字的实测坑）。
/// 2. 激活重锤：0.35s（生产日志定标：用户唤起后 0.2~0.5s 就开始打字）仍未 key
///    → 临时切 .regular 激活（有 Dock 图标的应用激活可靠），key 落地或面板
///    收起时切回 .accessory。代价是 Dock 图标闪现 <1 秒。
/// 3. App Nap 断言：面板可见期间持有 userInitiated 活动，禁止系统 nap。
///
/// 所有 AppKit / Dispatch / 日志副作用经 Environment 注入（默认真实实现），
/// 单测可用假调度器按虚拟时间推进、假面板与假环境记录副作用。
@MainActor
final class KeyWindowLadder {

    // MARK: - 可注入环境（默认走真实 AppKit / Dispatch / DiagnosticCenter）

    struct Environment {
        var activate: () -> Void
        var setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
        var beginActivity: (_ reason: String) -> NSObjectProtocol
        var endActivity: (NSObjectProtocol) -> Void
        /// 延迟调度（主队列）
        var scheduleAfter: (Double, @escaping () -> Void) -> Void
        /// 立即一拍（主队列）
        var asyncOnMain: (@escaping () -> Void) -> Void
        var now: () -> DispatchTime
        var logInfo: (_ category: String, _ message: String) -> Void
        var logWarning: (_ category: String, _ message: String) -> Void

        static let live = Environment(
            activate: { NSApp.activate(ignoringOtherApps: true) },
            setActivationPolicy: { NSApp.setActivationPolicy($0) },
            beginActivity: { reason in
                ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: reason
                )
            },
            endActivity: { ProcessInfo.processInfo.endActivity($0) },
            scheduleAfter: { delay, block in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
            },
            asyncOnMain: { block in DispatchQueue.main.async(execute: block) },
            now: { DispatchTime.now() },
            logInfo: { DiagnosticCenter.info($0, $1) },
            logWarning: { DiagnosticCenter.warning($0, $1) }
        )
    }

    /// 补拉重试延迟序列（前密后疏）
    static let retryDelays: [Double] = [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.55, 0.7]
    /// 重锤触发时刻（用户唤起后 0.2~0.5s 就开始打字，越早越好）
    static let hammerDelay: Double = 0.35
    /// 重锤切 .regular 后跟进 activate 的延迟
    static let hammerFollowUpDelay: Double = 0.1
    /// 单步耗时告警阈值（ms）
    static let slowStepThreshold: Double = 80
    /// 单步熔断阈值（ms）
    static let abortThreshold: Double = 800

    private let env: Environment
    /// App Nap 断言 reason（按面板区分，便于功耗排查溯源）
    private let napReason: String

    /// 梯子会话是否存活（begin 置真、end 置假）——收起后所有排队闭包经此守卫
    /// 变空操作，不再产生任何副作用
    private(set) var isActive = false
    /// key 补拉熔断标志（begin 时复位；某步 activate/makeKey 阻塞 >0.8s 置位）
    private(set) var isAborted = false
    /// 重锤是否已切 .regular（切回 .accessory 前为真）
    private var policyDanced = false
    private var wakeAssertion: NSObjectProtocol?
    private weak var panel: (any KeyWindowLadderPanel)?
    /// 日志分类（begin 时传入："Clipboard" / "Launcher"）
    private var category: String = ""
    private var onFocus: (() -> Void)?

    init(env: Environment = .live, napReason: String) {
        self.env = env
        self.napReason = napReason
    }

    // MARK: - 会话生命周期

    /// 面板 show() 时调用：排布补拉梯子与重锤、持有 App Nap 断言。
    /// 重复 begin（快速 toggle 漏了 end）先收掉上一轮，断言不重复持有。
    func begin(
        panel: any KeyWindowLadderPanel,
        category: String,
        onFocus: @escaping () -> Void
    ) {
        if isActive { end() }
        isActive = true
        isAborted = false
        policyDanced = false
        self.panel = panel
        self.category = category
        self.onFocus = onFocus

        for delay in Self.retryDelays {
            runAt(delay) { [weak self] in
                self?.runRetryStep()
            }
        }
        runAt(Self.hammerDelay) { [weak self] in
            self?.runActivationHammer()
        }

        wakeAssertion = env.beginActivity(napReason)
        env.logInfo(category, "App Nap 断言已持有（面板可见期间）")
    }

    /// 面板 hide() 时调用：重锤后切回 .accessory、释放断言。
    /// 之后所有排队闭包经 isActive 守卫变空操作；重复调用无副作用。
    func end() {
        guard isActive else { return }
        isActive = false
        if policyDanced {
            env.setActivationPolicy(.accessory)
            policyDanced = false
        }
        if let token = wakeAssertion {
            env.endActivity(token)
            wakeAssertion = nil
            env.logInfo(category, "App Nap 断言已释放")
        }
    }

    // MARK: - 补拉重试（一步）

    private func runRetryStep() {
        guard let panel else { return }
        // 已 key 就不再动（重新 makeKey 会重启 field editor、丢组词内容）
        guard panel.isVisible, !panel.isKeyWindow else { return }
        guard !isAborted else { return }
        let t0 = env.now()
        env.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
        let ms = elapsedMs(since: t0)
        if ms > Self.slowStepThreshold {
            env.logWarning(category, String(format: "key 补拉一步耗时 %.0fms（activate/makeKey 疑似阻塞）", ms))
        }
        if ms > Self.abortThreshold {
            isAborted = true
            env.logWarning(category, String(format: "key 补拉熔断（该步 %.0fms，交由重锤接管）", ms))
        }
        // 无条件补焦一拍（激活/makeKey 本身不补焦也要补——晚到的 key 需要有人聚焦）
        runNextTick { [weak self] in
            self?.onFocus?()
        }
    }

    // MARK: - 激活重锤

    private func runActivationHammer() {
        guard let panel else { return }
        guard panel.isVisible, !panel.isKeyWindow else { return }
        env.logWarning(category, "激活被拒（accessory 策略），启用 .regular 重锤")
        policyDanced = true
        let h0 = env.now()
        env.setActivationPolicy(.regular)
        let policyMs = elapsedMs(since: h0)
        if policyMs > Self.slowStepThreshold {
            env.logWarning(category, String(format: "重锤 setActivationPolicy 耗时 %.0fms", policyMs))
        }
        runAt(Self.hammerFollowUpDelay) { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.env.activate()
            panel.makeKeyAndOrderFront(nil)
            self.runNextTick { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.onFocus?()
                // 聚焦完成后立刻切回（缩短 Dock 图标闪现）
                if panel.isKeyWindow, self.policyDanced {
                    self.env.setActivationPolicy(.accessory)
                    self.policyDanced = false
                }
            }
        }
    }

    // MARK: - 调度包装（isActive 守卫：收起后排队闭包全部空操作）

    private func runAt(_ delay: Double, _ body: @escaping () -> Void) {
        env.scheduleAfter(delay) { [weak self] in
            guard let self, self.isActive else { return }
            body()
        }
    }

    private func runNextTick(_ body: @escaping () -> Void) {
        env.asyncOnMain { [weak self] in
            guard let self, self.isActive else { return }
            body()
        }
    }

    private func elapsedMs(since start: DispatchTime) -> Double {
        Double(env.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
