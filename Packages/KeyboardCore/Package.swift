// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyboardCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            resources: [
                // Common words from JMdict (CC BY-SA, EDRDG). Rebuild with tools/build_dictionary.py.
                .copy("Resources/dictionary.tsv"),
                .copy("Resources/JMdict-LICENSE.md"),
            ]
        ),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
