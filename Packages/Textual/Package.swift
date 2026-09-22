// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "textual",
  platforms: [
    .macOS(.v15),
    .iOS(.v17), // B9-FIX2 (2026-09-22): .v18→.v17 — app target floor is 17.0 (DEP-17, pp-owned); no iOS-18-gated API in Sources (only @available(iOS 26) ×1). Same lever as RemoteKit's v17 floor (30cdd24). tvOS/watchOS/visionOS untouched: not integrated.
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  products: [
    .library(name: "Textual", targets: ["Textual"])
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.1"),
    .package(url: "https://github.com/gonzalezreal/swiftui-math", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "Textual",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SwiftUIMath", package: "swiftui-math"),
      ],
      resources: [
        .process("Internal/Highlighter/Prism"),
        .copy("PrivacyInfo.xcprivacy"),
      ],
      swiftSettings: [
        .define(
          "TEXTUAL_ENABLE_LINKS",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .watchOS, .visionOS])),
        .define(
          "TEXTUAL_ENABLE_TEXT_SELECTION",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
      ]
    ),
    .testTarget(
      name: "TextualSelectionTests",
      dependencies: ["Textual"],
      swiftSettings: [.define("TEXTUAL_ENABLE_TEXT_SELECTION")]
    ),
  ]
)
