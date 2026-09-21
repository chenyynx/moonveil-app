#!/usr/bin/env python3
"""Whole-module typecheck replay: turn "one error per CI cycle" into "every error
in one cycle".

Why this exists. xcodebuild with SWIFT_COMPILATION_MODE=incremental plus
-Xfrontend -disable-batch-mode compiles the app target one file per frontend job
and the CompileSwift task fails as soon as the first job errors. Every remaining
file is then never type-checked, so a 15-minute mac run reveals exactly the next
dependency layer. Moonveil burned 14 consecutive red runs that way.

Fix: reuse the invocation Xcode ALREADY logged for the app target (it carries the
real -sdk, -target, -import-objc-header, framework and module-search paths, and a
@FileList response naming every source file) and replay it as a single
-typecheck. Whole-module typecheck emits no object code, so it skips IRGen --
the memory phase that made a real WMO build die on these runners -- while still
resolving all cross-file type context, which a per-file pass cannot.

Safety contract: this is INFORMATIONAL. The step that runs it is
`continue-on-error: true`, and this script never exits nonzero on compile errors
(it reports them). It exits nonzero only when it could not run the pass at all,
and it always prints whether the surface it reported is complete or truncated,
so a partial answer can never be read as a clean one.

Usage: swift-full-typecheck.py [--log PATH] [--out PATH] [--module NAME] [--timeout SEC]
"""

import argparse
import os
import re
import shlex
import subprocess
import sys

# Flags that make the original invocation an CODE-EMITTING compile. Under
# -typecheck they are either meaningless or actively conflicting (the driver
# rejects -typecheck combined with -c/-o/-emit-module). -Xfrontend pairs are
# deliberately preserved: -disable-batch-mode is harmless there and dropping
# only the value would leave -Xfrontend glued to the following argument.
DROP_EXACT = {"-c", "-no-color-diagnostics", "-wmo", "-enable-batch-mode",
              "-save-optimization-record", "-incremental", "-Onone", "-O", "-Osize",
              "-g", "-profile-generate", "-profile-coverage-mapping",
              "-emit-dependencies", "-emit-localized-strings", "-emit-objc-header",
              "-emit-const-values", "-experimental-emit-module-separately",
              # -emit-module / -emit-symbol-map are BOOLEAN in the driver (the
              # logged shape is `-emit-module -emit-module-path <p>`). Listing
              # them as value-taking makes them eat the following real flag and
              # orphans <p> as a positional input -> "unexpected input file".
              "-emit-module", "-emit-symbol-map"}
DROP_WITH_VALUE = {"-o", "-emit-module-path", "-emit-dependencies-path",
                   "-emit-reference-dependencies-path", "-emit-localized-strings-path",
                   "-output-file-map", "-index-store-path", "-module-cache-path",
                   "-num-threads", "-j",
                   "-save-optimization-record-path", "-target-variant", "-vfsoverlay",
                   "-serialize-diagnostics-path", "-embed-bitcode-marker-files",
                   "-enable-testable-code-for-profile", "-profile-generate-lines-coverage",
                   "-emit-objc-header-path", "-emit-module-interface-path",
                   "-const-gather-protocols-file"}
# Frontend-only flags safe to drop as a -Xfrontend <flag> pair.
# -disable-batch-mode is dropped ON PURPOSE: the logged build uses it to make a
# real codegen failure visible per file, but here we want the opposite shape --
# one frontend pass over the whole file list, batching allowed, so the run both
# survives the memory pressure (WMO on this codebase has OOM-killed runners) and
# reports across batches instead of dying with the first file.
DROP_XFRONTEND = {"-serialize-debugging-options", "-disable-batch-mode"}
# Whole groups to remove, matched as exact token runs (the const-gather trio asks
# for its path through a second -Xfrontend, so it cannot be caught by the
# single-flag rules above).
# Token substrings whose whole -Xfrontend group must go away. The logged shape is
# `-Xfrontend -const-gather-protocols-file -Xfrontend <path>`, i.e. the flag's own
# path arrives through a SECOND -Xfrontend, so single-flag rules cannot reach it.
DROP_RUNS = ("const-gather-protocols-file", "const_extract_protocols")


def split_driver_prefix(argv):
    """xcodebuild logs the compile task as `builtin-SwiftDriver -- <swiftc> ...`.
    Only the real toolchain binary onward is executable, so cut the prefix."""
    for i, a in enumerate(argv):
        if a.endswith("/swiftc") or a.endswith("/swift-frontend"):
            return argv[i:]
    return argv[1:] if argv[:1] == ["builtin-SwiftDriver"] else argv


def to_typecheck_argv(argv):
    """Rebuild the logged codegen invocation as a pure -typecheck invocation.

    Pair-aware on purpose: a token that directly follows -Xfrontend belongs to the
    frontend and must be dropped or kept together with it, otherwise an orphaned
    -Xfrontend silently swallows the next unrelated flag.
    """
    argv = split_driver_prefix(argv)
    out = []
    i = 0
    prev_was_xfrontend = False
    while i < len(argv):
        a = argv[i]
        base = os.path.basename(a)
        if a == "-Xfrontend" and i + 1 < len(argv) and any(t in argv[i + 1] for t in DROP_RUNS):
            i += 2
            if i + 1 < len(argv) and argv[i] == "-Xfrontend":
                i += 2
            prev_was_xfrontend = False
            continue
        if prev_was_xfrontend:
            out.append(a)
            prev_was_xfrontend = False
            i += 1
            continue
        if a == "-Xfrontend" and i + 1 < len(argv) and argv[i + 1] in DROP_XFRONTEND:
            i += 2
            continue
        if a in DROP_EXACT or base in DROP_EXACT:
            i += 1
            continue
        if a in DROP_WITH_VALUE or base in DROP_WITH_VALUE:
            i += 2
            continue
        if re.match(r"^-(emit-module-path|output-file-map|index-store-path|"
                    r"emit-objc-header-path)=", a):
            i += 1
            continue
        out.append(a)
        prev_was_xfrontend = (a == "-Xfrontend")
        i += 1
    out.append("-typecheck")
    return out


def find_app_invocation(log_lines, module):
    """Return the argv of the app target's swiftc compile, last occurrence."""
    best = None
    for line in log_lines:
        if "swiftc" not in line:
            continue
        if f"-module-name {module} " not in line + " ":
            continue
        if "SwiftFileList" not in line:
            continue
        if "-import-objc-header" not in line:
            continue
        best = line
    if best is None:
        return None
    # The log escapes shell-special chars (e.g. -enforce-exclusivity\=checked);
    # shlex handles both the escaped and the plain form.
    return shlex.split(best.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default="/tmp/ios-build.log")
    ap.add_argument("--out", default="/tmp/full-typecheck.log")
    ap.add_argument("--module", default="Minis")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--dry-run", action="store_true",
                    help="parse + transform + print the replayed argv, do not exec "
                         "(lets the extraction be unit-checked on a non-Apple box)")
    args = ap.parse_args()

    if sys.platform != "darwin" and not args.dry_run:
        print("[full-typecheck] SKIP: needs an Apple SDK (macOS runner only)")
        return 0
    try:
        with open(args.log, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError as exc:
        print(f"[full-typecheck] FATAL cannot read build log: {exc}")
        return 2

    argv = find_app_invocation(lines, args.module)
    if argv is None:
        print(f"[full-typecheck] FATAL no `-module-name {args.module}` compile "
              f"invocation with @SwiftFileList found in {args.log} — the app target "
              f"never reached the Swift compile phase, so there is nothing to replay.")
        return 3

    tc = to_typecheck_argv(argv)
    print(f"[full-typecheck] replaying app-target invocation as whole-module -typecheck "
          f"({len(tc)} argv entries)")
    print(f"[full-typecheck] filelist: "
          f"{next((a for a in tc if 'SwiftFileList' in a), '?')}")

    if args.dry_run:
        print(f"[full-typecheck] DRY-RUN executable: {tc[0]}")
        print(f"[full-typecheck] DRY-RUN argv[1:] ({len(tc) - 1} entries):")
        for a in tc[1:]:
            print(f"  {a}")
        bad = [a for a in tc if a in DROP_EXACT or a in DROP_WITH_VALUE]
        print(f"[full-typecheck] DRY-RUN leaked codegen flags: {bad or 'none'}")
        # -Xfrontend legitimately appears an odd number of times (the
        # const-gather trio passes its path via a second -Xfrontend), so parity
        # is not the invariant -- a dangling one at the tail is.
        print(f"[full-typecheck] DRY-RUN tail: {tc[-2:]}")
        print(f"[full-typecheck] DRY-RUN dangling -Xfrontend: "
              f"{'YES' if tc[-1] == '-Xfrontend' else 'no'}")
        return 0

    try:
        proc = subprocess.run(tc, capture_output=True, text=True, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f"[full-typecheck] INCOMPLETE: killed after {args.timeout}s. "
              f"The surface below (if any) is TRUNCATED, do not read it as clean.")
        return 0
    except OSError as exc:
        print(f"[full-typecheck] FATAL could not exec: {exc}")
        return 4

    diag = (proc.stdout or "") + (proc.stderr or "")
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(diag)

    errors, notes = [], 0
    for line in diag.splitlines():
        if ": error:" in line:
            errors.append(re.sub(r"^/Users/runner/work/[^ ]*/", "", line.strip()))
        if "no such module" in line or "could not build module" in line:
            notes += 1

    uniq = sorted(set(errors))
    # exit 0 + no errors => genuinely clean. nonzero with errors => complete
    # surface (whole-module typecheck does not stop at the first file).
    # Missing-module notes mean dependencies were not built: report is partial.
    if notes:
        verdict = (f"PARTIAL — {notes} missing/unbuilt-module diagnostics present, so "
                   f"downstream errors may be masked")
    elif proc.returncode == 0 and not uniq:
        verdict = "COMPLETE and CLEAN"
    elif not uniq:
        # Nonzero exit with zero error lines is the silent-death signature this
        # repo already knows (Xcode 26.6 OOM). Never report that as clean.
        verdict = (f"INCONCLUSIVE — frontend exited {proc.returncode} without a single "
                   f"error line (silent death / OOM suspected). Surface is UNKNOWN, "
                   f"not clean. Last lines: {diag.strip().splitlines()[-3:]}")
    else:
        verdict = f"COMPLETE ({len(uniq)} unique errors) — whole-module pass ran to end"

    print(f"[full-typecheck] {verdict}")
    for e in uniq[:80]:
        print(f"  {e}")
        print(f"::error::full-typecheck {e[:700]}")
    if len(uniq) > 80:
        print(f"[full-typecheck] ... {len(uniq) - 80} more unique errors in {args.out}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(f"\n### Whole-module typecheck (complete error surface)\n\n")
            fh.write(f"Verdict: **{verdict}**\n\n```\n")
            fh.write("\n".join(uniq[:120]) or "(no errors)")
            fh.write("\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
