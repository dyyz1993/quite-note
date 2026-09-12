import XCTest
@testable import QuiteNote

/// 打字/删除路径性能基线（用户反馈输入卡顿，2026-09-12 十五轮修复的防退化钉子）
final class ClipboardTypingPerfTests: XCTestCase {

    private func makeEntries(_ n: Int) -> [ClipboardEntry] {
        let base = Date().addingTimeInterval(-Double(n) * 10)
        return (0..<n).map { i in
            ClipboardEntry(
                type: .text,
                createdAt: base.addingTimeInterval(Double(i) * 10),
                plainText: String(repeating: "内容\(i) ", count: 20),
                sourceApp: "T", sourceBundleID: "t",
                contentHash: "h\(i)"
            )
        }
    }

    func test空查询免排序_500条亚毫秒() {
        let entries = makeEntries(500)
        let start = Date()
        let result = ClipboardSearchService.search("", in: entries)
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertEqual(result.count, 500)
        XCTAssertLessThan(ms, 2, "空查询必须免排序直通（\(ms)ms）")
    }

    func test空查询保持传入顺序() {
        // store 顺序 = 置顶优先+时间倒序 的不变式由插入/移动端保证，search 不得重排
        let entries = makeEntries(20)
        let result = ClipboardSearchService.search("", in: entries)
        XCTAssertEqual(result.map(\.id), entries.map(\.id))
    }

    func test查询过滤500条_30ms内() {
        let entries = makeEntries(500)
        _ = ClipboardSearchService.search("内容1", in: entries)  // 预热（首次含归一化冷启动）
        let start = Date()
        _ = ClipboardSearchService.search("内容12", in: entries)
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertLessThan(ms, 30, "500 条查询过滤应 <30ms（实测 \(ms)ms；防退化目标是挡 O(n²) 回潮）")
    }

    func test详情面板按身份相等_大文本零成本() {
        let big = String(repeating: "x", count: 1_000_000)
        let a = ClipboardEntry(type: .text, createdAt: Date(), plainText: big,
                               contentHash: "a")
        let b = a  // 同一条目，不同实例也行（值拷贝）
        let start = Date()
        XCTAssertTrue(ClipboardDetailPane(entry: a) == ClipboardDetailPane(entry: b))
        XCTAssertEqual(ClipboardDetailPane(entry: a) == ClipboardDetailPane(entry: nil), false)
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertLessThan(ms, 1, "身份比较不得触碰 1MB 文本（\(ms)ms）")
    }
}
