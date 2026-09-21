#!/usr/bin/env python3
# Strict OpenStep-plist gate for project.pbxproj.
# openstep_parser AND the ruby xcodeproj/nanaimo gem both accept "key = value" lines
# missing their terminating ';' (proven on 8314d82's broken pbxproj: both rc=0).
# xcodebuild refuses to open such a project ("Unable to read project"). This checker
# implements the strict grammar (every dict entry MUST end with ';') with per-error
# recovery, so one run reports the full broken-line surface. Stdlib only.
import os, sys

DEFAULT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "src/ios/Minis.xcodeproj/project.pbxproj")
UNQUOTED_OK = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$/+*?@~^&%!:-")
STRUCT = "{}();,"

class Tok:
    __slots__ = ("kind", "val", "line", "col")
    def __init__(self, kind, val, line, col):
        self.kind, self.val, self.line, self.col = kind, val, line, col
    def __repr__(self):
        return f"{self.kind}:{self.val!r}@{self.line}:{self.col}"

def tokenize(text):
    toks, i, line, col, n = [], 0, 1, 1, len(text)
    def adv(steps):
        nonlocal i, line, col
        for ch in text[i:i+steps]:
            i += 1
            if ch == "\n":
                line += 1; col = 1
            else:
                col += 1
    while i < n:
        ch = text[i]
        if ch in " \t\r\n":
            adv(1); continue
        if text.startswith("/*", i):
            depth, start_line, start_col = 1, line, col
            adv(2)
            while i < n and depth:
                if text.startswith("*/", i):
                    depth -= 1; adv(2)
                elif text.startswith("/*", i):
                    depth += 1; adv(2)
                else:
                    adv(1)
            if depth:
                toks.append(Tok("error", "unterminated /* comment", start_line, start_col))
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                adv(1)
            continue
        if ch == '"' or ch == "'":
            quote, start_line, start_col = ch, line, col
            adv(1); buf = []
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    if i + 1 >= n:
                        break
                    buf.append(text[i+1]); adv(2)
                else:
                    if text[i] == "\n":
                        toks.append(Tok("error", "newline inside quoted string", start_line, start_col))
                        break
                    buf.append(text[i]); adv(1)
            if i < n and text[i] == quote:
                adv(1)
            else:
                toks.append(Tok("error", "unterminated quoted string", start_line, start_col))
            toks.append(Tok("str", "".join(buf), start_line, start_col))
            continue
        if ch == "<":
            start_line, start_col = line, col
            adv(1); buf = []
            while i < n and text[i] != ">":
                buf.append(text[i]); adv(1)
            if i < n:
                adv(1)
            else:
                toks.append(Tok("error", "unterminated <data>", start_line, start_col))
            toks.append(Tok("data", "".join(buf).strip().strip("<>"), start_line, start_col))
            continue
        if ch in STRUCT + "=":
            toks.append(Tok(ch, ch, line, col)); adv(1); continue
        # unquoted string
        start_line, start_col = line, col
        buf = []
        while i < n and text[i] not in " \t\r\n;={}(),\"'" and not text.startswith("/*", i):
            if text[i] not in UNQUOTED_OK and text[i] not in "\\\\":
                toks.append(Tok("error", f"illegal char {text[i]!r} in unquoted token", line, col))
            buf.append(text[i]); adv(1)
        if not buf:  # nothing consumed (defensive, keep loop progressing)
            adv(1); continue
        toks.append(Tok("str", "".join(buf), start_line, start_col))
    return toks

class Parser:
    def __init__(self, toks, path):
        self.toks, self.pos, self.path, self.errors = toks, 0, path, []
    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else None
    def next(self):
        t = self.peek()
        if t: self.pos += 1
        return t
    def err(self, t, msg):
        self.errors.append(f"{self.path}:{t.line}:{t.col}: error: {msg}")
    def skip_errors(self):
        while (t := self.peek()) and t.kind == "error":
            self.err(t, t.val); self.next()
    def parse_value(self):
        self.skip_errors()
        t = self.peek()
        if t is None:
            self.err(self.toks[-1], "unexpected EOF, expected value"); return None
        if t.kind == "{": self.next(); return self.parse_dict()
        if t.kind == "(": self.next(); return self.parse_array()
        if t.kind in ("str", "data"): self.next(); return t.val
        self.err(t, f"unexpected {t.kind!r}, expected value"); self.next(); return None
    def parse_dict(self):
        cur = {}
        while True:
            self.skip_errors()
            t = self.peek()
            if t is None:
                self.err(self.toks[-1], "unexpected EOF, expected '}'"); return cur
            if t.kind == "}": self.next(); return cur
            if t.kind != "str":
                self.err(t, f"unexpected {t.kind!r}, expected key or '}}'"); self.next(); continue
            key = t.val; self.next()
            self.skip_errors()
            t = self.peek()
            if t is None or t.kind != "=":
                self.err(t or self.toks[-1], f"expected '=' after key {key!r}")
                continue
            self.next()
            val = self.parse_value()
            cur[key] = val
            self.skip_errors()
            t = self.peek()
            if t is not None and t.kind == ";":
                self.next()
            else:
                where = t or self.toks[-1]
                self.err(where, f"missing ';' after value of key {key!r} (xcodebuild refuses to read such a project)")
    def parse_array(self):
        state = "start"  # "start": expect element or ')'; "elem": expect ',' or ')'
        while True:
            self.skip_errors()
            t = self.peek()
            if t is None:
                self.err(self.toks[-1], "unexpected EOF, expected ')'"); return
            if state == "start":
                if t.kind == ")": self.next(); return
                self.parse_value()
                state = "elem"
            else:
                if t.kind == ",": self.next(); state = "start"; continue
                if t.kind == ")": self.next(); return
                self.err(t, f"missing ',' between array elements (found {t.kind!r})")
                state = "start"  # recover: treat current token as next element

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    with open(path) as f:
        text = f.read()
    p = Parser(tokenize(text), path)
    top = p.parse_value()
    leftover = p.peek()
    if leftover is not None:
        p.err(leftover, f"trailing content {leftover.kind!r} after top-level value")
    structural = 0
    if not isinstance(top, dict):
        p.errors.append(f"{path}:1:1: error: top-level plist is not a dictionary")
    else:
        for req in ("archiveVersion", "objectVersion", "objects", "rootObject"):
            if req not in top:
                p.errors.append(f"{path}:1:1: error: missing required top-level key {req!r}")
                structural += 1
        objs = top.get("objects")
        if isinstance(objs, dict):
            for oid, o in objs.items():
                if not isinstance(o, dict) or "isa" not in o:
                    p.errors.append(f"{path}:1:1: error: objects[{oid}] is not an isa-dictionary")
                    structural += 1
            print(f"[strict-pbxproj] objects={len(objs)}")
    if p.errors:
        shown = p.errors[:100]
        for e in shown:
            print(e)
        if len(p.errors) > 100:
            print(f"... {len(p.errors)-100} more")
        print(f"[strict-pbxproj] FAIL: {len(p.errors)} error(s)")
        sys.exit(1)
    print(f"[strict-pbxproj] OK (strict OpenStep grammar)")
    sys.exit(0)

if __name__ == "__main__":
    main()
