import XCTest
@testable import QuiteNote

/// FolderTreeRenderer：目录树行生成（缩进 / 排序 / fileCount）。
/// 逻辑从 RecordStore.generateTreeStructure 逐字搬运，这里把现状行为钉住
final class FolderTreeRendererTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-folder-tree-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    private func makeDirectory(named name: String, files: [String], subdirectories: [String: [String]] = [:]) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files {
            try Data("x".utf8).write(to: url.appendingPathComponent(file))
        }
        for (sub, subFiles) in subdirectories {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
            for file in subFiles {
                try Data("x".utf8).write(to: url.appendingPathComponent(sub).appendingPathComponent(file))
            }
        }
        return url
    }

    func testRendersDirectoriesFirstThenFilesWithExactIndentation() throws {
        let root = try makeDirectory(
            named: "root",
            files: ["c.txt", ".hidden.txt"],   // 隐藏文件不进树
            subdirectories: [
                "empty": [],
                "subdir": ["b.md", "a.txt"],
            ]
        )

        let rendered = FolderTreeRenderer.renderLines(for: root)

        // 文件夹排前且按名排序（empty < subdir），文件在后；子层行 = 父连接线 + 子层缩进（现状的叠加样式）
        XCTAssertEqual(rendered.lines, [
            "文件夹路径: \(root.path)",
            "文件夹名: root",
            "文件结构:",
            ".",
            "├── empty/",
            "├── subdir/",
            "│   │  ├── a.txt",
            "│   │  └── b.md",
            "└── c.txt",
        ])
        XCTAssertEqual(rendered.fileCount, 3, "fileCount 只数文件，空目录不计")
    }

    func testRendersNestedSubdirectories() throws {
        let root = try makeDirectory(
            named: "nested",
            files: ["top.txt"],
            subdirectories: ["dirA": ["inner.txt"]]
        )

        let rendered = FolderTreeRenderer.renderLines(for: root)

        XCTAssertEqual(rendered.lines.suffix(3), [
            "├── dirA/",
            "│   │  └── inner.txt",
            "└── top.txt",
        ])
        XCTAssertEqual(rendered.fileCount, 2)
    }

    func testEmptyFolderRendersJustTheHeader() throws {
        let root = try makeDirectory(named: "void", files: [])

        let rendered = FolderTreeRenderer.renderLines(for: root)

        XCTAssertEqual(rendered.lines, [
            "文件夹路径: \(root.path)",
            "文件夹名: void",
            "文件结构:",
            ".",
        ])
        XCTAssertEqual(rendered.fileCount, 0)
    }
}
