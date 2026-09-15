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
    targets: [
        .target(name: "RemoteKit", dependencies: ["AAV2"], path: "Sources/Glue"),
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
                "Views/Components/StableViewModel.swift",
            ]
        ),
    ]
)
