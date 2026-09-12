import XCTest
@testable import QuiteNote

/// 启动器符号搜索（复用符号库）+ 条目身份
final class LauncherSymbolTests: XCTestCase {

    func testSymbolItem身份与内容() {
        let sym = SymbolItem(triggers: ["笑", "笑脸"], content: "😊", desc: "微笑")
        XCTAssertEqual(LauncherItem.symbol(sym).id, "sym:" + sym.id.uuidString)
        XCTAssertEqual(sym.content, "😊")
    }

    @MainActor
    func test符号库搜索_触发词反查必命中() throws {
        let manager = SymbolConfigManager.shared
        manager.loadConfigs()
        // 不依赖具体词条（隔离目录的默认集可能被裁剪）：任一符号按其自身触发词反查
        let allSymbols = manager.enabledConfigs.flatMap { config in
            config.menus.flatMap { $0.symbols }
        }
        guard let probe = allSymbols.first(where: { $0.triggers.first?.isEmpty == false }) else {
            throw XCTSkip("测试进程符号目录无配置（重定向隔离）")
        }
        let trigger = probe.triggers.first!
        let hits = manager.searchSymbols(query: trigger)
        XCTAssertTrue(hits.contains { $0.content == probe.content },
                      "按触发词「\(trigger)」应命中符号 \(probe.content)")
    }
}
