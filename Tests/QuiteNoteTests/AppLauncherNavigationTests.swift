#if !APP_STORE
import XCTest
import AppKit
@testable import QuiteNote

/// 启动器 ↑↓ 导航 / hover 选中抑制 / 防抖冲刷 / 文件结果落地语义（2026-10-11 三症状修复）
///
/// 覆盖 10 组交叉调研定位的缺陷：
/// ① ↑↓ 回绕（第 0 项按 ↑ 跳到最后一项 = "选中跑到下面"来源之一）→ 改为到顶/到底即停
/// ② 布局合成 hover 抢选中（重置 0 后鼠标下的行立即覆盖）→ hover 抑制 + 真实移动才恢复
/// ③ 打字后 30ms 内按键作用于旧列表随后被重置吞掉 → 键盘动作前冲刷挂起的重算
/// ④ 文件模式异步回调绕过选中重置（越界索引）→ applyFileResults 统一落地
/// ⑤ ⌥空格唤起后 ⌥ 未松时 ↓ 带修饰被拒收 → mapKey 对 option-only 宽容
@MainActor
final class AppLauncherNavigationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    private func makeFiles(_ count: Int) -> [LauncherFile] {
        (0..<count).map {
            LauncherFile(name: "f\($0)", url: URL(fileURLWithPath: "/tmp/qntest/\($0).txt"),
                         kindDescription: "文本", modifiedDate: nil, isDirectory: false)
        }
    }

    // MARK: - ↑↓ 不回绕

    func test顶部按上不回绕() {
        let vm = AppLauncherViewModel()
        vm.selectedIndex = 0
        vm.moveSelection(up: true)
        XCTAssertEqual(vm.selectedIndex, 0, "第 0 项按 ↑ 必须停在原处（Alfred 语义，不跳到最后一项）")
    }

    func test底部按下不回绕() {
        let vm = AppLauncherViewModel()
        let version = vm.resultsVersion
        vm.applyFileResults(makeFiles(5))
        XCTAssertEqual(vm.resultsVersion, version + 1)
        vm.selectedIndex = 4
        vm.moveSelection(up: false)
        XCTAssertEqual(vm.selectedIndex, 4, "最后一项按 ↓ 必须停在原处")
        vm.moveSelection(up: true)
        XCTAssertEqual(vm.selectedIndex, 3)
        vm.moveSelection(up: true)
        vm.moveSelection(up: true)
        vm.moveSelection(up: true)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func test空列表导航安全() {
        let vm = AppLauncherViewModel()
        vm.moveSelection(up: true)
        vm.moveSelection(up: false)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    // MARK: - hover 抑制

    func test键盘导航后合成hover不抢选中() {
        let vm = AppLauncherViewModel()
        vm.applyFileResults(makeFiles(10))
        vm.hoverSelect(5, mouseLocation: CGPoint(x: 100, y: 100))   // 真实移动 → 恢复并选中
        XCTAssertEqual(vm.selectedIndex, 5)

        vm.moveSelection(up: false)                                  // 键盘操作 → 抑制（记录当前光标位置）
        let parked = NSEvent.mouseLocation
        vm.hoverSelect(9, mouseLocation: parked)                     // 同一位置触发 = 布局合成 → 拒绝
        XCTAssertEqual(vm.selectedIndex, 6, "抑制期内布局合成的 hover 不得改写键盘选中")
    }

    func test真实鼠标移动恢复hover选中() {
        let vm = AppLauncherViewModel()
        vm.applyFileResults(makeFiles(10))
        vm.moveSelection(up: false)                                  // 抑制
        vm.hoverSelect(2, mouseLocation: CGPoint(x: 555, y: 999))    // 位置变化 = 真实移动
        XCTAssertEqual(vm.selectedIndex, 2, "真实移动后 hover 选中应恢复")
    }

    // MARK: - 防抖冲刷

    func test冲刷挂起重算并重置选中() {
        let vm = AppLauncherViewModel()
        vm.applyFileResults(makeFiles(8))
        vm.selectedIndex = 6
        // 模拟打字（didSet 只排队 30ms 防抖任务；同步测试里 main queue 不转，任务挂起）
        vm.searchText = "xyz"
        vm.flushPendingRecompute()
        XCTAssertEqual(vm.selectedIndex, 0, "冲刷后新结果落地，选中必须归零（输入变化 → 第一项）")
    }

    func test无挂起任务时冲刷零开销() {
        let vm = AppLauncherViewModel()
        let before = vm.resultsVersion
        vm.flushPendingRecompute()
        XCTAssertEqual(vm.resultsVersion, before, "无挂起重算时不重复计算")
    }

    // MARK: - 文件结果落地

    func test文件结果落地重置选中与版本() {
        let vm = AppLauncherViewModel()
        vm.applyFileResults(makeFiles(20))
        vm.selectedIndex = 15
        let version = vm.resultsVersion
        vm.applyFileResults(makeFiles(3))                            // 列表缩短
        XCTAssertEqual(vm.selectedIndex, 0, "异步结果落地必须重置选中，防越界索引")
        XCTAssertEqual(vm.resultsVersion, version + 1, "落地要 bump 版本（视图据此回顶）")
    }

    // MARK: - 按键映射（⌥ 修饰宽容）

    private func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: " ", charactersIgnoringModifiers: " ",
                         isARepeat: false, keyCode: keyCode)!
    }

    func test裸方向键导航() {
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(125, [])), .moveDown)
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(126, [])), .moveUp)
    }

    func testOption残留仍可导航() {
        // ⌥空格唤起后松开 ⌥ 稍慢，↓ 带着 ⌥ —— 必须照常导航
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(125, .option)), .moveDown)
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(126, .option)), .moveUp)
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(36, .option)), .launchSelected)
    }

    func test命令与Shift修饰放行() {
        // ⌘↓ / ⇧↓ 是文本编辑语义，不归启动器
        XCTAssertNil(AppLauncherPanelController.mapKey(keyEvent(125, .command)))
        XCTAssertNil(AppLauncherPanelController.mapKey(keyEvent(125, .shift)))
        XCTAssertNil(AppLauncherPanelController.mapKey(keyEvent(126, [.option, .command])))
    }

    func test命令数字与命令W() {
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(18, .command)), .launchIndex(1))
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(13, .command)), .escape)
        XCTAssertEqual(AppLauncherPanelController.mapKey(keyEvent(36, .command)), .copyCalcFull)
    }
}
#endif
