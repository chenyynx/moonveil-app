#!/usr/bin/env python3
"""Full static audit of the remote-line surface (B-plan, single module).
Goal: expose ALL remaining first-compile-class debts in one pass instead of
one CI round per surprise. Three checks:
 A) iOS18/26-only APIs used bare (no #available) in app-side ported files.
 B) cross-file construction of structs whose private stored props demote the
    memberwise init (the ServiceEntryView class of bug).
 C) capitalized identifiers referenced from ported files that are declared
    NOWHERE in the repo and are not known system types (the OAuthCallback /
    AppSymbolAssets class of bug).
"""
import re, os, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTED = []
for d in ("src/ios/Views/AuthAA", "src/ios/Views/SettingsSkin", "src/ios/Views/ModeTabs"):
    PORTED += [p for p in glob.glob(os.path.join(ROOT, d, "*.swift"))]
GLUE = glob.glob(os.path.join(ROOT, "Packages/RemoteKit/Sources/Glue/*.swift"))
RK = glob.glob(os.path.join(ROOT, "Packages/RemoteKit/Sources/AAV2/**/*.swift"), recursive=True)
ALL_APP = glob.glob(os.path.join(ROOT, "src/ios/**/*.swift"), recursive=True)

# ---------- A) availability audit ----------
RISKY = {
    r"glassEffect\s*\(": "iOS26", r"\.glass\b": "iOS26 glassStyle", r"Button\s*\(\s*role:": "iOS26",
    r"\.controlSize\s*\(\.extraExtraLarge": "iOS18", r"presentationBackground": "iOS16.4-OK",
    r"\.scrollTargetLayout": "iOS17-OK", r"symbolRenderingMode\(\.monochrome\)": "OK",
    r"\.containerBackground": "iOS17-OK", r"navigationZoomTransition": "iOS26",
    r"\.scrollClipDisabled": "iOS17-OK", r"contentMargins\s*\(": "iOS17-OK",
    r"NavigationLabel": "iOS26", r"\.navigationPointStyle": "iOS26",
    r"@Bindable": "iOS17-OK", r"\.fontDesign": "iOS16.4-OK", r"textSelection": "iOS18?",
    r"\.glassProminent": "iOS26", r"buttonStyle\(\.glass": "iOS26",
}
def strip_code(t):
    t = re.sub(r"//.*", "", t)
    return t
def check_available(lines):
    """set of line numbers covered by an #available(iOS 26 (or 18) block or @available attr"""
    guarded = set()
    stack = []
    for i, l in enumerate(lines):
        m = re.search(r"#available\((?:iOS|macOS)\s+(\d+)", l)
        if m and "{" in l:
            stack.append((int(m.group(1)), i))
        if "{" in l or "}" in l:
            while stack and False: pass
        if "}" in l and stack:
            stack.pop() if l.count("}") >= l.count("{") else None
        if any(".glass" in l or "glassEffect" in l or "Button(role" in l for _ in [0]):
            pass
    return guarded
print("== A) risky-API sites (manual guard check below):")
for p in PORTED + GLUE:
    t = strip_code(open(p).read())
    for pat, tag in RISKY.items():
        if not tag.startswith("iOS26"): continue
        for m in re.finditer(pat, t):
            ln = t[:m.start()].count("\n") + 1
            lines = open(p).read().splitlines()
            ctx = "\n".join(lines[max(0,ln-8):ln+1])
            if "#available" not in ctx:
                print(f"  UNGUARDED {tag}: {p.replace(ROOT+'/','')}:{ln}: {lines[ln-1].strip()[:90]}")

# ---------- B) memberwise-init hazard ----------
print("== B) structs with private non-@State stored props constructed cross-file:")
declared = {}
for p in PORTED + GLUE + RK:
    for m in re.finditer(r"^(?:public |internal )?(?:struct|final class|class) (\w+)[^\n{]*\{", open(p).read(), re.M):
        declared.setdefault(m.group(1), []).append(p)
for name, files in declared.items():
    for p in files:
        s = open(p).read()
        m = re.search(r"(?:struct|class) " + name + r"[^\n{]*\{", s)
        if not m: continue
        body_start = s.index("{", m.start())
        depth = 0; body_end = body_start
        for i in range(body_start, len(s)):
            if s[i] == "{": depth += 1
            elif s[i] == "}":
                depth -= 1
                if depth == 0: body_end = i; break
        body = s[body_start:body_end]
        if re.search(r"^\s*init\s*\(", body, re.M): continue  # explicit init exists
        privs = re.findall(r"^\s*private\s+(?!static|let _)[\w<>?, ]+\s+(\w+)\s*(?::|=)", body, re.M)
        privs = [v for v in privs if not re.match(r"^_", v)]
        if not privs: continue
        # constructed outside its own file?
        for q in PORTED + GLUE + ALL_APP:
            if q == p: continue
            for mm in re.finditer(name + r"\s*\(", open(q).read()):
                print(f"  HAZARD {name}: private props {privs[:3]} constructed at {q.replace(ROOT+'/','')}")
                break

# ---------- C) undefined capitalized refs ----------
print("== C) capitalized refs in ported files missing from repo decls:")
decl = set()
for p in ALL_APP + GLUE + RK:
    s2 = open(p, encoding="utf-8", errors="ignore").read()
    for m2 in re.finditer(r"^(?:@\w+\s+)*(?:public |internal |private |fileprivate |final |nonisolated |actor |remote )*?(?:class|struct|enum|protocol|actor|extension|func|typealias)\s+([A-Z]\w*)", s2, re.M):
        decl.add(m2.group(1))
    for m2 in re.finditer(r"typealias\s+(\w+)", s2):
        decl.add(m2.group(1))
KNOWN_SYS = set("""URL URLSession URLRequest HTTPURLResponse Data String Int Double Bool Date UUID Error LocalizedError Notification
NSObject UIDevice UIApplication UIImage UIColor UIFont UIView UIViewController UIHostingController UIWindow UIWindowScene UIScreen
CGContext CGImage CGRect CGFloat CGPoint CGSize CIFilter CIImage CoreImage CIContext CoreGraphics CTLine CTRun CATransaction
CALayer CGPoint CGSize Image Text VStack HStack ZStack Button TextField SecureField Toggle Picker ScrollView List Form Section
NavigationStack NavigationLink NavigationPath GeometryReader GeometryGroup Color Font LinearGradient AnyView EmptyView Group Label
LabeledContent Menu ControlGroup PresentationalChanger Task TaskGroup Timer Thread DispatchQueue OperationQueue IndexSet
NotificationCenter Bundle UserDefaults Result Optional Never some StaticString Mirror Codable Decodable Encodable JSONEncoder
JSONDecoder URLSessionConfiguration URLComponents URLQueryItem CharacterSet ProcessInfo Locale Calendar TimeInterval
URLSessionTask HTTPCookieStorage CGColorSpace UIGraphicsImageRenderer UIPasteboard UIFeedbackGenerator UIFeedbackHaptics
UIImagePickerController AVCaptureSession AVCaptureDevice AVCaptureVideoPreviewLayer AVMediaType AVFoundation
ASWebAuthenticationSession ASWebAuthenticationPresentationContextProviding AuthenticationServices CryptoKit SHA256 PKCE
Keychain SecItem Security CGPath UIBezierPath UIEdgeInsets UIEdgeInsetsTopLayoutGuideAnchorPoint
CGRectInset CGFloat uicolor UIKit SwiftUI Foundation Combine ObservableObject StateObject State Published Binding Environment
EnvironmentObject App Scene WindowGroup UISceneSceneDelegateSupport UIApplicationSceneManifest""".split())
def known(w):
    if w in KNOWN_SYS: return True
    for pre in ("UI","NS","CG","CI","AV","MTK","MK","CA","WK","PK","SCN","CN","EK","HN","SF","MF","EK","CK","IN","PH","RV","AR","CoreImage","PDF","Sec","AS","CT","CF","CV","MK"):
        if w.startswith(pre): return True
    return False
for p in PORTED + GLUE:
    t = strip_code(open(p).read())
    for w in set(re.findall(r"\b([A-Z][A-Za-z0-9]{3,})\b", t)):
        if w in decl or known(w): continue
        # not a member call target like .foo or Type.static; crude: skip if preceded by .
        ln = None
        for i,l in enumerate(open(p).read().splitlines()):
            if re.search(r"(?<![\.\w])" + w + r"\b", strip_code(l) if l.strip().startswith("//")==False else ""):
                ln = i+1; break
        print(f"  UNRESOLVED {w}: {p.replace(ROOT+'/','')} first~:{ln}")
