import XCTest
@testable import QuiteNote

/// 启动器拼音搜索端到端（走真实生效路径：SearchIndexService + 真实 PinyinTransformer，
/// 文档构造方式与 AppLauncherViewModel.appIndexDocument/textIndexDocument 一致）
///
/// 背景：剪贴板索引曾漏传拼音字段导致拼音搜索失效——这里钉住启动器两条索引
/// 链路（App / 文本条目）不回退。
@MainActor
final class LauncherPinyinIndexTests: XCTestCase {

    private func appDoc(_ app: LauncherApp) -> SearchIndexDocument<LauncherApp> {
        SearchIndexDocument(
            id: app.id,
            source: .launcherApp,
            payload: app,
            normalizedTitle: app.nameNormalized,
            normalizedBody: app.bundleIDLower,
            normalizedPinyin: app.pinyinCompact,
            normalizedPinyinInitials: app.initialsNormalized
        )
    }

    private func textDoc(_ item: LauncherTextItem) -> SearchIndexDocument<LauncherTextItem> {
        SearchIndexDocument(
            id: item.id,
            source: .launcherText,
            payload: item,
            title: item.title,
            body: item.contentNormalized,
            pinyin: item.pinyinCompact,
            pinyinInitials: item.pinyinInitials,
            isPinned: item.kind == .favorite
        )
    }

    private func waitFirstApp(
        _ index: SearchIndexService<SearchIndexDocument<LauncherApp>>,
        query: String,
        expecting name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let exp = expectation(description: "app search '\(query)'")
        index.search(query, limit: 5) { page in
            defer { exp.fulfill() }
            XCTAssertEqual(page.documents.first?.payload.name, name, "拼音查询「\(query)」未命中", file: file, line: line)
        }
        wait(for: [exp], timeout: 5)
    }

    func test全拼无分隔命中中文应用() {
        let index = SearchIndexService<SearchIndexDocument<LauncherApp>>()
        index.rebuild(documents: [
            appDoc(LauncherApp(name: "微信", bundleID: "com.tencent.xinWeChat",
                               url: URL(fileURLWithPath: "/Applications/微信.app"), isSystem: false)),
            appDoc(LauncherApp(name: "Safari", bundleID: "com.apple.Safari",
                               url: URL(fileURLWithPath: "/Applications/Safari.app"), isSystem: true)),
        ])
        waitFirstApp(index, query: "weixin", expecting: "微信")
    }

    func test首字母命中中文应用() {
        let index = SearchIndexService<SearchIndexDocument<LauncherApp>>()
        index.rebuild(documents: [
            appDoc(LauncherApp(name: "微信", bundleID: "com.tencent.xinWeChat",
                               url: URL(fileURLWithPath: "/Applications/微信.app"), isSystem: false)),
        ])
        waitFirstApp(index, query: "wx", expecting: "微信")
    }

    func test全拼无分隔命中中文文本条目() {
        let index = SearchIndexService<SearchIndexDocument<LauncherTextItem>>()
        index.rebuild(documents: [
            textDoc(LauncherTextItem(kind: .memo, id: "memo-1", copyText: "会议纪要：周会同步")),
        ])
        let exp = expectation(description: "text search delivers")
        index.search("huiyijiyao", limit: 5) { page in
            defer { exp.fulfill() }
            XCTAssertEqual(page.documents.first?.payload.title, "会议纪要：周会同步")
        }
        wait(for: [exp], timeout: 5)
    }
}
