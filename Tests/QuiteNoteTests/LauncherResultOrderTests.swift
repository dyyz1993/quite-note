import XCTest
@testable import QuiteNote

/// 启动器结果排序：应用优先于符号/命令，闪记/收藏文本条目只做兜底填充
/// （2026-11-03 用户约定×2：主场景是启动应用，同等匹配下应用恒在前）
@MainActor
final class LauncherResultOrderTests: XCTestCase {

    private let webRow = LauncherItem.web(.init(
        presetName: "Google", term: "sa",
        url: URL(string: "https://g.com")!
    ))
    private let symbolRow = LauncherItem.symbol(
        SymbolItem(triggers: ["sad", "伤心"], content: "😢", desc: "伤心")
    )
    private let textRow = LauncherItem.text(
        LauncherTextItem(kind: .memo, id: "memo-1", copyText: "会议纪要")
    )
    private let appRow = LauncherItem.app(LauncherApp(
        name: "Safari", bundleID: "com.apple.Safari",
        url: URL(fileURLWithPath: "/Applications/Safari.app"), isSystem: true
    ))

    /// 回归钉子（截图案例）：搜 "sa" 时符号（触发词 sad）不得压在 Safari 之前
    func testAppInsertionBeforeSymbolAndText() {
        // 符号/文本先落地（同步区），应用回调后到 → 落点在第一个次级项之前
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow, symbolRow]), 1)
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow, textRow]), 1)
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow, symbolRow, textRow]), 1)

        var ordered = [webRow, symbolRow, textRow]
        ordered.insert(contentsOf: [appRow], at: 1)
        if case .app = ordered[1] {} else { XCTFail("应用必须排在符号之前") }
        if case .symbol = ordered[2] {} else { XCTFail("符号应保持在应用之后") }
        if case .text = ordered[3] {} else { XCTFail("文本兜底应保持在末尾") }
    }

    /// 顶部动作区（网页/退出/范围行）始终在应用之前
    func testTopActionRowsStayAboveApps() {
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow]), 1)
    }

    /// 无任何次级项 → 落点为末尾（追加语义）；空列表 → 0
    func testAppInsertionAtEndWhenNoSecondaryItems() {
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: []), 0)
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow]), 1)
    }

    /// 多个次级项 → 落点在第一个（不是最后一个）之前
    func testAppInsertionUsesFirstSecondaryItem() {
        XCTAssertEqual(AppLauncherViewModel.appInsertionIndex(in: [webRow, symbolRow, symbolRow]), 1)
    }
}
