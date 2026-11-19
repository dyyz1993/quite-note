import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// 列表 ⌘N 序号标签三态展示 + 滚动增量更新 + footer 选中进度
@MainActor
final class ClipRowNumberingTests: XCTestCase {

    private func makeEntry(_ n: Int) -> ClipboardEntry {
        ClipboardEntry(
            type: .text,
            createdAt: Date().addingTimeInterval(Double(n)),
            plainText: "row-\(n)",
            contentHash: "row-\(n)"
        )
    }

    // MARK: - 三态文案（纯函数）

    func test序号文案_选中显示回车() {
        XCTAssertEqual(ClipRowCell.shortcutText(isSelected: true, paletteNumber: 3, index: 9), "⏎")
    }

    func test序号文案_视口内显示快捷键() {
        XCTAssertEqual(ClipRowCell.shortcutText(isSelected: false, paletteNumber: 1, index: 4), "⌘1")
        XCTAssertEqual(ClipRowCell.shortcutText(isSelected: false, paletteNumber: 9, index: 12), "⌘9")
    }

    func test序号文案_视口外显示行号兜底() {
        XCTAssertEqual(ClipRowCell.shortcutText(isSelected: false, paletteNumber: nil, index: 0), "1")
        XCTAssertEqual(ClipRowCell.shortcutText(isSelected: false, paletteNumber: nil, index: 11), "12")
    }

    func test序号文案_淡化规则() {
        XCTAssertEqual(ClipRowCell.shortcutAlpha(isSelected: false, paletteNumber: nil), 0.4)
        XCTAssertEqual(ClipRowCell.shortcutAlpha(isSelected: false, paletteNumber: 2), 1)
        XCTAssertEqual(ClipRowCell.shortcutAlpha(isSelected: true, paletteNumber: nil), 1)
    }

    // MARK: - 增量更新（滚动路径：不重建行，只改标签）

    func test增量更新序号不重建行() {
        let cell = ClipRowCell(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        cell.configure(entry: makeEntry(0), index: 4, isSelected: false, paletteNumber: 5)
        XCTAssertEqual(cell.shortcutTextForTesting, "⌘5")

        // 视口下移一行 → 序号跟随（⌘5 → ⌘4）
        cell.updatePaletteNumber(4)
        XCTAssertEqual(cell.shortcutTextForTesting, "⌘4")

        // 滚出 ⌘1–9 窗口 → 行号兜底
        cell.updatePaletteNumber(nil)
        XCTAssertEqual(cell.shortcutTextForTesting, "5")
        XCTAssertEqual(cell.shortcutAlphaForTesting, 0.4)

        // 同值重复上报无副作用（守卫分支）
        cell.updatePaletteNumber(nil)
        XCTAssertEqual(cell.shortcutTextForTesting, "5")
    }

    // MARK: - 滚动位置纯计算（reportVisibleTop 路径）

    private typealias Update = ClipboardListTableView.Coordinator.ViewportUpdate

    func test滚动纯计算_首行未变不产生更新() {
        let update = ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 0, visibleLength: 12, entryCount: 100, currentTop: 0
        )
        XCTAssertFalse(update.topChanged)
        XCTAssertTrue(update.paletteUpdates.isEmpty)
        XCTAssertFalse(update.loadMore)
    }

    func test滚动纯计算_下移一行刷新整个可见区间序号() {
        let update = ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 1, visibleLength: 12, entryCount: 100, currentTop: 0
        )
        XCTAssertTrue(update.topChanged)
        XCTAssertEqual(update.newTop, 1)
        XCTAssertEqual(update.paletteUpdates.count, 12)
        XCTAssertEqual(update.paletteUpdates.first, Update.PaletteUpdate(row: 1, slot: 1))
        XCTAssertEqual(update.paletteUpdates[8], Update.PaletteUpdate(row: 9, slot: 9))
        // 第 10 行起超出 ⌘1–9 窗口 → 行号兜底
        XCTAssertEqual(update.paletteUpdates[9], Update.PaletteUpdate(row: 10, slot: nil))
        XCTAssertEqual(update.paletteUpdates.last, Update.PaletteUpdate(row: 12, slot: nil))
    }

    func test滚动纯计算_翻页阈值() {
        // 100 条：位置 58 + 12 = 70 ≥ 100-30 → 请求下一页
        XCTAssertTrue(ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 58, visibleLength: 12, entryCount: 100, currentTop: 57
        ).loadMore)
        // 位置 57 + 12 = 69 < 70 → 不请求
        XCTAssertFalse(ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 57, visibleLength: 12, entryCount: 100, currentTop: 56
        ).loadMore)
    }

    func test滚动纯计算_空可见区与尾部裁剪() {
        let empty = ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 0, visibleLength: 0, entryCount: 100, currentTop: 0
        )
        XCTAssertFalse(empty.loadMore)
        XCTAssertFalse(empty.topChanged)
        XCTAssertTrue(empty.paletteUpdates.isEmpty)

        // 尾部 overscroll：可见长度超过剩余行数 → 裁剪到 entryCount-1
        let tail = ClipboardListTableView.Coordinator.viewportUpdate(
            visibleLocation: 5, visibleLength: 12, entryCount: 10, currentTop: 4
        )
        XCTAssertEqual(tail.paletteUpdates.map(\.row), [5, 6, 7, 8, 9])
        XCTAssertEqual(tail.paletteUpdates.map(\.slot), [1, 2, 3, 4, 5])
    }

    func test序号更新应用到桩cell() {
        let parent = ClipboardListTableView(
            entries: [], entriesVersion: 0, selectedIndex: .constant(0),
            onSingleClick: { _ in }, onDoubleClick: { _ in },
            onVisibleTopChanged: { _ in }, onLoadMore: {}
        )
        let coordinator = ClipboardListTableView.Coordinator(parent)
        var cells: [Int: ClipRowCell] = [:]
        for row in 0..<3 {
            let cell = ClipRowCell(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
            cell.configure(entry: makeEntry(row), index: row, isSelected: false, paletteNumber: nil)
            cells[row] = cell
        }
        let updates: [Update.PaletteUpdate] = [
            .init(row: 0, slot: 1),
            .init(row: 1, slot: nil),
            .init(row: 2, slot: nil),
            .init(row: 99, slot: 9), // 不存在的行必须静默跳过
        ]
        coordinator.applyPaletteUpdates(updates) { cells[$0] }

        XCTAssertEqual(cells[0]?.shortcutTextForTesting, "⌘1")
        XCTAssertEqual(cells[1]?.shortcutTextForTesting, "2")
        XCTAssertEqual(cells[2]?.shortcutTextForTesting, "3")
    }

    // MARK: - footer 选中进度

    func test选中进度_空列表为nil() {
        let vm = ClipboardHistoryViewModel()
        XCTAssertNil(vm.selectionProgress)
    }

    func test选中进度_正常与越界钳制() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        (0..<3).forEach { store.insertOrUpdate(makeEntry($0)) }
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        vm.selectedIndex = 1
        XCTAssertEqual(vm.selectionProgress?.current, 2)
        XCTAssertEqual(vm.selectionProgress?.total, 3)

        // 删除后的暂态越界：钳制到最后一条，不显示越界值
        vm.selectedIndex = 99
        XCTAssertEqual(vm.selectionProgress?.current, 3)
    }
}
