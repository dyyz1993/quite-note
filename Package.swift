// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuiteNote",
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
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/QuiteNote",
            resources: [
                .process("UI/Screenshot/COORDINATE_SYSTEM.md"),
                .process("UI/Screenshot/THREE_PHASE_ARCHITECTURE.md"),
                .process("Info-debug.plist"),
                .process("Resources/Symbols/default.yaml")
            ]
        )
    ]
)
