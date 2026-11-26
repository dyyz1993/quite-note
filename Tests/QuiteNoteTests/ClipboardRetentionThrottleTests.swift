import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// 捕获热路径的保留策略节流判定（纯函数）
///
/// applyRetentionIfNeeded 全量执行时会 fetchPage(limit: .max) 物化整库，
/// 只允许在「总数超上限 / 距上次清理超过节流间隔 / 强制」时触发。
final class ClipboardRetentionThrottleTests: XCTestCase {

    private func run(
        force: Bool = false,
        totalCount: Int,
        maxEntries: Int = 500,
        lastRunAgo: TimeInterval?,
        throttle: TimeInterval = ClipboardHistoryStore.retentionThrottleInterval
    ) -> Bool {
        let now = Date()
        return ClipboardHistoryStore.shouldRunRetention(
            force: force,
            totalCount: totalCount,
            maxEntries: maxEntries,
            lastRunAt: lastRunAgo.map { now.addingTimeInterval(-$0) },
            now: now,
            throttle: throttle
        )
    }

    /// 常态：未超限且刚清过 → 跳过全量（这是每次复制要省掉的那一步）
    func test未超限且刚清过不执行() {
        XCTAssertFalse(run(totalCount: 500, maxEntries: 500, lastRunAgo: 10))
        XCTAssertFalse(run(totalCount: 1, maxEntries: 500, lastRunAgo: ClipboardHistoryStore.retentionThrottleInterval - 0.5))
    }

    /// 总数超过上限：不管节流，立即执行（count 是廉价查询）
    func test超上限立即执行() {
        XCTAssertTrue(run(totalCount: 501, maxEntries: 500, lastRunAgo: 0.1))
        XCTAssertTrue(run(totalCount: 2000, maxEntries: 500, lastRunAgo: 0))
    }

    /// 距上次清理超过节流间隔：执行（给「按天过期」留上限；边界值含等于）
    func test过节流间隔执行() {
        XCTAssertTrue(run(totalCount: 100, maxEntries: 500, lastRunAgo: ClipboardHistoryStore.retentionThrottleInterval))
        XCTAssertTrue(run(totalCount: 100, maxEntries: 500, lastRunAgo: ClipboardHistoryStore.retentionThrottleInterval + 3600))
    }

    /// 设置页「立即清理过期记录」：无条件执行
    func test强制执行() {
        XCTAssertTrue(run(force: true, totalCount: 1, maxEntries: 500, lastRunAgo: 0))
    }

    /// 本次会话还没清过（启动后的第一次）：必须执行
    func test从未清理过执行() {
        XCTAssertTrue(run(totalCount: 1, maxEntries: 500, lastRunAgo: nil))
    }
}
