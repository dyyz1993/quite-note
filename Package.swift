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
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift", from: "0.556.0")
    ],
    targets: [
        .executableTarget(
            name: "QuiteNote",
            dependencies: [
                .product(name: "LucideIcons", package: "lucide-icons-swift")
            ],
            path: "Sources/QuiteNote"
        )
    ]
)
