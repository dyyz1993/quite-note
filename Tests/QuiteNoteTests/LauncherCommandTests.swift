import XCTest
@testable import QuiteNote

/// 系统命令：拼音/别名匹配 + 破坏性标记
final class LauncherCommandTests: XCTestCase {

    func test拼音首字母_搜sp命中锁屏() {
        let matched = SystemCommandService.matchingCommands(tokens: ["sp"])
        XCTAssertEqual(matched.first?.title, "锁屏")
    }

    func test全拼_搜suoping命中锁屏() {
        let matched = SystemCommandService.matchingCommands(tokens: ["suoping"])
        XCTAssertEqual(matched.first?.title, "锁屏")
    }

    func test中文_搜关机() {
        XCTAssertEqual(SystemCommandService.matchingCommands(tokens: ["关机"]).first?.title, "关机")
    }

    func test英文别名_搜sleep和trash() {
        XCTAssertEqual(SystemCommandService.matchingCommands(tokens: ["sleep"]).first?.title, "睡眠")
        XCTAssertEqual(SystemCommandService.matchingCommands(tokens: ["trash"]).first?.title, "清倒废纸篓")
    }

    func test废纸篓首字母前缀_搜fzl() {
        // 清倒废纸篓 → qing dao fei zhi lou → 首字母 qdfzl，"fzl" 是中间段（contains 45）
        let matched = SystemCommandService.matchingCommands(tokens: ["fzl"])
        XCTAssertEqual(matched.first?.title, "清倒废纸篓")
    }

    func test空查询不返回命令() {
        XCTAssertTrue(SystemCommandService.matchingCommands(tokens: []).isEmpty)
    }

    func test无命中返回空() {
        XCTAssertTrue(SystemCommandService.matchingCommands(tokens: ["zzz不存在"]).isEmpty)
    }

    func test破坏性命令标记() {
        let destructive = ["清倒废纸篓", "重启电脑", "关机"]
        for cmd in LauncherCommand.all {
            XCTAssertEqual(cmd.requiresConfirmation, destructive.contains(cmd.title),
                           "\(cmd.title) 的二次确认标记不符预期")
        }
    }

    func test多token全命中才保留() {
        // "清 废"：清(名称前缀) + 废(名称包含) 都命中清倒废纸篓
        let matched = SystemCommandService.matchingCommands(tokens: ["清", "废"])
        XCTAssertTrue(matched.contains { $0.title == "清倒废纸篓" })
        // "锁 sleep"：锁命中锁屏但 sleep 不命中锁屏 → 整体排除
        XCTAssertTrue(SystemCommandService.matchingCommands(tokens: ["锁", "sleep"]).isEmpty)
    }
}
