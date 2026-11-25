// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PaperGlideCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PaperGlideCore", targets: ["PaperGlideCore"])
    ],
    targets: [
        .target(name: "PaperGlideCore"),
        .executableTarget(
            name: "GenerateGoldenFixtures",
            dependencies: ["PaperGlideCore"]
        ),
        .testTarget(
            name: "PaperGlideCoreTests",
            dependencies: ["PaperGlideCore"]
        )
    ]
)
