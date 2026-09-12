// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuiteNote",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuiteNote", targets: ["QuiteNote"])
    ],
    dependencies: [
        // Lucide-Swift 图标库
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift", from: "0.556.0"),
        // Yams YAML 解析库
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "QuiteNote",
            dependencies: [
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
        .testTarget(
            name: "QuiteNoteTests",
            dependencies: ["QuiteNote"],
            path: "Tests/QuiteNoteTests"
        )
    ]
)
