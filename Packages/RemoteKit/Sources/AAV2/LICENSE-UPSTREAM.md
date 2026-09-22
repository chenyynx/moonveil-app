# Upstream license note — AAV2 freeze zone

- Upstream repo: `anywhere-labs/Agents-Anywhere` (our mirror: chenyynx/moonveil-cloud).
  The AAV2 freeze zone is pinned at rev `1bc11f45`; it was **initially ported from tag
  `v2.0.0`** (anchor raised 2026-09-22, see `AA-ATTRIBUTION.md` for the provenance note).
- Upstream declares the project **MIT** in `README.md` section「开源许可」
  (badge `license-MIT` + text "MIT。"), verified 2026-09-15.
- The upstream repo contains **no root LICENSE file**; only third-party vendored subpackages
  carry their own (`dsh-bridge/LICENSE`, `ios/Packages/Textual/LICENSE`, …).
- Compliance stance for Moonveil: code copied from this source tree is redistributed under the
  upstream's declared MIT terms; attribution + link to the mirror repo are maintained in
  `AA-ATTRIBUTION.md`. If upstream ever ships a LICENSE text file, copy it here verbatim.
