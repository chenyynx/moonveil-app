// swift-tools-version:6.0
import PackageDescription

// Moonveil RemoteKit — isolated SwiftPM package (D4 门1: App→RemoteKit one-way).
// Sources/AAV2/ = official AA iOS V2 layer (MIT, verbatim port; AAV2/AA-ATTRIBUTION.md).
//   The `sources:` whitelist IS the wiring ledger: a frozen file compiles only once its
//   dependency closure is proven. Files in the dir but off the list = ported, not wired.
// Sources/Glue/ = our only seam work (SessionBackend binding + D1 sqlite adapter + D2 out-seam).
// Freeze integrity: scripts/aav2-freeze-check.sh (CI gate), independent of compilation.
let package = Package(
    name: "RemoteKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],
    // Language mode pinned to Swift 5 = upstream's SWIFT_VERSION (5.0 in the
    // v2.0.0 Xcode project, verified 2026-09-15). The frozen AAV2 code leans on
    // Swift-5 warning-level actor isolation (HTTPReadRetryPolicy.permitsRetry is
    // @MainActor, called from a nonisolated retry loop; HTTPTransport.swift:56).
    // tools-version 6.0 defaults every target to Swift 6 mode, which hard-errors
    // the verbatim official sources — align the build config, freeze zone untouched.
    targets: [
        .target(name: "RemoteKit", dependencies: ["AAV2"], path: "Sources/Glue",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "AAV2",
            dependencies: [],
            path: "Sources/AAV2",
            sources: [
                // batch2 (2026-09-15): Domain leaf closure + error family + StableViewModel
                "Domain/Common",
                "Domain/Session",
                "Domain/Runtime",
                "Domain/Connector",
                "Domain/Realtime",
                "Domain/Attachment",
                "Network",
                "Business",
                // batch3 (2026-09-15): API/V2 transport-facing layer + WS client
                // (closure of V2APIClient composition root; no UI deps — verified)
                "API/V2",
                "Domain/Account",
                "Models/APIModels.swift",
                "Models/WorkspaceDownloadedFile.swift",
                "Views/Components/StableViewModel.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
