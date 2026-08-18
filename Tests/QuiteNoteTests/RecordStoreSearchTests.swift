import XCTest
@testable import QuiteNote

/// RecordStore 层搜索行为测试：搜索历史写入时机
final class RecordStoreSearchTests: XCTestCase {

    private var savedHistory: Any?

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        // 数据隔离红线：UserDefaults 改动必须保存/恢复
        savedHistory = UserDefaults.standard.object(forKey: "searchHistory")
        UserDefaults.standard.removeObject(forKey: "searchHistory")
    }

    override func tearDown() {
        if let old = savedHistory {
            UserDefaults.standard.set(old, forKey: "searchHistory")
        } else {
            UserDefaults.standard.removeObject(forKey: "searchHistory")
        }
        super.tearDown()
    }

    /// 连续按键式搜索（a → ab → abc）：搜索历史只记录防抖后真正执行的查询。
    /// 旧行为：防抖前立即写入历史 → 每个半截词都进历史，且每次按键触发
    /// searchHistory @Published 更新 → 搜索栏重渲染，加剧输入卡顿
    func testDebouncedSearchRecordsOnlyExecutedQueryInHistory() {
        let store = RecordStore()

        XCTAssertTrue(store.searchHistory.isEmpty, "前置条件：历史为空")

        let executed = expectation(description: "最终搜索交付")
        // 前两次与第三次几乎同时发起：前两次的防抖任务会被取消，只有 abc 真正执行
        store.debouncedSearch("a", delay: 0.3) { _ in }
        store.debouncedSearch("ab", delay: 0.3) { _ in }
        store.debouncedSearch("abc", delay: 0.1) { _ in executed.fulfill() }

        wait(for: [executed], timeout: 3)

        XCTAssertFalse(store.searchHistory.contains("a"), "半截词 'a' 不得写入搜索历史")
        XCTAssertFalse(store.searchHistory.contains("ab"), "半截词 'ab' 不得写入搜索历史")
        XCTAssertTrue(store.searchHistory.contains("abc"), "真正执行的 'abc' 应记入历史")
    }
}
