import SwiftUI
import XCTest
@testable import QuiteNote

/// 便利贴底部工具栏的布局与文案（2026-11-25 实机验证发现：工具栏比默认宽度的便签还宽，
/// 编辑区被挤得左移、每行开头裁掉）。不进窗口：NSHostingController 不装进任何窗口也能按给定宽度报尺寸
@MainActor
final class StickyNoteToolbarTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    /// 工具栏在「便签宽度」下的实际宽度（工具栏自带两侧 8pt 边距）
    private func toolbarWidth(stickyWidth: CGFloat) -> CGFloat {
        let toolbar = StickyNoteToolbar(note: .constant(StickyNoteModel()), onCommand: { _ in })
        // NSHostingController 不装进窗口也能按"给定宽度"报出实际尺寸
        return NSHostingController(rootView: toolbar).sizeThatFits(in: CGSize(width: stickyWidth, height: 60)).width
    }

    /// 默认便签 300pt 宽：常规栏被选中（带弹性间距，会撑满可用宽度），所有按钮都在便签内
    func testRegularToolbarFitsTheDefaultStickyWidth() {
        XCTAssertEqual(toolbarWidth(stickyWidth: StickyNoteGeometry.defaultSize.width),
                       StickyNoteGeometry.defaultSize.width, accuracy: 0.5)
    }

    /// 最窄 150pt：切到紧凑栏（没有弹性间距，宽度是定值），同样不超出便签
    func testCompactToolbarFitsTheNarrowestSticky() {
        let narrowest = toolbarWidth(stickyWidth: StickyNoteGeometry.minimumSize.width)
        XCTAssertLessThanOrEqual(narrowest, StickyNoteGeometry.minimumSize.width)
        XCTAssertLessThan(narrowest, toolbarWidth(stickyWidth: StickyNoteGeometry.defaultSize.width))
        // 紧凑栏是定宽的：再宽一点的便签里，直到常规栏放得下之前，宽度都不变
        XCTAssertEqual(narrowest, toolbarWidth(stickyWidth: 180), accuracy: 0.5)
    }

    /// 便签底色和文字颜色的菜单文案、工具栏里新增的菜单标题：两份字符串表都要有
    func testToolbarAndColorStringsExistInBothLocalizationTables() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)          // …/Tests/QuiteNoteTests/X.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let regex = try NSRegularExpression(pattern: #"^"([^"]+)"\s*=\s*"(.*)";$"#)
        var tables: [[String: String]] = []
        for language in ["zh-Hans", "en"] {
            let url = packageRoot.appendingPathComponent("Sources/QuiteNote/Resources/Localization/\(language).lproj/Localizable.strings")
            var table: [String: String] = [:]
            for rawLine in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let keyRange = Range(match.range(at: 1), in: line),
                      let valueRange = Range(match.range(at: 2), in: line) else { continue }
                table[String(line[keyRange])] = String(line[valueRange])
            }
            tables.append(table)
        }
        XCTAssertEqual(Set(tables[0].keys), Set(tables[1].keys), "两份字符串表的键集合必须一致")

        let required = StickyNoteColor.allCases.map(\.nameKey) + [
            "sticky.textColor.yellow", "sticky.textColor.blue", "sticky.textColor.green", "sticky.textColor.red",
            "sticky.toolbar.resetTextColor", "sticky.toolbar.textColor", "sticky.toolbar.noteColor",
            "sticky.toolbar.pages", "sticky.toolbar.pageFormat", "sticky.toolbar.more",
        ]
        for (language, table) in zip(["zh-Hans", "en"], tables) {
            for key in required {
                XCTAssertFalse(table[key]?.isEmpty ?? true, "\(language) 缺少 \(key)")
            }
        }
        XCTAssertEqual(tables[0]["sticky.toolbar.pageFormat"], "第 %d 页", "带占位符的文案要保持 %d 不被翻译掉")
        XCTAssertEqual(tables[1]["sticky.toolbar.pageFormat"], "Page %d")
    }
}
