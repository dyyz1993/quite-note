import QuiteNoteSharedStorage
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
        let same = ClipboardDetailPane(entry: a)
        let sameCopy = ClipboardDetailPane(entry: b)
        let empty = ClipboardDetailPane(entry: nil)

        // Warm up the SwiftUI/Equatable specialization before measuring; the first
        // call can include one-time runtime setup that is unrelated to field access.
        XCTAssertTrue(same == sameCopy)
        XCTAssertFalse(same == empty)

        var samples: [Double] = []
        samples.reserveCapacity(21)
        for _ in 0...20 {
            let start = DispatchTime.now()
            XCTAssertTrue(same == sameCopy)
            XCTAssertFalse(same == empty)
            let end = DispatchTime.now()
            samples.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[(samples.count * 95) / 100]
        // Identity equality must not traverse the 1MB text payload. A median/p95
        // pair avoids failing the whole suite on a single scheduler scheduling blip.
        XCTAssertLessThan(median, 0.1, "身份比较中位耗时不得接近文本扫描（median=\(median)ms）")
        XCTAssertLessThan(p95, 1.0, "身份比较 p95 不得触碰 1MB 文本（p95=\(p95)ms, samples=\(samples)）")
    }
}
