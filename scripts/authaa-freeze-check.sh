#!/usr/bin/env bash
# Zone: AuthAA / SettingsSkin verbatim freeze. The 8 registered files under
# src/ios/Views/AuthAA and src/ios/Views/SettingsSkin that are verbatim copies of
# upstream Agents Anywhere must stay byte-identical to the pinned revision.
#
# Implementation lives in scripts/freeze-check.sh (shared with the AAV2 zone);
# this wrapper only pins FREEZE_ZONE and forwards the mode argument.
#
# These directories are only PARTIALLY frozen: the 8 verbatim files are registered
# in scripts/authaa-freeze-manifest.txt, the intentionally-skinned
# / no-upstream files are declared in scripts/authaa-skin-allowlist.txt (each entry
# carries its registration-time sha256 + an ASCII reason; stale sha or a list grown
# past its cap fails the gate). Any file on disk that is neither registered nor
# allow-listed fails the structure assertion.
#
# Modes: (none) full | --structure-only | --write-baseline. All fail-closed.
#   MV_CLOUD=/path/to/moonveil-cloud bash scripts/authaa-freeze-check.sh   # strong
FREEZE_ZONE=authaa exec "$(cd "$(dirname "$0")" && pwd)/freeze-check.sh" "$@"
