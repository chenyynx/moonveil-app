# Upstream modification ledger — src/ios vs OpenMinis 4ef2900

Every Moonveil edit to otherwise-verbatim upstream iOS files, in one place, for
merge/rebase audit (`git diff 4ef2900 -- src/ios` is the mechanical companion).
RemoteKit internals are ledgered separately (Packages/RemoteKit/Sources/AAV2/AA-ATTRIBUTION.md).

## SL1 — Sideload App Group fallback (3 sites, 2026-09-15)
- Files: `Agent/Chat/AIChatViewModel+RequestBudget.swift` (`minisAppGroupRoot`,
  `minisConfigRoot`), `MinisApp.swift` (`migrateSharedDirToAppGroup`).
- Why: KSign/enterprise re-signed builds get NO App Group container; upstream force
  unwraps `containerURL(...)!` → SIGTRAP at launch (crash report Minis-2026-09-15-085415.ips).
- Fix: if-let/guard with Application Support fallback — the exact workaround claudio
  ships field-verified. Container-present behavior: byte-identical to upstream (no branch runs).
- Known sideload-form consequence: FileProvider extension sync degrades (extension keeps
  upstream `providerRoot!` per claudio parity); user-visible sharing needs a signed form
  with entitlements. Decided 2026-09-15 (pp: 对齐 claudio 实证形态).

## BR1 — Bundle identity rename `com.openminis` → `com.moonveil` (49 files, 2026-09-15)
- pbxproj (main + 3 appex bundle ids), entitlements/plists (App Group, iCloud container,
  NSUserActivityTypes, BGTask ids), swift refs (app group id, FileProvider domains,
  keychain services, os_log subsystem, notification names). 101+/101- pure rename.
- URL schemes (minis://) untouched.

## BR2 — Launch screen brand text → "Moonveil" (`Launch Screen.storyboard`)
- Main title only; subtitle kept. (Interim "月纱" commit f47425f superseded per pp: use English name.)

## BR3 — App icon → AA official iconset (2 files, `Assets.xcassets/AppIcon.appiconset/`)
- light slot ← v2.0.0 `logo/ios-dark-iOS-Default-1024@1x.png`, dark slot ← appiconset
  `ios-dark-iOS-Dark-1024@1x.png` (verbatim from moonveil-cloud tag v2.0.0).
- Brand-artwork licensing: upstream README「图片来源与复现方式」— re-decide at open gate.
