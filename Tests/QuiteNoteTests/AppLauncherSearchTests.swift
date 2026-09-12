import XCTest
@testable import QuiteNote

/// 应用启动器搜索打分与 MRU 纯逻辑
final class AppLauncherSearchTests: XCTestCase {

    // 显式传拼音的便利构造（打分测试不依赖真实转换结果，确定性优先）
    private func app(_ name: String, _ bundleID: String, pinyin: String, initials: String,
                     system: Bool = false) -> LauncherApp {
        LauncherApp(name: name, bundleID: bundleID,
                    url: URL(fileURLWithPath: "/Applications/\(name).app"),
                    isSystem: system, pinyinFull: pinyin, pinyinInitials: initials)
    }

    private var catalog: [LauncherApp] {
        [
            app("Safari 浏览器", "com.apple.Safari", pinyin: "safari liu lan qi", initials: "sllq", system: true),
            app("微信", "com.tencent.xinWeChat", pinyin: "wei xin", initials: "wx"),
            app("Google Chrome", "com.google.Chrome", pinyin: "google chrome", initials: "gc"),
            app("三星笔记", "com.samsung.notes", pinyin: "san xing bi ji", initials: "sxbj"),
            app("网易云音乐", "com.netease.163music", pinyin: "wang yi yun yin le", initials: "wyyyl"),
            app("Steam", "com.valve.steam", pinyin: "steam", initials: "s"),
        ]
    }

    func test拼音首字母_搜wx命中微信() {
        let results = AppSearchService.search("wx", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "微信")
    }

    func test全拼前缀_搜weixin命中微信() {
        let results = AppSearchService.search("weixin", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "微信")
    }

    func test名称前缀优先于拼音前缀() {
        // "sa"：Safari 名称前缀(100) 应排在 三星笔记 全拼前缀(80) 之前
        let results = AppSearchService.search("sa", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "Safari 浏览器")
        XCTAssertTrue(results.contains { $0.name == "三星笔记" })
    }

    func test名称包含_搜chrome() {
        let results = AppSearchService.search("chrome", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "Google Chrome")
    }

    func testbundleID包含() {
        let results = AppSearchService.search("xinwechat", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "微信")
    }

    func test大小写与首尾空白归一() {
        let results = AppSearchService.search("  WX ", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "微信")
    }

    func test空查询返回MRU顺序并过滤已卸载() {
        let recent = ["com.netease.163music", "已卸载的id", "com.apple.Safari"]
        let results = AppSearchService.search("", in: catalog, recentIDs: recent)
        XCTAssertEqual(results.map(\.name), ["网易云音乐", "Safari 浏览器"])
    }

    func test最近使用加权_同档位recent靠前() {
        // Safari 与 Steam 同为名称前缀 "s"（100 分）；Steam 是最近使用 → +5 排第一
        let results = AppSearchService.search("s", in: catalog, recentIDs: ["com.valve.steam"])
        XCTAssertEqual(results.first?.name, "Steam")
        // 命中四个：Steam(105) / Safari(名称前缀 100) / 三星笔记(首字母前缀 90) /
        // 网易云音乐(bundleID com.netease.163music 含 s → 30)
        XCTAssertEqual(results.count, 4)
    }

    func test无命中返回空() {
        XCTAssertTrue(AppSearchService.search("zzz不存在的应用", in: catalog, recentIDs: []).isEmpty)
    }

    // MARK: - 多词搜索（空格拆 token，全部命中才保留）

    func test多词搜索_goo_chr命中GoogleChrome() {
        let results = AppSearchService.search("goo chr", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "Google Chrome")
    }

    func test多词搜索_乱序同样命中() {
        let results = AppSearchService.search("chr goo", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "Google Chrome")
    }

    func test多词搜索_任一token失配则排除() {
        XCTAssertTrue(AppSearchService.search("goo zzz", in: catalog, recentIDs: []).isEmpty)
    }

    func test多词搜索_拼音分段_万云() {
        // "wan"（网易云全拼前缀）+ "y"（首字母含 y）双命中
        let results = AppSearchService.search("wan y", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "网易云音乐")
    }

    // MARK: - 子序列模糊匹配（兜底层）

    func test名称子序列_gch命中GoogleChrome() {
        // "gch" 不是 "google chrome" 的子串，但是子序列（g..c..h）
        let results = AppSearchService.search("gch", in: catalog, recentIDs: [])
        XCTAssertEqual(results.first?.name, "Google Chrome")
    }

    func test首字母子序列_wd命中微信读书() {
        let weRead = app("微信读书", "com.tencent.weread", pinyin: "wei xin du shu", initials: "wxds")
        let results = AppSearchService.search("wd", in: catalog + [weRead], recentIDs: [])
        XCTAssertTrue(results.contains { $0.name == "微信读书" })
    }

    func test子序列_快于包含的仍排前面() {
        // "ch" 在 Google Chrome 是名称包含(60)，在 Clash Royale 是名称子序列(25) → Chrome 第一
        let clash = app("Clash Royale", "com.supercell.clashroyale", pinyin: "clash royale", initials: "cr")
        let results = AppSearchService.search("ch", in: catalog + [clash], recentIDs: [])
        XCTAssertEqual(results.first?.name, "Google Chrome")
        XCTAssertTrue(results.contains { $0.name == "Clash Royale" })
    }

    func testisSubsequence基础() {
        XCTAssertTrue(AppSearchService.isSubsequence("gch", of: "google chrome"))
        XCTAssertTrue(AppSearchService.isSubsequence("", of: "abc"))
        XCTAssertFalse(AppSearchService.isSubsequence("z", of: "微信"))
        XCTAssertFalse(AppSearchService.isSubsequence("abcz", of: "abc"))
    }

    func testtokenize_空白分词归一() {
        XCTAssertEqual(AppSearchService.tokenize("  Goo   Chr "), ["goo", "chr"])
        XCTAssertEqual(AppSearchService.tokenize("wx"), ["wx"])
        XCTAssertTrue(AppSearchService.tokenize("   ").isEmpty)
    }

    // MARK: - 目录磁盘缓存（首开秒显，2026-09-11 十二轮）

    func test目录缓存编解码往返_预计算字段随缓存恢复() throws {
        let apps = [
            LauncherApp(name: "微信", bundleID: "com.tencent.xinWeChat",
                        url: URL(fileURLWithPath: "/Applications/WeChat.app"), isSystem: false),
            LauncherApp(name: "终端", bundleID: "com.apple.Terminal",
                        url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), isSystem: true),
        ]
        let data = try XCTUnwrap(AppCatalogStore.encodeCatalog(apps, scannedAt: Date()), "编码失败")
        let decoded = try XCTUnwrap(AppCatalogStore.decodeCatalog(data), "解码失败")
        XCTAssertEqual(decoded.apps, apps)
        // 预计算字段随缓存恢复（不重算 CFStringTransform）
        XCTAssertEqual(decoded.apps[0].pinyinCompact, "weixin")
        XCTAssertEqual(decoded.apps[0].initialsNormalized, "wx")
        XCTAssertEqual(decoded.apps[1].isSystem, true)
    }

    func test目录缓存_损坏数据与版本不符返回nil() throws {
        XCTAssertNil(AppCatalogStore.decodeCatalog(Data("not json".utf8)))
        // 手工构造 version=999 的包裹 → 丢弃
        let apps = [LauncherApp(name: "微信", bundleID: "x", url: URL(fileURLWithPath: "/x.app"), isSystem: false)]
        let wrapped = try XCTUnwrap(AppCatalogStore.encodeCatalog(apps, scannedAt: Date()))
        // 正常数据可解（对照）
        XCTAssertNotNil(AppCatalogStore.decodeCatalog(wrapped))
        // 篡改 version 字段
        let mutated = String(data: wrapped, encoding: .utf8)!.replacingOccurrences(of: "\"version\":1", with: "\"version\":999")
        XCTAssertNil(AppCatalogStore.decodeCatalog(Data(mutated.utf8)))
    }

    // MARK: - 预计算字段（卡顿修复：搜索热路径零字符串转换）

    func test预计算字段_构造时生成() {
        let wechat = LauncherApp(name: "微信", bundleID: "com.tencent.xinWeChat",
                                 url: URL(fileURLWithPath: "/Applications/WeChat.app"), isSystem: false)
        XCTAssertEqual(wechat.nameNormalized, "微信")
        XCTAssertEqual(wechat.pinyinCompact, "weixin")
        XCTAssertEqual(wechat.initialsNormalized, "wx")
        XCTAssertEqual(wechat.bundleIDLower, "com.tencent.xinwechat")

        let chrome = LauncherApp(name: "Google Chrome", bundleID: "com.google.Chrome",
                                 url: URL(fileURLWithPath: "/Applications/Chrome.app"), isSystem: false)
        XCTAssertEqual(chrome.nameNormalized, "google chrome")
        XCTAssertEqual(chrome.pinyinCompact, "googlechrome")
        XCTAssertEqual(chrome.initialsNormalized, "gc")
    }

    func test性能_2000应用单次搜索亚毫秒级() {
        let bigCatalog = (0..<2000).map { i in
            app("测试应用\(i)号", "com.test.app\(i)", pinyin: "ce shi ying yong \(i) hao", initials: "csyy\(i)h")
        }
        let start = Date()
        let results = AppSearchService.search("wx", in: bigCatalog + catalog, recentIDs: [])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(results.first?.name, "微信")
        // 2168 个应用单次搜索应在 20ms 内（预计算后实测远低于此；超时说明热路径退化了）
        XCTAssertLessThan(elapsed, 0.02, "搜索热路径疑似退化：\(elapsed * 1000)ms")
    }

    // MARK: - MRU 纯逻辑

    func testMRU_新启动插到最前并去重() {
        var mru = ["a", "b", "c"]
        mru = AppCatalogStore.updateMRU(mru, inserting: "b")
        XCTAssertEqual(mru, ["b", "a", "c"])
        mru = AppCatalogStore.updateMRU(mru, inserting: "d")
        XCTAssertEqual(mru, ["d", "b", "a", "c"])
    }

    func testMRU_超限截断到十条() {
        let ids = (0..<12).map(String.init)
        let updated = AppCatalogStore.updateMRU(ids, inserting: "new")
        XCTAssertEqual(updated.count, 10)
        XCTAssertEqual(updated.first, "new")
        XCTAssertEqual(updated.last, "8")
    }
}
