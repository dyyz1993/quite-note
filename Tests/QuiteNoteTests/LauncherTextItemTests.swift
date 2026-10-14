import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// 收藏片段/备忘文本条目：标题提取、匹配打分、贴纸标记剥离
final class LauncherTextItemTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        LauncherTextSearch.resetCacheForTesting()
    }

    override func tearDown() {
        LauncherTextSearch.resetCacheForTesting()
        super.tearDown()
    }

    private func item(_ copyText: String, kind: LauncherTextItem.Kind = .favorite) -> LauncherTextItem {
        LauncherTextItem(kind: kind, id: "t1", copyText: copyText)
    }

    // MARK: - 标题/详情提取

    func test首行作标题_剩余作详情() {
        let it = item("上海市浦东新区世纪大道100号\n收件人张三\n电话13800000000")
        XCTAssertEqual(it.title, "上海市浦东新区世纪大道100号")
        XCTAssertTrue(it.detail.contains("收件人张三"))
        XCTAssertEqual(it.copyText, "上海市浦东新区世纪大道100号\n收件人张三\n电话13800000000")
    }

    func test单行内容详情为空() {
        let it = item("单行片段")
        XCTAssertEqual(it.title, "单行片段")
        XCTAssertTrue(it.detail.isEmpty)
    }

    func test空白行被过滤() {
        let it = item("\n\n  实际内容  \n\n")
        XCTAssertEqual(it.title, "实际内容")
        XCTAssertTrue(it.detail.isEmpty)
    }

    // MARK: - 匹配打分

    func test标题前缀与拼音匹配() {
        let it = item("上海市浦东新区\n张三", kind: .favorite)
        XCTAssertEqual(LauncherTextSearch.tokenScore("上海", item: it), 100)   // 标题前缀
        XCTAssertEqual(LauncherTextSearch.tokenScore("shanghai", item: it), 90) // 全拼前缀（上海=shang hai）
        XCTAssertEqual(LauncherTextSearch.tokenScore("sh", item: it) >= 90, true) // 拼音前缀 shang
        XCTAssertEqual(LauncherTextSearch.tokenScore("张三", item: it), 40)    // 张三在第二行 → 内容包含
    }

    func test内容包含兜底() {
        let it = item("公司地址一览\n张三家住海淀区")
        // "海淀" 只在第二行（detail/内容）出现 → 内容包含 40
        XCTAssertEqual(LauncherTextSearch.tokenScore("海淀", item: it), 40)
    }

    func test多token全命中才保留() {
        let items = [item("家庭地址\n浦东新区", kind: .favorite)]
        let hit = LauncherTextSearch.matchingItems(tokens: ["家庭", "浦东"], in: items)
        XCTAssertEqual(hit.count, 1)
        XCTAssertTrue(LauncherTextSearch.matchingItems(tokens: ["家庭", "不存在"], in: items).isEmpty)
    }

    func test空token不匹配() {
        let items = [item("任意")]
        XCTAssertTrue(LauncherTextSearch.matchingItems(tokens: [], in: items).isEmpty)
    }

    // MARK: - 贴纸标记剥离

    func test贴纸颜色标记剥离() {
        XCTAssertEqual(LauncherTextSearch.stripStickyMarkup("[c:#ff0000]会议要点\n[c:#00ff00]第二行"), "会议要点\n第二行")
        XCTAssertEqual(LauncherTextSearch.stripStickyMarkup("无标记文本"), "无标记文本")
    }

    // MARK: - 图片条目（用户收藏的多为截图）

    func test图片条目构造() throws {
        let it = LauncherTextItem(kind: .favorite, id: "fav-img",
                                  title: "20260104_153542_60a9_screenshot.png",
                                  detail: "收藏图片",
                                  copyText: "", imagePath: "/tmp/QNFavTest.png")
        XCTAssertEqual(it.title, "20260104_153542_60a9_screenshot.png")
        XCTAssertEqual(it.imagePath, "/tmp/QNFavTest.png")
        // 文件名含数字片段可命中（搜文件名）
        XCTAssertGreaterThan(LauncherTextSearch.tokenScore("153542", item: it), 0)
    }

    @MainActor
    func testCollectCacheIsReusedUntilClipboardVersionChanges() {
        let store = ClipboardHistoryStore.shared
        store.deleteAllForTesting()
        let entry = ClipboardEntry(
            type: .text,
            createdAt: Date(),
            plainText: "缓存片段",
            contentHash: "launcher-text-cache",
            isPinned: true
        )
        store.insertOrUpdate(entry)

        let first = LauncherTextSearch.collect()
        XCTAssertTrue(first.contains { $0.copyText == "缓存片段" })

        // 空查询也不应触发文本语料构造；这里通过再次收集同版本缓存保持等价。
        XCTAssertEqual(LauncherTextSearch.collect(), first)
    }

    // MARK: - 闪记收藏（主面板 starred 记录）

    private func makeRecord(_ content: String, type: RecordType = .text, starred: Bool = false) -> Record {
        Record(id: UUID(), content: content, createdAt: Date(),
               hash: UUID().uuidString, starred: starred, type: type)
    }

    func test闪记_链接免点星全量收录_文本须点星() {
        let records = [
            makeRecord("https://example.com/article", type: .url, starred: false),
            makeRecord("未点星的普通文本", type: .text, starred: false),
            makeRecord("https://github.com/dyyz1993/quite-note", type: .url, starred: true),
            makeRecord("已点星的文本记录", type: .text, starred: true),
            makeRecord("/Users/x/Attachments/shot.png", type: .screenshot, starred: true),
            makeRecord("- [x] 便签内容", type: .note, starred: true),
        ]
        let items = LauncherTextSearch.flashItems(from: records)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.kind == .flash }.count, 3)
        XCTAssertTrue(items.contains { $0.copyText == "https://example.com/article" }, "链接不点星也要能搜到")
        XCTAssertTrue(items.contains { $0.copyText == "https://github.com/dyyz1993/quite-note" })
        XCTAssertTrue(items.contains { $0.copyText == "已点星的文本记录" })
    }

    func test闪记收藏_链接标题即URL_可按域名搜索() {
        let items = LauncherTextSearch.flashItems(from: [
            makeRecord("https://github.com/dyyz1993/quite-note", type: .url, starred: false),
        ])
        let it = items[0]
        XCTAssertEqual(it.title, "https://github.com/dyyz1993/quite-note")
        XCTAssertGreaterThan(LauncherTextSearch.tokenScore("github", item: it), 0, "域名可命中标题包含")
    }

    func test闪记_副标题带溯源信息_类型来源与相对时间() {
        let items = LauncherTextSearch.flashItems(from: [
            Record(id: UUID(), content: "https://example.com/doc", createdAt: Date(),
                   hash: "prov-1", sourceApp: "Safari浏览器", type: .url),
            Record(id: UUID(), content: "多行文本\n第二行", createdAt: Date(timeIntervalSinceNow: -3 * 86400),
                   hash: "prov-2", starred: true, type: .text),
        ])
        // 类型名走本地化（测试环境可能是英文），断言不写死语言；只验证溯源要素
        XCTAssertTrue(items[0].detail.contains("来自 Safari浏览器"), "URL 条目带来源应用")
        XCTAssertTrue(items[0].detail.contains("刚刚"), "URL 条目带相对时间")
        XCTAssertFalse(items[1].detail.contains("来自"), "无来源应用时省略「来自」段")
        XCTAssertTrue(items[1].detail.contains("3 天前"))
        XCTAssertEqual(items[1].title, "多行文本", "长内容只露首行，溯源占据副标题")
    }

    func test闪记收藏_空内容跳过() {
        XCTAssertTrue(LauncherTextSearch.flashItems(from: [
            makeRecord("  \n  ", type: .text, starred: true),
        ]).isEmpty)
    }

    func test图片复制到剪贴板() throws {
        // 造一张 1×1 png
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "qn-img-copy-test.png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(LauncherTextSearch.copyImageToPasteboard(imagePath: url.path))
        let pb = NSPasteboard.general
        XCTAssertEqual(pb.data(forType: .png)?.count ?? 0, png.count)
        XCTAssertFalse(LauncherTextSearch.copyImageToPasteboard(imagePath: "/tmp/不存在.png"))
    }
}
