#!/usr/bin/env bash
# Zone: AAV2 verbatim freeze. Packages/RemoteKit/Sources/AAV2/**.swift must stay
# byte-identical to the pinned upstream Agents Anywhere revision.
#
# Implementation lives in scripts/freeze-check.sh (shared by every verbatim zone);
# this wrapper only pins FREEZE_ZONE and forwards the mode argument. Background and
# the two blind spots this gate closes are documented in that engine's header.
#
# Modes: (none) full | --structure-only | --write-baseline. All fail-closed.
#   MV_CLOUD=/path/to/moonveil-cloud bash scripts/aav2-freeze-check.sh   # strong
FREEZE_ZONE=aav2 exec "$(cd "$(dirname "$0")" && pwd)/freeze-check.sh" "$@"
