// Glue — Moonveil's own seam layer ONLY (SessionBackend binding + D1 cache adapter +
// D2 out-seam projection). Nothing here is copied from upstream; nothing from upstream
// is edited. Official code lives in ../AAV2 (frozen, verbatim).
//
// Batch3 placeholders: real wiring lands per U1/D1/D2 plan (D4 门1 keeps this one-way:
// App -> RemoteKit, never App internals -> here or here -> App).
import AAV2

public enum RemoteKitVersion {
    /// Ledger marker for diagnostics; bumped per wiring batch.
    public static let current = "glue-0.1 (AAV2 domain wired, batch2)"
}
