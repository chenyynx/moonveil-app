// swift-tools-version:6.0
import PackageDescription

// Moonveil RemoteKit — isolated SwiftPM package (D4 门1: App→RemoteKit one-way).
// Sources/AAV2/ = official AA iOS V2 layer (MIT, verbatim port; see AAV2/AA-ATTRIBUTION.md).
// Sources/Glue/ = our only seam work (SessionBackend binding + D1 sqlite adapter + D2 out-seam).
// NOTE: Sources/AAV2 is a FROZEN ZONE with no target declared yet — its seeds transitively
// reference AA's monolithic app module (144-file closure incl. SwiftUI views). It becomes a
// target per Glue wiring batch once a compilable sub-closure lands; freeze integrity is
// enforced by scripts/aav2-freeze-check.sh (CI gate), not by compilation.
let package = Package(
    name: "RemoteKit",
    platforms: [.iOS(.v18)],
    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],
    targets: [
        .target(name: "RemoteKit", dependencies: [], path: "Sources/Glue"),
    ]
)
