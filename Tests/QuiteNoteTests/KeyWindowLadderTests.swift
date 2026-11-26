import AppKit
import XCTest
@testable import QuiteNote

/// KeyWindowLadder 行为钉子（虚拟时间推进 + 假面板/假环境记录副作用）
///
/// 覆盖剪贴板面板 2026-11-20 生产验证版梯子的核心语义：
/// 补拉重试（前密后疏 + 逐步计时熔断）、0.35s 激活重锤、App Nap 断言生命周期、
/// end() 后排队闭包全部空操作。
@MainActor
final class KeyWindowLadderTests: XCTestCase {

    // MARK: - 假环境

    /// 虚拟时间调度器：闭包按到期时间从早到晚执行；闭包内部可推进虚拟时钟
    /// （模拟 activate/makeKey 同步阻塞）
    private final class FakeScheduler {
        private var items: [(deadline: Double, block: () -> Void)] = []
        private(set) var virtualSeconds: Double = 0

        var now: DispatchTime { DispatchTime(uptimeNanoseconds: UInt64(virtualSeconds * 1_000_000_000)) }

        func schedule(after delay: Double, _ block: @escaping () -> Void) {
            items.append((virtualSeconds + delay, block))
        }

        /// 直接推进虚拟时钟（测试里模拟 activate/makeKey 同步阻塞用）
        func elapse(_ seconds: Double) {
            virtualSeconds += seconds
        }

        /// 虚拟环境里"下一拍"同步执行（顺序语义与真实主队列一致）
        func runNextTick(_ block: @escaping () -> Void) {
            block()
        }

        func advance(by interval: Double) {
            let target = virtualSeconds + interval
            while let idx = items.indices
                .filter({ items[$0].deadline <= target })
                .min(by: { items[$0].deadline < items[$1].deadline }) {
                let item = items.remove(at: idx)
                virtualSeconds = max(virtualSeconds, item.deadline)
                item.block()
            }
            // 闭包内部可能把时钟推过 target（阻塞模拟），不能回拨
            virtualSeconds = max(virtualSeconds, target)
        }
    }

    /// 副作用记录器
    private final class Recorder {
        var activateCalls = 0
        var policies: [NSApplication.ActivationPolicy] = []
        var beginActivityCount = 0
        var endActivityCount = 0
        /// 当前仍持有的断言 token（beginActivity/endActivity 配对核对）
        var heldTokens: [NSObjectProtocol] = []
        var warnings: [String] = []
        var infos: [String] = []
        var focusCalls = 0
    }

    /// 假面板：makeKey 永远拿不到 key（模拟 accessory 激活被系统拒绝）；
    /// makeKeyAndOrderFront 能拿到（重锤切 .regular 后激活可靠的真实行为）
    private final class FakePanel: KeyWindowLadderPanel {
        var isVisible = true
        var isKeyWindow = false
        private(set) var makeKeyCalls = 0
        private(set) var makeKeyAndOrderFrontCalls = 0
        private(set) var orderFrontRegardlessCalls = 0

        func orderFrontRegardless() { orderFrontRegardlessCalls += 1 }
        func makeKey() { makeKeyCalls += 1 }
        func makeKeyAndOrderFront(_ sender: Any?) {
            makeKeyAndOrderFrontCalls += 1
            isKeyWindow = true
        }
    }

    private func makeEnv(
        scheduler: FakeScheduler,
        recorder: Recorder,
        onActivate: (() -> Void)? = nil
    ) -> KeyWindowLadder.Environment {
        KeyWindowLadder.Environment(
            activate: {
                onActivate?()
                recorder.activateCalls += 1
            },
            setActivationPolicy: { recorder.policies.append($0) },
            beginActivity: { _ in
                recorder.beginActivityCount += 1
                let token = NSObject()
                recorder.heldTokens.append(token)
                return token
            },
            endActivity: { token in
                recorder.endActivityCount += 1
                recorder.heldTokens.removeAll { $0 === token }
            },
            scheduleAfter: { scheduler.schedule(after: $0, $1) },
            asyncOnMain: { scheduler.runNextTick($0) },
            now: { scheduler.now },
            logInfo: { _, message in recorder.infos.append(message) },
            logWarning: { _, message in recorder.warnings.append(message) }
        )
    }

    // MARK: - a) 面板一直不 key：0.35s 重锤恰好一次，key 落地后切回 .accessory

    func testHammerFiresOnceAndRestoresPolicyWhenKeyArrives() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }

        // App Nap 断言恰好持有一次
        XCTAssertEqual(recorder.beginActivityCount, 1)
        XCTAssertEqual(recorder.heldTokens.count, 1)
        XCTAssertTrue(recorder.infos.contains("App Nap 断言已持有（面板可见期间）"))

        // 重锤前：0.05~0.3 共 6 步补拉，每步 activate + makeKey（激活始终被拒）+ 无条件补焦
        scheduler.advance(by: 0.34)
        XCTAssertEqual(recorder.activateCalls, 6)
        XCTAssertEqual(panel.makeKeyCalls, 6)
        XCTAssertEqual(panel.orderFrontRegardlessCalls, 6)
        XCTAssertEqual(recorder.focusCalls, 6)
        XCTAssertEqual(recorder.policies, [])

        // 0.35s 重锤：切 .regular（恰好一次）
        scheduler.advance(by: 0.01)
        XCTAssertEqual(recorder.policies, [.regular])
        XCTAssertEqual(recorder.warnings, ["激活被拒（accessory 策略），启用 .regular 重锤"])

        // +0.1s 跟进：activate + makeKeyAndOrderFront（假面板模拟 key 落地）→ 聚焦 + 切回。
        // 0.4s 的最后一步补拉先于 0.45s 的跟进执行（此刻面板仍未 key，照常 activate）
        scheduler.advance(by: 0.1)
        XCTAssertEqual(recorder.activateCalls, 8) // 7 步补拉 + 跟进 1 次
        XCTAssertEqual(panel.makeKeyCalls, 7)
        XCTAssertEqual(panel.makeKeyAndOrderFrontCalls, 1)
        XCTAssertEqual(recorder.policies, [.regular, .accessory])
        XCTAssertEqual(recorder.focusCalls, 8)
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertEqual(recorder.heldTokens.count, 1)

        // 剩余步 0.55/0.7 面板已 key → 静默跳过，无新副作用（重锤/跟进不重复）
        scheduler.advance(by: 2.0)
        XCTAssertEqual(recorder.activateCalls, 8)
        XCTAssertEqual(recorder.policies, [.regular, .accessory])
    }

    // MARK: - b) 某步耗时 1500ms：熔断，后续补拉不再动，重锤仍然接管

    func testSlowStepTripsAbortAndHammerStillRuns() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        // activate 每次同步阻塞 1.5s（推进虚拟时钟模拟）
        let env = makeEnv(scheduler: scheduler, recorder: recorder, onActivate: { scheduler.elapse(1.5) })
        let ladder = KeyWindowLadder(env: env, napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }

        scheduler.advance(by: 0.05)
        XCTAssertTrue(ladder.isAborted)
        XCTAssertTrue(recorder.warnings.contains("key 补拉一步耗时 1500ms（activate/makeKey 疑似阻塞）"))
        XCTAssertTrue(recorder.warnings.contains("key 补拉熔断（该步 1500ms，交由重锤接管）"))
        XCTAssertEqual(recorder.activateCalls, 1)
        XCTAssertEqual(panel.makeKeyCalls, 1)

        // 后续补拉步跳过（activate/makeKey 不再调用）；重锤照常执行并跟进激活
        scheduler.advance(by: 2.0)
        XCTAssertEqual(recorder.activateCalls, 2) // 熔断步 1 次 + 重锤跟进 1 次
        XCTAssertEqual(panel.makeKeyCalls, 1)
        XCTAssertTrue(recorder.policies.contains(.regular))
        XCTAssertTrue(recorder.warnings.contains("激活被拒（accessory 策略），启用 .regular 重锤"))
    }

    // MARK: - c) 面板在 0.2s 成为 key：不触发重锤，后续补拉不再动

    func testKeyArrivalStopsRetriesAndSkipsHammer() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }

        scheduler.advance(by: 0.16) // 0.05 / 0.1 / 0.15 三步
        XCTAssertEqual(recorder.activateCalls, 3)
        panel.isKeyWindow = true // key 落地

        scheduler.advance(by: 3.0)
        XCTAssertEqual(recorder.activateCalls, 3) // 补拉不再动
        XCTAssertEqual(panel.makeKeyCalls, 3)
        XCTAssertEqual(recorder.policies, []) // 重锤未触发
        XCTAssertTrue(recorder.warnings.isEmpty) // 无激活被拒告警
    }

    // MARK: - d) 梯子途中面板被隐藏：之后什么都不做

    func testHiddenPanelMakesLadderIdle() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }

        scheduler.advance(by: 0.1) // 两步
        XCTAssertEqual(recorder.activateCalls, 2)
        panel.isVisible = false // 途中被隐藏

        scheduler.advance(by: 3.0)
        XCTAssertEqual(recorder.activateCalls, 2)
        XCTAssertEqual(panel.makeKeyCalls, 2)
        XCTAssertEqual(recorder.policies, []) // 重锤不触发
        XCTAssertEqual(recorder.beginActivityCount, 1) // 断言仍在持有（由 end() 释放）
    }

    // MARK: - e) end()：释放断言恰好一次；policyDanced 切回；重复 end 与排队闭包全部空操作

    func testEndReleasesAssertionAndNeutersQueuedClosures() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }
        scheduler.advance(by: 0.1) // 两步补拉

        ladder.end()
        XCTAssertEqual(recorder.endActivityCount, 1)
        XCTAssertEqual(recorder.heldTokens.count, 0)
        XCTAssertTrue(recorder.infos.contains("App Nap 断言已释放"))
        XCTAssertEqual(recorder.policies, []) // 未重锤 → 不切 policy

        // 重复 end() 无副作用
        ladder.end()
        XCTAssertEqual(recorder.endActivityCount, 1)
        XCTAssertEqual(recorder.policies, [])

        // end() 后推进时间：排队的补拉 / 重锤闭包不再产生副作用
        let activateBefore = recorder.activateCalls
        let focusBefore = recorder.focusCalls
        scheduler.advance(by: 3.0)
        XCTAssertEqual(recorder.activateCalls, activateBefore)
        XCTAssertEqual(recorder.focusCalls, focusBefore)
        XCTAssertEqual(recorder.policies, [])
    }

    func testEndAfterHammerRestoresAccessoryPolicy() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }

        scheduler.advance(by: 0.35) // 重锤触发（面板一直不 key，policyDanced 悬着）
        XCTAssertEqual(recorder.policies, [.regular])
        let activateAtHammer = recorder.activateCalls // 6 步补拉已发生的 activate

        ladder.end() // 面板收起：切回 .accessory 并复位
        XCTAssertEqual(recorder.policies, [.regular, .accessory])
        XCTAssertEqual(recorder.endActivityCount, 1)

        // 重锤的跟进闭包（+0.1s）在 end 后必须空操作
        scheduler.advance(by: 1.0)
        XCTAssertEqual(recorder.policies, [.regular, .accessory])
        XCTAssertEqual(recorder.activateCalls, activateAtHammer) // 跟进 activate 未执行
        XCTAssertEqual(recorder.endActivityCount, 1)
    }

    // MARK: - f) 连续 begin 两次（快速 toggle）：断言不重复持有

    func testConsecutiveBeginDoesNotDoubleHoldAssertion() {
        let scheduler = FakeScheduler()
        let recorder = Recorder()
        let panel = FakePanel()
        let ladder = KeyWindowLadder(env: makeEnv(scheduler: scheduler, recorder: recorder), napReason: "test")

        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }
        XCTAssertEqual(recorder.beginActivityCount, 1)
        XCTAssertEqual(recorder.heldTokens.count, 1)

        // 漏 end 的快速重开：先隐式收掉上一轮，再持有——任意时刻只持有一个断言
        ladder.begin(panel: panel, category: "Test") { recorder.focusCalls += 1 }
        XCTAssertEqual(recorder.beginActivityCount, 2)
        XCTAssertEqual(recorder.endActivityCount, 1)
        XCTAssertEqual(recorder.heldTokens.count, 1)

        // 会话存活、熔断标志已复位、end 收尾正常
        XCTAssertFalse(ladder.isAborted)
        ladder.end()
        XCTAssertEqual(recorder.endActivityCount, 2)
        XCTAssertEqual(recorder.heldTokens.count, 0)
    }

    // MARK: - 常量钉子（剪贴板面板生产验证版参数，不许悄悄漂移）

    func testLadderConstantsMatchProductionVerifiedValues() {
        XCTAssertEqual(
            KeyWindowLadder.retryDelays,
            [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.55, 0.7]
        )
        XCTAssertEqual(KeyWindowLadder.hammerDelay, 0.35)
        XCTAssertEqual(KeyWindowLadder.hammerFollowUpDelay, 0.1)
        XCTAssertEqual(KeyWindowLadder.slowStepThreshold, 80)
        XCTAssertEqual(KeyWindowLadder.abortThreshold, 800)
    }
}
