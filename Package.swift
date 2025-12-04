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
    targets: [
        .executableTarget(
            name: "QuiteNote",
            path: "Sources/QuiteNote"
        )
    ]
)

