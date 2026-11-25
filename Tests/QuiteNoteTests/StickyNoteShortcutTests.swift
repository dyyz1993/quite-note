import XCTest
import AppKit
@testable import QuiteNote

/// 便利贴两个全局热键收归 KeyboardShortcutManager 统一注册：
/// 偏好键（默认值 / 读写 / resetAll）、偏好 → 注册参数映射、注册流程、菜单项 keyEquivalent、
/// 设置页字符串表完整性。
///
/// ⚠️ Carbon 热键是全系统独占：正式版 Quite Note 运行期间可能已占用同一组合，所以这里
/// **不做真实注册**——注册/注销/重试全部换成注入的假实现（FakeHotkeyCenter），
/// 也不调用 start() / refresh()（它们会走真实 Carbon 注册其他热键）。
@MainActor
final class StickyNoteShortcutTests: XCTestCase {

    // MARK: - 夹具

    private static let preferenceKeys = [
        "stickyNoteShortcut", "stickyNoteShortcutFlags",
        "stickySpacePinShortcut", "stickySpacePinShortcutFlags",
        "stickyNoteDefaultColor",
    ]
    private var savedPreferences: [(key: String, value: Any?)] = []
    private var savedNoteConflict = false
    private var savedPinConflict = false

    private var prefs: PreferencesManager { PreferencesManager.shared }

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        // 保存旧偏好与冲突标志，测试结束后恢复，不污染同进程其他用例
        savedPreferences = Self.preferenceKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        Self.preferenceKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        savedNoteConflict = KeyboardShortcutManager.stickyNoteShortcutConflict
        savedPinConflict = KeyboardShortcutManager.stickySpacePinShortcutConflict
        KeyboardShortcutManager.stickyNoteShortcutConflict = false
        KeyboardShortcutManager.stickySpacePinShortcutConflict = false
    }

    override func tearDown() {
        Self.restore(savedPreferences)
        KeyboardShortcutManager.stickyNoteShortcutConflict = savedNoteConflict
        KeyboardShortcutManager.stickySpacePinShortcutConflict = savedPinConflict
        super.tearDown()
    }

    /// 把快照写回 UserDefaults（值为 nil 的键删掉）
    private static func restore(_ snapshot: [(key: String, value: Any?)]) {
        for (key, value) in snapshot {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private static let controlCommand = Int(NSEvent.ModifierFlags([.control, .command]).rawValue)
    /// 新建便利贴的默认修饰键：⌥⇧⌘
    private static let optionShiftCommand = Int(NSEvent.ModifierFlags([.option, .shift, .command]).rawValue)
    private static let optionCommand = Int(NSEvent.ModifierFlags([.option, .command]).rawValue)
    private static let commandShift = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)

    /// 假的热键中心：记录注册/注销调用、保存 handler，可按 id 模拟「被占用」。
    /// 重试块只收集不执行，由测试按需触发
    private final class FakeHotkeyCenter {
        struct Call: Equatable {
            let key: String
            let modifiers: NSEvent.ModifierFlags
            let id: UInt32
        }
        var registered: [Call] = []
        var unregistered: [UInt32] = []
        /// 注册失败后安排的重试块
        var scheduledRetries: [() -> Void] = []
        private var handlers: [UInt32: () -> Void] = [:]
        /// 这些 id 注册时返回失败（模拟 Carbon -9868 被系统/其他应用占用）
        var failingIDs: Set<UInt32> = []

        /// 把假中心装到一个新 manager 上（不调用 start()/refresh()——那会走真实 Carbon 注册其他热键）
        func install() -> KeyboardShortcutManager {
            let manager = KeyboardShortcutManager()
            manager.hotkeyRegister = { [weak self] key, modifiers, id, handler in
                guard let self else { return false }
                self.registered.append(Call(key: key, modifiers: modifiers, id: id))
                if self.failingIDs.contains(id) { return false }
                self.handlers[id] = handler
                return true
            }
            manager.hotkeyUnregister = { [weak self] id in
                self?.unregistered.append(id)
                self?.handlers[id] = nil
            }
            manager.scheduleHotkeyRetry = { [weak self] block in
                self?.scheduledRetries.append(block)
            }
            return manager
        }

        /// 模拟用户按下已注册的热键
        func fire(_ id: UInt32) { handlers[id]?() }
    }

    private func makeCenter() -> (manager: KeyboardShortcutManager, center: FakeHotkeyCenter) {
        let center = FakeHotkeyCenter()
        return (center.install(), center)
    }

    // MARK: - 偏好键

    func test默认值_新建为OptionShiftCommandN_固定为OptionCommandP() {
        XCTAssertEqual(prefs.stickyNoteShortcut, "n")
        XCTAssertEqual(prefs.stickyNoteShortcutFlags, Self.optionShiftCommand)
        XCTAssertEqual(prefs.stickySpacePinShortcut, "p")
        XCTAssertEqual(prefs.stickySpacePinShortcutFlags, Self.optionCommand)
    }

    /// 回归守卫：Carbon 热键是系统级独占，Finder 把带 N 的三种两键组合全占了——
    /// ⌘⇧N 新建文件夹、⌃⌘N 用所选项目新建文件夹、⌥⌘N 新建智能文件夹。
    /// 新建便利贴的默认值一个都不能撞
    func test默认值_不撞Finder的三个带N组合() {
        let defaultRegistration = KeyboardShortcutManager.hotkeyRegistration(
            key: prefs.stickyNoteShortcut, flags: prefs.stickyNoteShortcutFlags)
        XCTAssertEqual(defaultRegistration, HotkeyRegistration(key: "n", modifiers: [.command, .option, .shift]))
        for taken in [HotkeyRegistration(key: "n", modifiers: [.command, .shift]),
                      HotkeyRegistration(key: "n", modifiers: [.control, .command]),
                      HotkeyRegistration(key: "n", modifiers: [.option, .command])] {
            XCTAssertNotEqual(defaultRegistration, taken, "默认热键撞上了 \(taken.displayString())")
        }
    }

    func test读写_设置后原样读回() {
        prefs.setStickyNoteShortcut("k")
        prefs.setStickyNoteShortcutFlags(Self.optionCommand)
        prefs.setStickySpacePinShortcut("L")
        prefs.setStickySpacePinShortcutFlags(Self.commandShift)

        XCTAssertEqual(prefs.stickyNoteShortcut, "k")
        XCTAssertEqual(prefs.stickyNoteShortcutFlags, Self.optionCommand)
        XCTAssertEqual(prefs.stickySpacePinShortcut, "L")
        XCTAssertEqual(prefs.stickySpacePinShortcutFlags, Self.commandShift)
    }

    /// 空字符串 = 禁用：存了空串必须读回空串，不能落回默认键
    func test禁用_空字符串读回空串而不落回默认值() {
        prefs.setStickyNoteShortcut("")
        prefs.setStickyNoteShortcutFlags(0)
        XCTAssertEqual(prefs.stickyNoteShortcut, "")
        XCTAssertFalse(KeyboardShortcutManager.hotkeyRegistration(key: prefs.stickyNoteShortcut, flags: prefs.stickyNoteShortcutFlags).isEnabled)
    }

    func testresetAll_四个键在清除清单内并回到默认值() {
        // resetAll 清的是整个偏好域：按同一份清单保存/恢复，避免影响同进程其他用例
        let snapshot = PreferencesManager.resettableKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { Self.restore(snapshot) }

        for key in Self.preferenceKeys {
            XCTAssertTrue(PreferencesManager.resettableKeys.contains(key), "resetAll 漏了 \(key)")
        }

        prefs.setStickyNoteShortcut("k")
        prefs.setStickyNoteShortcutFlags(Self.commandShift)
        prefs.setStickySpacePinShortcut("")
        prefs.setStickySpacePinShortcutFlags(0)
        prefs.resetAll()

        XCTAssertEqual(prefs.stickyNoteShortcut, "n")
        XCTAssertEqual(prefs.stickyNoteShortcutFlags, Self.optionShiftCommand)
        XCTAssertEqual(prefs.stickySpacePinShortcut, "p")
        XCTAssertEqual(prefs.stickySpacePinShortcutFlags, Self.optionCommand)
    }

    // MARK: - 新建便利贴的默认底色

    func test默认底色_缺省为深蓝_可读写_纳入resetAll() {
        XCTAssertEqual(prefs.stickyNoteDefaultColor, StickyNoteColor.blue.rawValue)
        XCTAssertTrue(PreferencesManager.resettableKeys.contains("stickyNoteDefaultColor"))

        prefs.setStickyNoteDefaultColor(.amber)
        XCTAssertEqual(prefs.stickyNoteDefaultColor, StickyNoteColor.amber.rawValue)
        XCTAssertEqual(StickyNoteColor.from(prefs.stickyNoteDefaultColor), .amber)

        let snapshot = PreferencesManager.resettableKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { Self.restore(snapshot) }
        prefs.resetAll()
        XCTAssertEqual(StickyNoteColor.from(prefs.stickyNoteDefaultColor), .blue)
    }

    // MARK: - 偏好 → 注册参数（纯函数）

    func test映射_默认偏好得到OptionShiftCommandN与OptionCommandP() {
        XCTAssertEqual(
            KeyboardShortcutManager.hotkeyRegistration(key: prefs.stickyNoteShortcut, flags: prefs.stickyNoteShortcutFlags),
            HotkeyRegistration(key: "n", modifiers: [.command, .option, .shift]))
        XCTAssertEqual(
            KeyboardShortcutManager.hotkeyRegistration(key: prefs.stickySpacePinShortcut, flags: prefs.stickySpacePinShortcutFlags),
            HotkeyRegistration(key: "p", modifiers: [.command, .option]))
    }

    /// 录制器（ShortcutRecorderView）写入的是 charactersIgnoringModifiers.lowercased() 与
    /// deviceIndependent 全量修饰位；存量值还可能是大写。映射必须归一化成「小写键 + 四个修饰键」
    func test映射_录制后的组合被归一化() {
        let noisy = NSEvent.ModifierFlags([.command, .control]).union([.function, .numericPad, .capsLock])
        let registration = KeyboardShortcutManager.hotkeyRegistration(key: "K", flags: Int(noisy.rawValue))
        XCTAssertEqual(registration, HotkeyRegistration(key: "k", modifiers: [.command, .control]))

        // 全修饰键 + 大写
        let all = KeyboardShortcutManager.hotkeyRegistration(key: "P", flags: Self.optionCommand | Self.controlCommand | Int(NSEvent.ModifierFlags.shift.rawValue))
        XCTAssertEqual(all, HotkeyRegistration(key: "p", modifiers: [.command, .option, .shift, .control]))

        // 空格键（启动器同款：⌥ + U+00A0）
        let space = KeyboardShortcutManager.hotkeyRegistration(key: "\u{00A0}", flags: Int(NSEvent.ModifierFlags.option.rawValue))
        XCTAssertEqual(space, HotkeyRegistration(key: "\u{00a0}", modifiers: [.option]))
    }

    /// 负数 flags（只有外部手改 defaults 才会出现）：不得崩溃，也不得退化成「无修饰键的裸键」
    func test映射_非法flags不崩溃且不退化成裸键() {
        let negative = KeyboardShortcutManager.hotkeyRegistration(key: "n", flags: -1)
        XCTAssertTrue(negative.modifiers.isEmpty, "clamping 归零：实际 \(negative.modifiers.rawValue)")
        XCTAssertFalse(negative.isSafeToRegister, "无修饰键的裸 n 会被拒绝注册")

        let zero = KeyboardShortcutManager.hotkeyRegistration(key: "n", flags: 0)
        XCTAssertEqual(zero, HotkeyRegistration(key: "n", modifiers: []))
        XCTAssertFalse(zero.isSafeToRegister)

        // 空键永远是「禁用」，与 flags 无关
        XCTAssertFalse(KeyboardShortcutManager.hotkeyRegistration(key: "", flags: -1).isEnabled)
    }

    /// 修饰键按系统惯例排序（⌃⌥⇧⌘，与状态栏菜单的渲染一致）
    func test展示串_修饰键按系统惯例排序() {
        XCTAssertEqual(HotkeyRegistration(key: "n", modifiers: [.control, .command]).displayString(), "⌃⌘N")
        XCTAssertEqual(HotkeyRegistration(key: "p", modifiers: [.option, .command]).displayString(), "⌥⌘P")
        XCTAssertEqual(HotkeyRegistration(key: "n", modifiers: [.command, .shift]).displayString(), "⇧⌘N")
        XCTAssertEqual(HotkeyRegistration(key: "k", modifiers: [.command, .option, .shift, .control]).displayString(), "⌃⌥⇧⌘K")
        XCTAssertEqual(HotkeyRegistration(key: " ", modifiers: [.option]).displayString(), "⌥空格")
        XCTAssertEqual(HotkeyRegistration(key: " ", modifiers: [.option]).displayString(spaceLabel: "Space"), "⌥Space")
        XCTAssertEqual(HotkeyRegistration(key: "", modifiers: []).displayString(), "")
    }

    // MARK: - 注册流程（KeyboardShortcutManager + 注入的假热键中心）

    func test注册流程_按偏好注册两个热键并接对回调() {
        let (manager, center) = makeCenter()
        var newNoteCount = 0
        var togglePinCount = 0
        manager.onNewStickyNote = { newNoteCount += 1 }
        manager.onToggleStickySpacePin = { togglePinCount += 1 }

        manager.registerStickyHotkeys()

        // id 沿用 StickyNoteManager 旧实现的 5001 / 5002；默认偏好 → ⌥⇧⌘N / ⌥⌘P
        XCTAssertEqual(KeyboardShortcutManager.stickyNoteHotkeyID, 5001)
        XCTAssertEqual(KeyboardShortcutManager.stickySpacePinHotkeyID, 5002)
        XCTAssertEqual(center.registered, [
            FakeHotkeyCenter.Call(key: "n", modifiers: [.command, .option, .shift], id: 5001),
            FakeHotkeyCenter.Call(key: "p", modifiers: [.command, .option], id: 5002),
        ])
        XCTAssertTrue(center.unregistered.isEmpty, "启用状态下不应有注销")
        XCTAssertTrue(center.scheduledRetries.isEmpty)
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)
        XCTAssertFalse(KeyboardShortcutManager.stickySpacePinShortcutConflict)

        center.fire(5001)
        XCTAssertEqual(newNoteCount, 1)
        XCTAssertEqual(togglePinCount, 0, "新建热键不得触发固定切换")
        center.fire(5002)
        XCTAssertEqual(newNoteCount, 1)
        XCTAssertEqual(togglePinCount, 1)
    }

    func test注册流程_改键后按新偏好重新注册() {
        let (manager, center) = makeCenter()
        manager.registerStickyHotkeys()

        prefs.setStickyNoteShortcut("k")
        prefs.setStickyNoteShortcutFlags(Self.optionCommand)
        manager.registerStickyHotkeys()

        // registerStickyHotkeys 先注册新建、再注册固定，所以不能直接取 last
        XCTAssertEqual(center.registered.last { $0.id == 5001 },
                       FakeHotkeyCenter.Call(key: "k", modifiers: [.command, .option], id: 5001))
        XCTAssertEqual(center.registered.count, 4, "两个热键各注册两轮")
    }

    func test注册失败_置冲突标志并安排重试_重试成功后清除() {
        let (manager, center) = makeCenter()
        center.failingIDs = [5001]

        manager.registerStickyHotkeys()

        XCTAssertTrue(KeyboardShortcutManager.stickyNoteShortcutConflict, "注册失败必须暴露给设置页")
        XCTAssertFalse(KeyboardShortcutManager.stickySpacePinShortcutConflict, "另一个热键不受牵连")
        XCTAssertEqual(center.scheduledRetries.count, 1, "失败要安排一次重试")

        // 「被占用」解除后执行重试块 → 注册成功，冲突标志清除，且不再追加重试
        center.failingIDs = []
        center.scheduledRetries[0]()
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)
        XCTAssertEqual(center.registered.filter { $0.id == 5001 }.count, 2)
        XCTAssertEqual(center.scheduledRetries.count, 1, "重试成功后不再排重试")
    }

    func test注册失败_重试仍失败则冲突标志保持() {
        let (manager, center) = makeCenter()
        center.failingIDs = [5002]

        manager.registerStickyHotkeys()
        XCTAssertTrue(KeyboardShortcutManager.stickySpacePinShortcutConflict)
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)

        center.scheduledRetries[0]()
        XCTAssertTrue(KeyboardShortcutManager.stickySpacePinShortcutConflict)
        XCTAssertEqual(center.scheduledRetries.count, 1, "只重试一次")
    }

    func test注册失败_重试时重新读取偏好() {
        let (manager, center) = makeCenter()
        center.failingIDs = [5001]
        manager.registerStickyHotkeys()

        // 重试窗口内用户改了键：重试必须注册新键，而不是失败时的旧参数
        prefs.setStickyNoteShortcut("k")
        prefs.setStickyNoteShortcutFlags(Self.controlCommand)
        center.failingIDs = []   // 「被占用」已解除
        center.scheduledRetries[0]()
        XCTAssertEqual(center.registered.last { $0.id == 5001 },
                       FakeHotkeyCenter.Call(key: "k", modifiers: [.command, .control], id: 5001))
        XCTAssertEqual(center.registered.filter { $0.id == 5001 }.map(\.key), ["n", "k"], "重试不应再注册旧键 n")
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)
    }

    /// 非空键但不带修饰键：裸字母 / 空格做成全局热键会吞掉系统里每一次该按键，必须拒绝注册，
    /// 并以冲突标志提示用户（录制器本就录不出这种组合，兜底的是被写坏的偏好）
    func test裸键_非空键无修饰键拒绝注册并提示冲突() {
        for bareKey in ["n", " "] {
            prefs.setStickyNoteShortcut(bareKey)
            prefs.setStickyNoteShortcutFlags(0)
            let (manager, center) = makeCenter()

            manager.registerStickyHotkeys()

            XCTAssertFalse(center.registered.contains { $0.id == 5001 }, "裸键 \(bareKey.debugDescription) 不得注册")
            XCTAssertTrue(KeyboardShortcutManager.stickyNoteShortcutConflict, "裸键 \(bareKey.debugDescription) 要提示冲突")
            XCTAssertTrue(center.scheduledRetries.isEmpty, "配置本身不安全，重试没有意义")
            // 另一个热键不受牵连
            XCTAssertEqual(center.registered.map(\.id), [5002])
        }
    }

    func test注册失败_重试窗口内用户禁用则只注销() {
        let (manager, center) = makeCenter()
        center.failingIDs = [5001]
        manager.registerStickyHotkeys()

        prefs.setStickyNoteShortcut("")
        prefs.setStickyNoteShortcutFlags(0)
        let registeredBefore = center.registered.count
        center.scheduledRetries[0]()

        XCTAssertEqual(center.registered.count, registeredBefore, "禁用后不得再注册")
        XCTAssertEqual(center.unregistered.last, 5001)
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)
    }

    func test禁用_只注销不注册且不算冲突() {
        prefs.setStickyNoteShortcut("")
        prefs.setStickyNoteShortcutFlags(0)
        let (manager, center) = makeCenter()

        manager.registerStickyHotkeys()

        XCTAssertFalse(center.registered.contains { $0.id == 5001 })
        XCTAssertEqual(center.unregistered, [5001], "禁用要注销旧注册")
        XCTAssertEqual(center.registered, [
            FakeHotkeyCenter.Call(key: "p", modifiers: [.command, .option], id: 5002),
        ], "另一个热键照常注册")
        XCTAssertFalse(KeyboardShortcutManager.stickyNoteShortcutConflict)
        XCTAssertFalse(KeyboardShortcutManager.stickySpacePinShortcutConflict)
    }

    func teststop_注销本实例登记过的两个便利贴热键且可重复调用() {
        let (manager, center) = makeCenter()
        manager.registerStickyHotkeys()
        XCTAssertTrue(center.unregistered.isEmpty)

        manager.stop()

        XCTAssertEqual(Set(center.unregistered), [5001, 5002])
        XCTAssertEqual(center.unregistered.count, 2, "每个 id 只注销一次")

        manager.stop()
        XCTAssertEqual(center.unregistered.count, 2, "重复 stop 不应重复注销")
    }

    /// stop() 只注销**本实例登记过的**便利贴热键。GlobalHotkeyManager 是进程级单例：
    /// 一个从没登记过便利贴热键的临时实例（如 GlobalHotkeyRecorderRouteTests 里 new 出来
    /// 只为验证 refresh 守卫的那个）析构时，不得把别的 owner 注册的同 id 热键清掉
    func teststop_未登记过的实例不注销任何便利贴热键() {
        let (manager, center) = makeCenter()

        manager.stop()

        XCTAssertTrue(center.unregistered.isEmpty, "实际: \(center.unregistered)")
        XCTAssertTrue(center.registered.isEmpty)
    }

    // MARK: - 状态栏菜单「新建贴纸」的快捷键

    func test菜单项快捷键_默认显示OptionShiftCommandN() {
        let shortcut = StatusBarController.newStickyNoteMenuShortcut(
            key: prefs.stickyNoteShortcut, flags: prefs.stickyNoteShortcutFlags)
        XCTAssertEqual(shortcut.keyEquivalent, "n")
        XCTAssertEqual(shortcut.modifierMask, [.command, .option, .shift])
    }

    func test菜单项快捷键_禁用时keyEquivalent为空() {
        let shortcut = StatusBarController.newStickyNoteMenuShortcut(key: "", flags: 0)
        XCTAssertEqual(shortcut.keyEquivalent, "")
        XCTAssertEqual(shortcut.modifierMask, [])
    }

    /// 菜单显示的快捷键必须与实际注册的 Carbon 热键同源（同一套归一化），否则菜单会显示错的组合
    func test菜单项快捷键_与注册参数同源() {
        for (key, flags) in [("N", Self.commandShift), ("k", Self.controlCommand), (" ", Self.optionCommand), ("", 0)] {
            let registration = KeyboardShortcutManager.hotkeyRegistration(key: key, flags: flags)
            let menu = StatusBarController.newStickyNoteMenuShortcut(key: key, flags: flags)
            XCTAssertEqual(menu.keyEquivalent, registration.key, "key=\(key.debugDescription) flags=\(flags)")
            XCTAssertEqual(menu.modifierMask, registration.modifiers, "key=\(key.debugDescription) flags=\(flags)")
        }
    }

    // MARK: - 设置页 footer 状态摘要

    func testFooter摘要_显示当前热键_禁用时标注已禁用() {
        let lines = StickyNoteSettingsTab.footerStatusLines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("⌥⇧⌘N"), "实际: \(lines[0])")
        XCTAssertTrue(lines[1].hasSuffix("⌥⌘P"), "实际: \(lines[1])")

        prefs.setStickyNoteShortcut("")
        prefs.setStickyNoteShortcutFlags(0)
        let disabled = StickyNoteSettingsTab.footerStatusLines()
        XCTAssertTrue(disabled[0].hasSuffix(L("sticky.settings.shortcut.disabled", fallback: "已禁用")), "实际: \(disabled[0])")
        XCTAssertTrue(disabled[1].hasSuffix("⌥⌘P"))
    }

    // MARK: - 字符串表完整性（设置页文案）

    /// 两份 Localizable.strings 键集合一致；源码里用到的 sticky.settings.* 键两份表都有、
    /// 且 zh 表的值与调用处的 fallback 一致（fallback 是表缺失/损坏时的兜底，不能各写各的）
    func test字符串表_两份键一致_便利贴设置页用到的键都在且与fallback一致() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)          // …/Tests/QuiteNoteTests/X.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let zhURL = packageRoot.appendingPathComponent("Sources/QuiteNote/Resources/Localization/zh-Hans.lproj/Localizable.strings")
        let enURL = packageRoot.appendingPathComponent("Sources/QuiteNote/Resources/Localization/en.lproj/Localizable.strings")
        guard let zh = Self.parseStringsFile(zhURL), let en = Self.parseStringsFile(enURL) else {
            throw XCTSkip("找不到 Localizable.strings（#filePath=\(#filePath)），跳过")
        }
        let keyDifference = Set(zh.keys).symmetricDifference(en.keys)
        XCTAssertTrue(keyDifference.isEmpty, "两份字符串表的键集合必须一致，只在其中一份里的键: \(keyDifference.sorted())")

        let sources = packageRoot.appendingPathComponent("Sources/QuiteNote")
        let used = Self.collectStickySettingsCalls(under: sources)
        XCTAssertFalse(used.isEmpty, "没扫到任何 sticky.settings.* 调用，扫描逻辑可能失效")

        for (key, fallback) in used.sorted(by: { $0.key < $1.key }) {
            XCTAssertNotNil(zh[key], "zh-Hans 缺少 \(key)")
            XCTAssertNotNil(en[key], "en 缺少 \(key)")
            XCTAssertFalse(zh[key]?.isEmpty ?? true, "\(key) 的 zh 值为空")
            XCTAssertFalse(en[key]?.isEmpty ?? true, "\(key) 的 en 值为空")
            XCTAssertEqual(zh[key], fallback, "\(key) 的 zh 表值与调用处 fallback 不一致")
        }
        // 反向：表里的 sticky.settings.* 键都不能是没人用的死条目。
        // knownConflicts 的键是数据里的字符串字面量、不走 L() 字面量调用，按白名单核对
        let dataDrivenKeys = ["sticky.settings.shortcut.finderWarning",
                              "sticky.settings.shortcut.finderSelectionWarning",
                              "sticky.settings.shortcut.smartFolderWarning"]
        for key in dataDrivenKeys {
            XCTAssertNotNil(zh[key], "zh-Hans 缺少 \(key)")
            XCTAssertNotNil(en[key], "en 缺少 \(key)")
        }
        let dead = zh.keys.filter { $0.hasPrefix("sticky.settings.") && used[$0] == nil && !dataDrivenKeys.contains($0) }
        XCTAssertTrue(dead.isEmpty, "字符串表里有已无人使用的键: \(dead)")
    }

    /// 解析 .strings（本项目每行一条 "key" = "value"; 的老式 plist）；有任何一行解析不了就返回 nil
    private static func parseStringsFile(_ url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        guard let regex = try? NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";$"#) else { return nil }
        var table: [String: String] = [:]
        for line in lines {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { return nil }
            table[unescape(String(line[keyRange]))] = unescape(String(line[valueRange]))
        }
        guard table.count == lines.count else { return nil }   // 重复键
        return table
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// 扫描目录下所有 Swift 源码里的 L("sticky.settings.*", fallback: "…") 调用（跳过注释行）
    private static func collectStickySettingsCalls(under directory: URL) -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil),
              let regex = try? NSRegularExpression(pattern: #"L\("(sticky\.settings\.[A-Za-z0-9_.]+)",\s*fallback:\s*"([^"]*)""#) else { return [:] }
        var result: [String: String] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for rawLine in text.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: line),
                          let valueRange = Range(match.range(at: 2), in: line) else { continue }
                    result[String(line[keyRange])] = unescape(String(line[valueRange]))
                }
            }
        }
        return result
    }
}
