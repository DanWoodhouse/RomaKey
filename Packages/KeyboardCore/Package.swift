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
                // Emoji names and keywords from Emojibase (MIT). Rebuild with tools/build_emoji.py.
                .copy("Resources/emoji.tsv"),
                .copy("Resources/emojibase-LICENSE"),
                // English word pairs for predictive text, from SymSpell's bigram list (MIT), built
                // from Google Books Ngrams (CC BY 3.0). Rebuild with tools/build_bigrams.py.
                .copy("Resources/bigrams.tsv"),
            ]
        ),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
