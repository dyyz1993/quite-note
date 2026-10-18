// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuiteNote",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "QuiteNoteSharedStorage", targets: ["QuiteNoteSharedStorage"]),
        .executable(name: "QuiteNote", targets: ["QuiteNote"]),
        .executable(name: "QuiteNoteCoreService", targets: ["QuiteNoteCoreService"])
    ],
    dependencies: [
        // Lucide-Swift 图标库
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift", from: "0.556.0"),
        // Yams YAML 解析库
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "QuiteNoteSharedStorage",
            path: "Sources/QuiteNoteSharedStorage"
        ),
        .executableTarget(
            name: "QuiteNote",
            dependencies: [
                "QuiteNoteSharedStorage",
                .product(name: "LucideIcons", package: "lucide-icons-swift"),
                .product(name: "Yams", package: "yams")
            ],
            path: "Sources/QuiteNote",
            exclude: [
                "UI/FloatingPanel/Untitled-2.ini",
                "UI/FloatingPanel/┌───────────────────────────────────────.ini",
                "UI/ScreenshotV2/DEBUG_WIREFRAME_ISSUE.md",
                "UI/ScreenshotV2/Docs",
                "UI/ScreenshotV2/LongScreenshot/Docs",
                "UI/ScreenshotV2/LongScreenshot/README.md",
                "UI/ScreenshotV2/Views/Overlays/YellowWireframe_ANALYSIS.md",
                "UI/ScreenshotV3"
            ],
            resources: [
                .process("Info-debug.plist"),
                .process("Resources/Localization"),
                .process("Resources/Symbols/default.yaml")
            ]
        ),
        .executableTarget(
            name: "QuiteNoteCoreService",
            dependencies: ["QuiteNoteSharedStorage"],
            path: "Sources/QuiteNoteCoreService"
        ),
        .testTarget(
            name: "QuiteNoteTests",
            dependencies: ["QuiteNote"],
            path: "Tests/QuiteNoteTests"
        ),
        .testTarget(
            name: "QuiteNoteCoreServiceTests",
            dependencies: ["QuiteNoteCoreService", "QuiteNoteSharedStorage"],
            path: "Tests/QuiteNoteCoreServiceTests"
        ),
        .testTarget(
            name: "QuiteNoteSharedStorageTests",
            dependencies: ["QuiteNoteSharedStorage"],
            path: "Tests/QuiteNoteSharedStorageTests"
        )
    ]
)
