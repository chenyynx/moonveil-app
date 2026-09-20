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

## BR3 — App icon → AA official iconset (CORRECTED 2026-09-15 same day)
- First attempt wrongly mapped light/dark semantics: put the WHITE Default in the universal
  slot -> light-mode home screen showed white. pp caught it ("咋是白色的").
- Now verbatim AA recipe: Contents.json copied from v2.0.0 appiconset — universal slot =
  ios-dark-iOS-Dark-1024 (black), dark slot inherits, tinted slot = TintedLight; both pngs
  byte-verified vs tag. Upstream Icon-1024*.png restored from git (unreferenced).
- Brand-artwork licensing: upstream README「图片来源与复现方式」— re-decide at open gate.

## BR4 — Visible brand sweep Minis -> Moonveil (79 files, 419+/417-, 2026-09-15, pp directive)
- Changed: all user-visible strings (UI copy incl. lock screen/About/settings/notifications/
  Siri phrases/FileProvider labels), 9-language InfoPlist+AppShortcuts .strings, permission
  usage descriptions (Info.plist), extension display names (pbxproj), app display name =
  Moonveil, HTTP User-Agent (Minis/x -> Moonveil/x), log prefixes ([MinisImage]/[MinisScheme]/
  [MinisSymlink]...), debug identifiers (MinisSoulMdChanged, MinisDebugVoiceMicTap), cache key
  (MoonveilImageSizes_v1), share-sheet comment refs.
- KEPT with reason (non-visible or contract-bearing): data-path anchors (MinisChat/, MinisConfig,
  MinisFileProvider dirs, minis.db), iSH terminal escape protocol "MinisOpenURL=" (emitter+parser
  pair), HTTP header name X-Minis-OAuth-UUID (server contract), minis:// URL scheme (deep-link
  protocol), class/file/symbol names (MinisApp, AskMinisIntent...), symbolication example frame
  (binary image name IS Minis), github.com/OpenMinis attribution (GPL), MinisTests fixtures,
  one log string self-referencing a real function name.
- UserDefaults-key renames are behavior-neutral for our installs (no shipped user base yet).

## BR5 — deep-link protocol minis:// -> moonveil:// (84 files, 440+/440-, 2026-09-15, pp: "改")
- Changed (both platforms, emitter+parser together): every `minis://` literal (iOS swift 226 /
  Android kt 177), bare scheme comparisons `== "minis"`, WKURLSchemeHandler registration,
  browser scheme whitelists (iOS ChatURLBrokerage + Android MinisOpenUrlBroker), iOS
  Info.plist CFBundleURLSchemes `<string>minis</string>` -> moonveil, AndroidManifest
  `android:scheme="minis"`, xAI OAuth referrer value. Test DATA synced where it asserts the
  protocol (protocol tests must track the protocol or the gate lies).
- KEPT (with reason): data-path directory component `appendingPathComponent("minis")` and
  `MinisChat/minis` paths (storage anchors — 7 bare-literal over-matches caught by post-sweep
  and reverted: ChatStore x2, ICloudBackupManager x3, DebugJSONRPC skills.db path, voice-
  correction pronunciation samples x5 "linux"/"minis" pairs — test meaning depends on those
  exact spellings), iSH escape token MinisOpenURL= (IPC pair; its PAYLOAD value is now
  moonveil:// — token name unchanged), minis-mcp/minis-config/minis-model-use tool names
  (counterpart lives in iSH CLI toolchain — renaming text without the binary = false claim),
  minis.db filename, X-Minis header, class/symbol names, OpenMinis attribution.
- Fresh install data domain: no legacy moonveil-side links to serve; no compat shim registered
  (moonveil is brand-new bundle id; old minis:// history lives in OTHER apps' domains).

## BR6 — scope A per pp (X-Minis header + MCP tool-name family, 2026-09-15)
- X-Minis-OAuth-UUID -> X-Moonveil-OAuth-UUID (write/read/strip all inside OAuthHTTPClient — self-contained, earlier "server contract" label was wrong: it never leaves the app).
- MCP servers renamed end to end: minis-config -> moonveil-config, minis-model-use -> moonveil-model-use, minis-mcp-cli -> moonveil-mcp-cli (tool scripts git-mv'd at bin+lib on BOTH platforms; daemon IPC files /tmp/moonveil-mcp-daemon.{pid,port,lock} synced with bin references; system prompt text + 52 Android locale strings + all code refs updated).
- BR5 straggler completion: default_mount sandbox minis:// -> moonveil:// (model-facing docs inside the sandbox teach the protocol — missing them would make the model emit dead links).
- Ledger note: earlier BR5 KEPT said tool counterpart "not in repo" — wrong, corrected by evidence (lives in src/*/default_mount). Ledger entries are never rewritten; corrections land as new sections.
- OUT of scope A (kept): minis-open + MinisOpenURL escape token (scope B), class/symbol names, /var/minis + MinisChat/minis data paths, minis.db, Android applicationId com.openminis.app (BR1 was iOS-only — flagged for pp), minis.sh.

## BR7 — file-name & IPC-token families (pp: "这些不能改？" -> all in, class names stay, 2026-09-15)
- Log filenames: minis-YYYY-MM-DD.log -> moonveil-... (generation + hasPrefix + dropFirst, same file, paired).
- Backup package extension family: .minisbak -> .moonveilbak incl. Info.plist UTType id + journal
  prefix minisbak- -> moonveilbak- + 76 locale strings (android xml + ios strings) + tests.
- Sandbox tool minis-open -> moonveil-open (git mv both platforms; 6 browser-alias scripts
  xdg-open/gnome-open/... forward to it, updated).
- Escape token MinisOpenURL= -> MoonveilOpenURL= (emitters in bin scripts + parsers:
  TerminalEmulator/ChatURLBrokerage iOS, MinisOpenUrlBroker.kt Android) — token string only,
  CLASS NAMES KEPT (MinisOpenURLBroker x26 refs): user-invisible, renaming = upstream merge debt.
- BROWSER=/usr/local/bin/... env injection in ISHShellExecutor.m + ISHKernel.m: functional fix —
  missed in first pass (extension .m outside sweep), would have killed terminal browser links.
- minis-mcp plist registration + comment -> moonveil-mcp (dead legacy; real default redirect is
  http://localhost loopback per MCPOAuthController.defaultRedirectURI).
- PROCESS LESSON (two false-green sweeps caught in-repo): verification sweep MUST cover >= the
  replacement corpus — extension-whitelisted greps initially "proved zero" while no-ext bin
  scripts and .m files still held the old tokens (emitter/parser briefly DISJOINT = live bug
  state before full re-sweep). Authoritative final sweep: no extension filter at all.
- Backup-format compatibility ruling (review R2): moonveil REJECTS foreign .minisbak packages
  (claudio/official exports) — consistent with upstream S3 review intent (foreign prefix must
  refuse) and zero legacy in moonveil's own data domain (never shipped). Not a regression;
  recorded as product boundary. Android log family (4 sites: AppLogger generation,
  CrashFrequencyDetector + LogManagementScreen consumers, doc comment) synced in same batch.

## BR7b — Localizable.xcstrings pairing repair (review-round finding, 2026-09-15)
BR4 renamed code-side call-site literals but NOT the String Catalog keys (key == English
prose == call-site string): 70 keys + 612 localized values renamed now; 30 code files
with in-quote \bMinis\b filled. Power check: Moonveil call-sites missing from catalog = 0;
catalog sweep CLEAN. LESSON (ledgered): string-catalog renames are TWO-SIDED — key + every
value + call-site must move together or translations silently vanish.
## BR8-HELD — Android brand surface (pp: 安卓暂不动, 2026-09-15)
~1100 live lines (app_name=Minis across locales, manifest labels/comments, Theme.Minis,
prompt "Minis settings" android twin) + applicationId com.openminis.app — FROZEN pending
pp go. iOS-side zero-tolerated stragglers (prompt 1937/1965 area) were fixed under BR4/BR7b
scope (src/ios only), Android untouched by this whole BR series beyond scheme/protocol/MCP
naming already mandated by BR5/BR6 toolchain closure.

## MR-HELD — module name stays Minis (pp final call 2026-09-15: "算了 不改了 回退，只改用户可见的名字")
- Scope decision recorded: BRAND = user-visible surface ONLY (display name/launch screen/
  copy/notifications/UI strings — all Moonveil as of BR4-BR7). Build-system identity
  (PRODUCT_NAME/module name = Minis, scheme, target names, test imports) stays upstream.
- Reverted: 13 ObjC bridge-header imports `Moonveil-Swift.h` -> `Minis-Swift.h` (BR7b
  quoted-string sweep over-matched: -Swift.h filename is module-name-derived, NOT a brand
  string; this broke iOS Build at 491ce80 — caught by CI, reverted same day).
- LESSON (ledgered): before any quoted-string sweep, exclude build-system generated
  filenames ("<Module>-Swift.h", module maps, umbrella headers) — they LOOK like strings
  but are compiler contracts with the target's PRODUCT_MODULE_NAME.
## gitleaks allowlist extension (CI fix, same batch)
BackupCrypto.swift/.kt: generic-api-key hit on the ENCRYPTION FORMAT MAGIC (scheme/id
constant, identical on both platforms, sha 5bd3a1b4138e) — protocol discriminator, not a
key; both sites verified upstream-identical modulo our own brand rename. Rule-scoped
(generic-api-key only), paths exact, sentinel tamper-test still fails CI.

## FONTS-1 — factory default font scale → xSmall（2026-09-15，pp："先把字体改到默认最小"）

- `src/ios/Shared/FontSettings.swift`：新增 `factoryDefault = .xSmall`（最小档，0.88×）。
- init 改按 **键存在性**（`ud.object(forKey:)`）判"已配置"——`.default` rawValue=0 与"缺键"的 `integer(forKey:)` 返回值同形，纯值兜底永远救不到未配置安装。
- `isModified` / `resetToDefaults` 同锚 factoryDefault：重设按钮现在回到最小档而非上游 "Default"。
- 不动面：任何显式配置过的安装行为与上游逐字节一致；`applyAppScaleToAllWindows` 仍只在 `.default` 时跳过 trait 覆盖（xSmall 与用户手选时同样正常覆盖）。Android 侧未动（BR8-HELD），iOS only。

## B7-UI — sidebar title → source-mode capsule（2026-09-15，pp："胶囊放在列表顶部moonveil那个位置 两个tab分别是 Moonveil 和 Remote"）

- `ContentView.swift`：toolbar principal 的 `Text(soulName)` 换成 `ModeTabPicker`（首档=soulName 同源回退 Moonveil，次档 Remote）；sync 详情入口经 onLocalRetap 保留、指示器 overlay 保留、isSelecting 分支未动；两处崩溃文档注释重指向。
- 新目录 `Views/ModeTabs/`（4 文件）：ModeTabPicker（AA interactive-glass 配方+upstream 降级先例；触感=Grok 官方 Motion 规范：切换 .soft、拖滑越界 selection detent）/ RootTabRouter（唯一跨 tab 动作=路由）/ RootModeTabsView（D4 唯一分叉，MinisApp 一行换根）/ RemoteRootView（三态壳，只吃 RemoteKit public 面）。
- 隔离：本地数据流零触碰；两侧 tab 各自渲染同一胶囊组件（selection 共享源），切换位置不动。回归项：本机 tab 冒烟（sync 详情可达/多选标题/指示器）+ iOS Build 绿。
- 分期带期：QR 扫码=批8、R0 列表=批8、notice 交互 UI=批8（数据面已 public）。

## DEP-17 — Minis 部署目标 16.0 → 17.0 + 包下限 .v18→.v17（2026-09-15，⚠️ 待 pp 批准的兼容决策）

- 根因证据链：cc8e453 iOS Build exit 65；RemoteKit Build 同期绿（macOS 无门槛冲突）；Minis 配置 E51000072/73 = 16.0 < 包 .iOS(.v18)；冻结件用 Observation = iOS 17 硬底（上游 AA 自身 26.5）。
- 处置：只修配置（app 17.0 + 包 17.0），挂载与功能零删减。
- 代价：iOS 16 设备不再可装（一档兼容收缩），源自官方代码下限；否决回退路径=远程线不进 app（违背北极星，不可取）。
- 附带：ios-build.yml 错误面镜像进 job summary（日志桶两次 EOF 的永久解药，构建行为零变化）。

## B8-AUTH — 首启登录页 = AA 官方页全复用 + JO-6 本地入口（2026-09-15 pp："登录页扫码登录、手动登录完全用aa的 然后本地的进入配置东西的ui也要跟着aa的视觉风格进行风格统一设计"）

- **提取**：14 件 verbatim 进 src/ios/Views/AuthAA/（ServiceEntryView=截图落地页/QRCode 四步流/ManualLogin+OAuth 协调器/扫码相机件/AuthLayout 系/AppTheme/AppFontRegistry+Caveat 字体(403,648B sha 校验)/AppSheetPresentation/PrivacyPolicySheet）；AAV2/Services+Stores（LocalNetworkAccess/KeychainStore）进冻结区，manifest 52 条目 strong PASS。
- **改类留痕**（每类唯一断言+干跑）：①AppState→RemoteService 重绑（声明+调用点 3 处，残留=0）②载荷镜像 RemotePairingPayload（wire 常量 agents-anywhere.mobile-login v1 保留=协议值；Hashable 供路由枚举）③glassEffect 可用性 shim ×2（上游 26.5 无守卫，我们 17 底，26+ 逐参数原样、<26 走上游同位 background 无自造 blur）④可见品牌串→Moonveil（BR 政策；协议常量不动）⑤隐私表=结构保留+内容占位（他人法律文书/仓库链接不冒充，开放门发布正式政策）⑥#Preview 剥除。
- **引擎/门面**：checkServer 链（prepare→health→authConfig）/钥匙串持久化+restoreSession/signOut=delete/isWorking/completeManualLogin——全部镜像 AppState 官方语义（行号注记）。
- **接线**：RootModeTabsView fullScreenCover 登录盖（远程 tab 且未登录才出现；登录→远程、JO-6 灰字本地入口→本机、lastTab 记忆）；MinisApp init 字体注册；RemoteRootView idle=诚实空态卡一键回登录；pbxproj +68 纯插入（difflib 证明）。
- **8b 排期（pp 同条指令后半段）**：本机 tab 设置面视觉统一=AA 设计语言（AppTheme/AppGlassButton/玻璃卡）皮肤级重做，功能零删减，数据流零触碰。

## B8-VISUAL — 本机设置面 AA 视觉统一（2026-09-15 8b，pp："本地的进入配置东西的ui也要跟着aa的视觉风格进行风格统一设计"）

- **皮肤套件**：src/ios/Views/SettingsSkin/ 两文件——AppSymbol.swift（AA v2.0.0 verbatim，零外部依赖，diff 证）+ SettingsKit.swift（AA SettingsComponents 的 closeSettings env/SettingsRow/页面 chrome 逐行端口，`.settingsPage` 同名对齐；另加推入页变体 settingsChildPage=我们的胶合，AA 是 sheet 式我们是 NavigationStack 式）。
- **刷皮面**：根页 SettingsSheet（ContentView 内）3 处：listStyle insetGrouped + Done 钮→SheetCloseToolbar（同 dismiss 语义，pp 令的样式统一）；Settings/ 表单页 +14 件统一 insetGrouped/inline 标题，14 件按需未动（内容列表如日志/已有显式样式/非字面标题页不硬刷——完整性零删减，皮随件走）。
- **纯皮证明**：git diff 词表审计（listStyle|navigationTitle|TitleDisplayMode|SheetCloseToolbar|ToolbarItem|Done）违规行=0；15 文件 +16/-1。pbxproj SettingsSkin 登记 +14 纯插入（difflib 9 ops 全 insert）。
- **隔离**：零 @State/导航/数据流触碰；本地 agent 行为不变；RemoteKit 面零沾染。

## B8-FIX2 — 登录面编译修复轮（2026-09-15，CI 实证红单发先例；错误面经 ::error:: annotations 一次拿全=新通道首胜）

- **缺件补正（verbatim 双证）**：AsyncResultGate.swift、ServerNetworkPolicy.swift — LocalNetworkAccess 的官方依赖住在别的目录，闭包脚本"跨目录漏拉"家族第三案。AAV2 白名单补 Models/Auth 条目，manifest 52→54，强门 PASS，冻结文件本体零编辑。
- **自造 API 清剿**：needsLocalNetworkSettings 检测原用杜撰的 URLError.networkPermissionDenied（违"不猜 API"铁例，当场抓获）→ 换官方真身：AppState:162 `error is LocalNetworkAccessError`（含我们 transport 壳拆层）。
- **Glue 优先级手滑 ×2**：`try? await x.map{}` 的 .map 吃在 AuthMe 上 → if-let 形重写（167/177 两态）。
- **RK 门假绿案（判例第四案）**：`if ! swift build | tee | tail` 管道吞退出码——cbac5c2 上 Services 缺件编译必炸却报 success 实锤其谎。修=ios-build.yml 同款 PIPESTATUS 仪式，收紧不放松。YAML 三文件 parse 验后推。
- **语言模式悬案（探针中）**：target 级 swiftLanguageMode(.v5) 在 Xcode 包集成疑似未生效（同码 macOS swift build 绿 / iOS xcodebuild 红 permitsRetry 措辞=Swift6 硬错）→ 包级 swiftLanguageModes:[.v5] 补声明（末位实参无逗号教训 ×2 本地门拦下）。若 iOS 轮仍报 permitsRetry=假说死，另查 SWIFT_STRICT_CONCURRENCY 注入。
- 本地 sanity 判例：swift build 全量在 Linux 吃 Apple 框架（Network）≠ CI 环境；162 只能当纯 Foundation 面的粗筛，Apple-only 文件编译门以 macOS CI 为准（既有制度，不迁就本地改代码）。

## B8-FIX3 — 协议镜像补全 + 语言模式根源轮（2026-09-15，CI 实证红第二轮，单发先例内）

- **协议面自纠（阉割级）**：RemotePairingPayload 镜像漏 `expiresAt` 官方字段（MobileLoginPayload 六字段 APIModels.swift:66-73，非可选）+ toOfficial 曾写杜撰常量 "mobile-login"——真机握手必被服务端校型拒（QRCodeLoginView:130 实证官方值 "agents-anywhere.mobile-login"）。双错上线前拆除，六字段全量直通。
- **语言模式根源探针**：target 级与包级 pin 均被 Xcode 无视（同码 macOS swift build 绿 / Xcode Swift6 硬错 permitsRetry）→ tools-version 6.0→**5.9**（Xcode 从 banner 取模式，5.9 默认 v5=上游 SWIFT_VERSION 5.0 姿势）。连带判例：**Swift 尾逗号全域禁止**（实参表/数组皆炸，本轮 ×3 现场）、**banner 行禁尾注**（SwiftPM 把整行当版本号）、取证命令别把 stderr 灌进 JSON 管道。
- RK 门保持 PIPESTATUS 诚实版；Glue try? 优先级两态已正。iOS-only 分支盲区制度注记：macOS swift build 不含 UIKit/Network 分支，最终编译门=iOS Build（既有制度，annotations 通道兜底取证）。

## B8-FIX4 — permitsRetry 末路配置轮（2026-09-15，CI 实证红单发，探针②分支执行）
tools-5.9 假说死（banner 已降、permitsRetry 独苗仍炸，Xcode 26.2 不吃）。改走 xcodebuild **命令行构建设置覆盖**（压到集成包全部 target）：SWIFT_VERSION=5.0（上游项目本值）+ SWIFT_STRICT_CONCURRENCY=minimal。配置面零代码编辑：AAV2 逐字节未动（强门历次 PASS 佐证）、重试策略零删减。若此路仍红=配置穷尽，届时才议带台账的偏差补丁（需 pp）。


### AAV2-AWAIT-1 (2026-09-15, pp approval in chat — question 「批 A 案这一行?」 answer 「行」)
- File: Packages/RemoteKit/Sources/AAV2/Network/HTTPTransport.swift, call site line 56
- Deviation: `retryPolicy.permitsRetry(error)` -> `await retryPolicy.permitsRetry(error)` (5 chars added, nothing else)
- Why: bare call is a HARD error even in Swift 5 mode ("expression is 'async' but is
  not marked with 'await'") — isolated-repro machine-proven: bare=error, awaited=0 errors
  under -swift-version 5 AND 6 (swiftc 6.0.3). All configuration surfaces exhausted
  (target pin, package pin, tools banner, xcodebuild overrides, target-level default
  isolation [polluted local line, scoped out], per-file COMPILER_FLAGS [not honored by
  Xcode for Swift]). Upstream stays byte-compilable on the author's Xcode-27 combo only.
- Semantics: zero loss — pure error-code table function; call site already async; the
  hop matches the author's own @MainActor design intent.
- EXIT: any future AA tag landing await/refactoring this guard -> delete this patch,
  restore the byte, re-baseline FREEZE-MANIFEST (strong gate fails any other shape).
- Gate: aav2-freeze-check strong mode reverse-verifies "ours == upstream+sed exactly";
  counter-probes done: revoke-await rc=1, second-deviation rc=1, correct state rc=0.

### B14-E — ⛔ REVERTED（2026-09-16 装机即坏，pp 令「还原」）
- **回退**：`ContentView.swift` + `Views/ModeTabs/` 四件逐字节回到 **cf9e35f**（那一版 ci + iOS Build 双绿），本节以下全部记录为过程账，不再是现状态。
- **压垮它的缺陷**：`ModeTabPicker` 的 `ZStack` 我写成 `HStack(文字) → capsule`，胶囊成了最后一个子视图 = **画在选中段文字之上** → 真机顶栏是一颗空的灰药丸，"Moonveil" 被盖掉。pp 参考件里顺序是反的（胶囊在前、文字在后）。判例：**照抄参考件时子视图顺序也是规格的一部分，不是排版细节**；这一条在 CI 里永远抓不到（类型全对），只有真机看得见。
- 下面保留原申报，是为了下次真要做固定栏时不必重新踩：接缝形状、Equatable、DEBUG 垫片、stage 拆分、60fps 闸门那些结论仍然成立。

### B14-E — 固定顶栏搬出 ContentView（2026-09-16, pp「我要的就是平移」+「齿轮不要划走」；已回退）
- Files: `src/ios/Views/ContentView.swift`（`sidebarToolbarContent` + 新增 `bodyBarSeamStage`）、`Views/ModeTabs/{RootModeTabsView,ModeTabPicker,RemoteRootView,RootTabRouter}.swift`
- Deviation: resting-state 的齿轮（topBarLeading）、闹钟（topBarTrailing）、五项终端 Menu（topBarTrailing）从 ContentView 的 ToolbarItem 组里摘除；principal 换成等宽 `Color.clear` 占位（顶栏带宽/内缩不变）；`titleSyncIndicator` 逐字搬进外壳（单份，`PulseRotateIcon` 去 private）；新增 `LocalBarAction` 一次性动作接缝 + 五个单向呈现镜像（`localAtRoot / localSelecting / barHasAlarms / barSyncSubtitle / barKeepScreenAwake`）。
- Why: 两页现在在同一根固定栏下面横向平移（Grok 的结构：栏不属于任何一页）。住在某页 toolbar 里的按钮不可能在页滑动时保持不动。
- Semantics: 能力面零删减 —— 四颗按钮、菜单五项、指示器四态、点已选段开 sync 迁移详情全部仍在，动作落回 ContentView 自己的 `activeToolSheet / showTerminal / showAlarmList / keepScreenAwake`。勾选态 chrome（Cancel / Select All / "N Selected"）有意不搬：只在勾选时存在、文案要读 `selectedIds`/`sessions`，外壳靠 `localSelecting` 让位不重复。
- CI: 连红两轮后绿（① modifier 链加长撞 type-check 预算 → 拆独立 stage；② 搬链丢了接收者 `base` + `onChange` 要求 `LocalBarAction: Equatable`；③ DEBUG-only 的 `keepScreenAwake` 被无条件引用 ×4 → `keepAwakeFlag` 垫片）。tip `bdfe1af`：ci + iOS Build 双绿。
- Gate note: 本地 `swiftc -parse` 对含裸斜杠正则的文件必须加 `-enable-bare-slash-regex`（swiftc 6.0.3 默认关，Xcode 26.2 默认开），否则假红。

### B15-CODE — 行内代码对齐 Grok（2026-09-16, pp「把橙色部分的字体和颜色也对齐 grok」）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（`SelectableMarkdownTheme` + `minisInlineCodeBackgroundColor`）
- Deviation: ① 字体 Menlo → **SF Mono**（`.monospacedSystemFont(ofSize: baseFontSize*0.845, weight: .regular)`，PingFang SC cascade 原样保留）；② 浅色行内代码字色 `.systemOrange` → **#EA6F30**（pp 的 Grok 截图取核心墨色中值 234,112,49）；③ 浅色行内代码底色 `.systemGray6` → `.clear`（Grok 浅色只靠颜色标记，无 pill）。
- Why: Grok 规格表 `Code | SF Mono | 13.5pt | 400`，浅色无底、深色有底；字号比例本来就已对齐（Grok 13.5/16 = 0.844，我们 0.845），所以只换字形不换缩放 —— 聊天字号滑块继续有效。
- Semantics: 零删减。浅色无底照 pp 令；深色 `#3A3A3C` pill 曾保留（可读性案底见 `[T-inline-code-dark-bg-ios]`），**2026-09-17 已被 B15-CODE3 移除**。点击复制、hair-space 内边距、圆角绘制路径（画透明，仍一条代码路径）全部不变。
- EXIT: pp 若要连 Grok 深色那套（白字 `#E7E9EA` + `#16181C` 底 + `#2F3336` 0.5pt 描边）一起照抄，改的是同两个属性，届时本条改写不留双份。

### B15-CODE2 — 行内代码第二次改判：细的根因是字族与字号，不是颜色（2026-09-16, pp「现在这效果字体也细」→「f最像」→「走f」）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（`SelectableMarkdownTheme.inlineCodeFont` / `inlineCodeColor`）
- Deviation: ① 字号比例 `0.845` → **`0.95`**；② 字重 `.regular` → **`.medium`**（字族仍是 `.monospacedSystemFont` = SF Mono，PingFang SC cascade 不动）；③ 浅色芯色 `#EA6F30` → `#F5691F` → `#ED6D2E` → **`#FF6A00`**（2026-09-17 pp 终选「极艳纯橘」：预览阶梯对比后放弃 Grok 对齐路线——他给的 (227,122,69)/(204,113,66) 饱和度 74%/58% 反而低于现役 84%，要「更鲜艳」就直达 100% 饱和的纯橘）。
- Why（全部逐像素实测，不是眼力活）: 先立对照组——两 App 的**正文**笔画/em = 月纱 0.0926 / Grok 0.0909，基本相同 ⇒ 量法公平。行内代码：月纱 **0.079** vs Grok **0.096**（粗 22%，绝对值 3px vs 4px）；拉伸方向：代码 Latin 步进 22.8px vs 26.1px，而正文 CJK 步进 43.2 vs 44（几乎一致）⇒ **我的代码比 Grok 小一圈**。用 iOS WebKit 渲同尺度探针逐候选量 stroke/em：SF Mono reg ×0.845 = 0.0896（现状，与真机实测 0.0877 互证）、SF Mono **Medium** ×0.95 = 0.1116、Menlo reg ×0.95 = 0.1037、Grok 真机 = 0.0996。
- 改判关系（本条覆盖 B15-CODE 的字体判决，不留双份）: B15-CODE 把 Menlo 换成 SF Mono、并按 `13.5/16 = 0.844` 定了 0.845，依据是 Grok 的**网页 CSS token 表**。本条实测推翻它：**网页 token 不能当 iOS 规格**，跨端对齐必须量同一平台的截图。字族在 SF Mono Medium（F）与 Menlo Regular（G）之间由 pp 拍板 → **F**（我的票投 G，因为它离 0.0996 更近；F 比目标粗约 12%，可 pp 眼准优先）。
- Semantics: 零删减。点击复制（`.inlineCodeText`）、hair-space 内边距、圆角绘制路径全部不动；双态底色已统一为无底、双态字色已统一为 #FF6A00（见 B15-CODE3）。字号变大会改变气泡内的换行位置与行高，这是预期效果，不涉及布局算法。
- ⚠️ 唯一未自证项（真机必须看）: 权重是否真的吃到。`monospacedSystemFont(weight:.medium)` 先取 `fontDescriptor` 再 `UIFont(descriptor:size:)` 回来，这一趟往是为了挂 PingFang cascade；若装机后行内代码**变大了但仍细**，就是 descriptor 往返丢了权重，改法 = 改用 `UIFontDescriptor` 直接带 `.weight` 属性构造，不再从 font 取 descriptor。
- EXIT: 装机复拍一张同机同字号截图，重测 stroke/em；若超 Grok 太多，只需把 `.medium` 退回 `.regular` 并把比例守在 0.95（即 G 方案的变体），本条改写不留双份。

### B15-CODE3 — 深色模式行内代码底块移除（2026-09-17, pp「把深色模式的那个底块 不要」）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（`minisInlineCodeBackgroundColor`）
- Deviation: 深色分支 `#3A3A3C`（systemGray4）pill → **`.clear`**，常量收成单一 `.clear`；与浅色统一为「纯字色无底」。
- Why: pp 明示，覆盖原 `[T-inline-code-dark-bg-ios]` 案底（systemGray6 在深色解析成 #1C1C1E 会读作裸文本）。视觉决定优先于可读性推导。
- Semantics: 零删减。painter 仍一条代码路径（画透明）、`.inlineCodeText` 点击复制不变、圆角绘制逻辑与 `.inlineCodeBackground` 标记保留。
- Dev 增补: 深色字色同时 `.systemOrange` → **#FF6A00**(pp「深色也改」)。底块已无,颜色自己扛对比度(深色背景 ~6:1,过 WCAG AA)。至此双态统一为同一颗纯橘。

### B14-F — 顶部 tab 回到历史第一版（2026-09-16, pp「改回历史第一版切换tab那版」）
- File: `src/ios/Views/ModeTabs/ModeTabPicker.swift` 逐字节回到 **`131c261`**（B7 实色轨道 + 白药丸那版：36pt 轨道 / 3pt 内衬 / 14pt semibold / 选中白胶囊 / matchedGeometry / spring(0.28,0.82) / iOS26 轨道走 AA 的 `.glassEffect(.regular.interactive())`、<26 降级 secondarySystemBackground）。
- 为什么不是 `b5323bb`（真正的第一个 commit）：那版用 GeometryReader 供宽，在 `ToolbarItem(.principal)` 里没有固有尺寸 → 塌成 ~10pt 细条（当时真机实报）。`131c261` 与它只差 `trackWidth = 200` 一行，是第一版里**唯一能正常显示**的那版。
- 其余四件（ContentView / RootModeTabsView / RootTabRouter / RemoteRootView）保持 `cf9e35f` 原样：列表横滑切档、淡入换页、齿轮在页内顶栏。接缝与固定栏仍未启用。
- 能力面：点已选本机段开 sync 迁移详情（`onLocalRetap`）在该版本已存在，签名一致，调用点零改动。

### B16-GEAR — 设置入口搬到固定栏，设置页改由外壳呈现（2026-09-16, pp「我就是希望 remote 也能开设置」→「行吧」→「现在就做齿轮」）
- Files: `Views/ContentView.swift`、`Views/ModeTabs/RootTabRouter.swift`、`Views/ModeTabs/RootModeTabsView.swift`
- Deviations（逐处）：
  1. `sidebarToolbarContent` 的 topBarLeading **齿轮分支摘除**（`isSelecting` 的 Cancel 原样留在页内，由系统画）。齿轮现在由 `RootModeTabsView` 画 —— 它必须两档都在、且切档时不随页滑走，住在任何一页的 toolbar 里都做不到。
  2. 材质 = **`Circle().fill(.clear).glassEffect(.regular.interactive(), in: Circle())`**，与胶囊同一份玻璃；iOS<26 降级 `secondarySystemBackground` + 1pt 描边。**明确不用 `.buttonStyle(.glass)`** —— 那个按钮样式在浅色态自带灰底和自己的内边距，B14e 就是拿它冒充 toolbar 按钮才被 pp 判为"形状不对"。
  3. `SettingsSheet` 的呈现从 `ContentView` 挪到外壳：`RootTabRouter.showSettings` 一个 Bool，两档共用同一个可见宿主。**动机不是省事**：Remote 档时 `ContentView` 活着但 `opacity 0`，"不可见宿主能否稳定呈现 sheet" 不该成为承重假设。`ContentView` 里 `.settings` 那个 case 保留（无写入点，纯兜底）。
  4. `SettingsSheet` 由 `private struct` 改 `struct`（跨文件构造所需）；内部实现零改动。它签名里的 `showTerminal` 全程未被读取（vestigial），外壳传 `.constant(false)`，不改签名不改行为。
  5. `.settings` 的四个写入点（齿轮、语言切换重开 `pendingSettingsReopen`、深链 `showEnvironmentVariables` / `showPermissions` / `pendingSettingsTarget`）全部改指 `tabRouter.showSettings`，**入口一个没减**。
  6. 两个单向低频镜像：`localAtRoot`（push 进聊天页时固定齿轮让位）、`localSelecting`（勾选态时让位给页内 Cancel，不重复）。写在一轮之后（`DispatchQueue.main.async`），避免 "Publishing changes from within view updates"。
- 自查抓回一处我自己带进去的回归：我在 `pendingSettingsReopen` 读取点顺手加了 `removeObject`，而**真正的消费者是 `SettingsSheet.onAppear`（7818 行，读值后 push 到 Appearance 页再清）** —— 早清一步就会把"语言切换后回到原页"吃掉。已撤。判例：搬动代码时"顺手补的清理"也是行为改动，必须查这个 key 还有谁在读。
- Semantics: 能力面持平或变大 —— 齿轮动作不变；**Remote 档新增设置入口（加法）**；深链/语言切换/权限/环境变量四条入口全部保留；勾选态 Cancel/Select All 未动。
- 已知观感风险（真机看）：齿轮位置按 leading 16pt、band 44pt 居中算，与系统 toolbar 的内缩可能差 1-3pt；形状是玻璃自绘，不再声称与系统逐像素同。
- EXIT: 若下一批（两页平移 + 胶囊上提）落地，齿轮并入同一条固定栏，本节结构不变；若 pp 判齿轮形状不可接受，回退方向是"齿轮留在页内 + 接受它随页滑走"，不是回去冒充系统按钮。

### B16-PILL-FEEL — 拖动不跟手 + 不放大不发亮（2026-09-16, pp「胶囊这下对了 但是我拖着胶囊不跟手啊卡卡的」「而且我拖动也没有放大和发亮」）
- Files: `Views/ModeTabs/ModeTabPicker.swift`、`Views/ModeTabs/RootModeTabsView.swift`（1 行）
- 三处根因：
  1. `dragSlop = 10`（照抄 SwiftUI 默认）= 起手 10pt 死区，手指先空走再"跳进来"。→ **3pt**。
  2. 方向判定 `guard |dx| > |dy|×1.35` 挂在**每个** onChanged 上、无锁存：中途手指稍偏竖直就 return，`progress` 停更 → 胶囊在手指下冻住再蹿上来（= 卡卡的）。→ **一次判定 + 锁存到松手**（`directionLocked`，onEnded / onChange(selection) 双复位）。1.35 用 pp 给的数；外壳整页滑动 `pageSwipe` 的 minimumDistance 也从 10 改成 pp 给的 12。
  3. **`.interactive()` 不会为我们亮**：那个变体只在"真控件"的按压态上生效，而这一层是装饰层且 `allowsHitTesting(false)` → 永不放大/提亮。上游 AA 同类装饰层用的正是**不带 interactive 的 `.regular`**（`AuthGlassCompat.swift:11`），同一个道理。→ 提亮放大**自己画**：`scaleEffect 1.06` + 白色高光 `overlay`（浅色 0.26 / 深色 0.16）+ 阴影 0.09→0.18、radius 6→9，走同一条 spring；点按任一段也亮（`SegmentButtonStyle` 新增 `onPressChange` 把 `isPressed` 回传，写在 `DispatchQueue.main.async` 里避 "Publishing changes from within view updates"）。
- Semantics: 纯观感层，能力面不变（点档 soft 触感、越界 detent、就近吸附、onLocalRetap 开 sync 详情、整条顶栏宽热区 + highPriorityGesture 全部保留）。旋钮全做成常数，真机若过头按数回调。
- 门：parse / freeze / import-scan / fork-point 全 rc=0。⚠️ parse≠编译：本轮新增 `@Environment(\.colorScheme)`、`ButtonStyle` 带闭包属性、`onChange(of: configuration.isPressed)` 三处，都在 CI 才见真章。
- 现场注记：`PATCHES.md` 与 `SelectableMarkdownView.swift` 工作区里另有**另一会话在飞的行内代码批**，提交本批时只 add ModeTabs 两个文件，不裹别人的活。

### B16-PILL-SIZE — 胶囊高度按 Grok 截图重量（2026-09-16, pp「胶囊的高度不太对 现在有点窄 你对照gork这个来量一下」+ 贴 Grok 的 CSS token 表）
- File: `Views/ModeTabs/ModeTabPicker.swift`（纯观感层，能力面不变）
- 量法：pp 新图 `photo_33EAEE5C.png`（1179px@3x，Grok 现役顶栏），过胶囊中心列/行做亮度阈值扫描（白盘 ≥252）：
  | 量 | Grok 实测 | 我原来 | 改成 |
  |---|---|---|---|
  | 盘高 | 67.7→99.0pt = **31.3pt** | 26 | **30** |
  | 盘宽（提问） | 103.7→155.0pt = **51.3pt**（墨迹宽 25.0pt） | 字宽+24 | 字宽+**26**（hPadding 13） |
  | 字号 | 墨迹高 提问 12.3 / Imagine 13.0（含降部）→ **14pt** | 15 | **14** |
  | 静息阴影 | 他贴的 web token `0 1px 3px rgba(0,0,0,.06)` | 0.09/r6/y1 | **0.06/r3/y1** |
  | 按压缩放 | 他贴的 token `scale(0.97)` | 0.92 | **0.97** |
  - 结论：**"窄"不是宽度问题，是盘高与字号的比例** —— Grok 是 30pt 盘包 14pt 字（留 16pt），我是 26pt 盘包 15pt 字（留 11pt）。
- 有意未跟：Grok 的 web token 写「选中变黑，未选中灰色」，其截图里第三档 Build 也确实偏灰；pp 上午明说我们「两段都黑」→ 保留两段黑，要翻只改 `segment` 的 foregroundStyle 一行。
- 🔴 自查抓到一处 CI-only 错：`SegmentButtonStyle` 里写 `Self.pressScale` —— 那是**另一个类型**，parse 不解析名字所以本地全绿、CI 必炸。已改 `ModeTabPicker.pressScale`（同文件 private 可见）。判例：把常数加在 A 类型、在 B 类型里用 `Self.` 引用 = 必错，加完常数要问"用它的那行在哪个类型里"。
- 门：parse / freeze / import-scan / fork-point 全 rc=0。仍须 CI 终审（本轮新增 `@Environment(\.colorScheme)`、带闭包的 ButtonStyle、`onChange(of: configuration.isPressed)`）。

### B16-PILL-WEIGHT — 两段同字重（2026-09-16, pp「两段都黑」→「没选中的是不是字体要偏细一些？」→「未选中也要一样的粗细 改一下」）
- 终态：`segment` 字重 = 单一常数 `labelWeight = .semibold`，**选中与未选中同字重、同黑色**，选中态只由那颗玻璃胶囊标记。Grok 是靠颜色分档（选中黑/未选中灰），我们有意不用。
- 过程留痕：中途按 pp 上一问把未选中降到 `.light`（一版），下一条指令即改回同字重 → 常数合并为一个，将来要恢复对比只改这一处。
- 诚实标注：Grok 未选中的真实字重**没能量净**（CJK 竖笔与相邻笔画合并、Latin 样本 stroke/em=0.141 被阈值污染）⇒ 这类"细一点/粗一点"的判决跟 pp 的眼睛走，不跟数据走。
- 门：parse / import-scan rc=0。

### B16-BAR-EMPHASIS — 齿轮的放大/发亮/弹簧 + 胶囊落位弹簧（2026-09-16, pp「那个设置按钮 拖动放大、发亮效果没了」「弹簧效果也没了」）
- Files: `Views/ModeTabs/RootModeTabsView.swift`、`Views/ModeTabs/ModeTabPicker.swift`（纯观感层，能力面零变化）
- **同一个病根的第二个实例**：齿轮的玻璃写在 `.background { Circle().glassEffect(.regular.interactive(), …) }` 里 —— `interactive()` 只对"长在控件自己身上"的玻璃生效，背景层里的玻璃它管不着，所以永不放大永不亮。修法与胶囊一致：**按下态自己画**。
  - 新增 `BarPressStyle: ButtonStyle` 把 `configuration.isPressed` 经 `DispatchQueue.main.async` 回传到 `@State gearPressed`（同模块已撞过两次 "Publishing changes from within view updates"）。
  - `gearPressed` → `scaleEffect(ModeTabPicker.dragScale)` + 白高光 `Circle().fill(.white.opacity(…))`（浅 .26 / 深 .16，故外壳重新引入 `@Environment(\.colorScheme)`）+ 阴影 0.06/r3 → 0.14/r7，`.animation(ModeTabPicker.settle, value: gearPressed)`。
  - **常数共享**：`settle / dragScale / sheenLight / sheenDark` 由 `private static` 提为 `static`（internal），齿轮直接引用 `ModeTabPicker.*` —— 固定栏只说一种材质语言，两处不会各调各的手感。跨类型引用一律写类型名，不写 `Self.`（本轮已按 B16-PILL-SIZE 的判例自查过，grep 零误用）。
- 🔴 **顺带查出胶囊的落位弹簧也掉了**（pp 第二句「弹簧效果也没了」的真因之一）：加 emphasis 修饰层之后，只靠 `withAnimation(settle){ selection = … }` 不够 —— 值经 `@StateObject`/`Binding` 传播时事务动画没吃到，胶囊瞬移。→ 在 pill 上显式钉 `.animation(Self.settle, value: selection.slot)`。拖动中 `slot` 不变，所以跟手仍是 1:1 无拖滞。
- 门：parse / freeze / import-scan / fork-point 全 rc=0；diff ModeTabs 两文件 +136/−19。⚠️ parse≠编译：本轮新增 ButtonStyle 带 `Binding`、`onChange(of: configuration.isPressed)`、跨文件 internal 常数引用，CI 终审。
- 停在未提交。并发纪律：另一会话已把 `SelectableMarkdownView.swift` 放进暂存区 → 提交用 pathspec 形式 `git commit -- <ModeTabs 两文件>`，不裹别人的活。

### B16-BAR-ICON — 设置入口图标换成 AA 的抽屉按钮（2026-09-16, pp「把设置按钮的那个图标改一下吧 改成aa的那个抽屉按钮」）
- File: `Views/ModeTabs/RootModeTabsView.swift`（纯外观，动作与入口零变化）
- 上游取证（不私造）：AA 的抽屉按钮 = `Views/Chat/ChatPageToolbar.swift:99-101` 的 `struct SidebarMenuIcon { AppSymbol("sidebar.left", size: 22) }`，`AppSymbolAssets.swift:90` 把 `sidebar.left` 映射到资源 **`aa-TextAlignStart`**（Web Lucide 路径，template 向量）。按钮外再挂 `.accessibilityLabel(String(localized: "打开侧栏"))`。
- 落地：`Image(systemName: "gear")` → `AppSymbol("sidebar.left", size: 22)`。资源与映射**仓里早就有**（批 8b 的 SettingsSkin 面），本次零新增资源、pbxproj 不动，`audit-aa-assets.py` 照绿。
- 尺寸口径：22pt 用 AA 自己的数（不再沿用旧齿轮墨迹反推的 22）；`AppSymbol` 内部是 `@ScaledMetric(relativeTo: .body)`，所以跟着动态字体走，和上游同形为。
- 🔴 a11y 不静默降级：`AppSymbol` 自带 `.accessibilityHidden(true)`（上游也这样），所以按钮必须自己带标签 —— 补 `.accessibilityLabel(Text(String(localized: "Settings")))`，用仓内已有词条（`Localizable.xcstrings:76808`，9 语已译）。
- 语义申报：这个图形在上游表示"开侧栏"，我们挂在"开设置"上（pp 要的是这个形）。标签仍写 Settings，不跟图形改成"侧栏"，免得 VoiceOver 与实际动作不一致。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。

### B16-FIX-VIS — run 35059803697 红一条：`'pressScale' is inaccessible due to 'private'`（2026-09-16）
- 唯一真错，且是我上一笔带进去的：`SegmentButtonStyle` 跨类型读 `ModeTabPicker.pressScale`，而它是 `private static`。
- 🔴 **判例（编译门第四类，parse 抓不到）**：Swift 的 `private` 只在**声明它的类型内部**（含同文件的该类型扩展）可见；**同文件的另一个类型读不到，那要 `fileprivate`**。我在台账里写的"同文件 private 可见"是错的，已按 CI 原文纠正。规则：跨类型引用的常数一律显式提 `internal`（或 `fileprivate`），别赌同文件。
- 修法（只修不删）：`pressScale`、`restShadow` 提为 `static`（internal）；顺带把外壳自己复制的那份 `restShadowOpacity = 0.06` 删掉，齿轮改读 `ModeTabPicker.restShadow.{opacity,radius,y}` —— 固定栏一份材质语言，一处调参两处同效。
- 自查升级为脚本：正则列出 picker 的 `private static` 成员 ∩ 外壳里 `ModeTabPicker.*` 引用 = 空集才算过（本轮输出"无 ✓"）。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。

### B16-GLASS-CONTAINER — 向 AA 输入框学真配方：GlassEffectContainer + glassEffectID（2026-09-16, pp「跟系统的那个做出来一样的效果…aa输入框就是这样的，相当于把aa输入框的那个效果做成了tab」）
- 上游取证（逐行读 `ChatComposer.swift`，不信转述）：`@Namespace private var glass`（:18）→ `GlassEffectContainer(spacing: 12) { … }`（:21）→ 内容整体 `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 形变态))`（:61）→ `.glassEffectID("composer", in: glass)`（:62）→ `.animation(reduceMotion ? nil : .smooth(duration: 0.24), value: 形变态)`（:68）。
- 🔴 **判例（推翻我上一笔的自绘方案）**：让玻璃"活起来"的是**容器 + 玻璃 ID**，不是 `.interactive()` 单独一个修饰符。玻璃脱离 `GlassEffectContainer` 就是死的（不响应按压、不形变）；容器还负责**间距内粘连**（spacing 12）与**同 ID 形状插值**（= pp 说的"拖着拉长延伸"）。我之前用 scaleEffect + 白高光 overlay 手搓，是在给一个本该由系统画的材质打补丁。
- 落地：① 胶囊整行包进 `GlassEffectContainer(spacing: 12)`，玻璃挂 `.glassEffectID("modePill", in: glassNS)`；② 齿轮的玻璃从 `.background` 里**搬到控件身上**（`gearControl.glassEffect(.regular.interactive(), in: Circle())`）并同样装容器 + `glassEffectID("settingsGear", …)`，于是删掉我自己的 `BarPressStyle` / `gearPressed` / 自绘高光与阴影（净 -57 行）；③ iOS<26 无 glass：容器分支不建，齿轮走系统实色 + 1pt 描边，胶囊走实色降级 —— 降级路径只用系统材质，不自造模糊（家规）。
- 能力面申报（铁律）：删的三样全是我自己上一批造的过渡件（按压回传 style、@State 按压态、手搓高光），**用户可见能力持平**：按下发亮放大改由系统给（更强）、a11y 标签 `Settings` 保留、点档/深链/勾选让位等逻辑一字未动。
### B16-SNAP-QUIET — 拖动吸附去掉触觉，逻辑回到历史第一版（2026-09-16, pp「这个拖动tab吸附不用做触屏反馈，其实逻辑跟历史第一版那个吸附一样的」）
- 删：中途越档的 `UISelectionFeedbackGenerator` detent 触感（含 `detent()` 整个函数与 `@State detented` 记账）、松手吸附成功时的 `softTick()`。→ 现在拖动 = 纯跟手 + 松手就近吸附（静默），越界仍是 0.32 阻尼（视觉，非触感）。
- 保留：**点按**切档的 soft 触感（Grok DESIGN.md「soft haptic on switch」，pp 早前确认）；外壳整页滑动的 `softTick()` 也保留 —— 它标的是"真的换了档"，不是拖动途中的吸附；若 pp 要一并静默，一句话删。
- 这是铁律里的合法出口：**pp 明示弃用 + 留字据**（本条即字据），不是我自行阉割。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。⚠️ `GlassEffectContainer`/`glassEffectID` 是 iOS 26 API 且我们仓内**首次使用**（上游 AA 有用，但我们没编译过）→ 必须 CI 终审。

### B16-SNAP-CLAUDIO — 与 claudio 的吸附逐条对表 + 补上尾随点击抑制（2026-09-16, pp「吸附逻辑应该是claudio会话开始选择agent的那个吸附 一样的道理」「你看看是不是一样的效果」）
- 参照件（只读，未改 claudio）：`~/claudio/src/ios/Views/ContentView.swift:6743-6793` `DraggableFAB`。
- 对表结论：**跟手映射、松手判定、回位弹簧三条本来就等价** —— claudio `dragOffset = translation.width`（1:1 pt）↔ 我 `progress = dx/slotStride` 后 `slot+progress` 插值；claudio 用"落点中心 vs 屏宽中线"↔ 我用 `round(slot+progress)`（两档居中时中心线≈中线）；`spring(0.35,0.75)` ↔ `spring(0.36,0.78)`。
- 三处不同：① 起手阈值 claudio 10pt（= pp 上午骂的"不跟手"死区），我保留 3pt；② 触感 claudio 只在真换边时 tick 一次（medium），我按 pp 令把拖动路径整体静默（点按 soft 保留）——**有意不同，留字据**；③ 🔴 真差异 = claudio 用 `.simultaneousGesture` + `didDrag`（抬手 0.15s 内吞掉 tap），我用 `highPriorityGesture` 且**没有这个抑制** → 拖完抬手会顺带触发落点那一段的 Button，表现为"多吸一格/回弹后再跳一次"。
- 落地：`@State didScrub` + `tap()` 首行 `if didScrub { return }` + onEnded 后 0.15s 复位（claudio 原窗口值）。
- 🔴 判例：claudio 那段文档注释自称"Uses UIKit's UIPanGestureRecognizer via UIViewRepresentable"，**代码里没有这件事**（就是 SwiftUI DragGesture + simultaneousGesture）。引用别人的实现前先读代码，别拿注释当证据 —— 我差点据此下沉到 UIKit 重写。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。⚠️ 本轮含**仓内首次使用 `GlassEffectContainer` / `glassEffectID`（iOS 26 API）**，parse 不代表编译通过，CI 终审。

### B16-SNAP-ARC — 「时而能发光放大时而不能」= 方向判定每帧重做 + 拇指弧线（2026-09-16, pp「胶囊时而拖动发光放大时而不能 我也不知道」）
- 机制：旧代码在每个 onChanged 上重测 `|dx| > |dy|×1.35` 才允许锁存。拇指在宽条上横拖天然带弧（例：末态 dx 60 / dy 50 → 60 > 67.5 不成立），于是**整次手势都不成立** ⇒ 既不跟手也不发亮放大。所以"时好时坏"取决于**手指的弧线**，不取决于控件 —— 这就是他说不清原因的原因。
- 修法：**一次判定、两个锁存态**。① 走到 `directionDecideDistance = 6pt` 才判（判得早，前 6pt 基本还是横向，1.35 这个 pp 给的数就够用）；② 判为横向 → `directionLocked = true`，此后不再重测；③ 判为纵向 → `directionRejected = true`，**本次手势彻底退出**（不再中途反悔重Claim，否则列表已开始滚、胶囊又突然抢手势会猛跳）。抬手与换档两条路都复位两个标志。
- 强调时机也改了：`isDragging = true` 紧跟"抢到"的那一刻，不等手指再走一段 ⇒ 发光放大从手势第一帧就在。
- 判据（可泛化）：**任何"每帧重估"的方向/意图判定，都要改成"早判一次 + 锁存 + 拒绝态"**；否则用户的手势轨迹会随机决定功能是否生效，症状表现为"时好时坏"，而且没人能复述触发条件。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。

### B16-NO-SHADOW — 摘掉胶囊与齿轮周围的投影（2026-09-16, pp「现在这个胶囊和设置按钮周围你是不是加了阴影 系统原生的没有阴影」）
- 是我加的。胶囊：静息 `0.06 / r3 / y1`、按下 `0.14 / r7`；齿轮那颗的阴影在上一批（玻璃从 `.background` 搬到控件身上、删掉我所有手搓件）时已经跟着没了 —— 所以**他手上那个包（34e1a32）里齿轮仍有阴影，新包里两处都干净**。
- 🔴 来源交代：那组数照搬了他贴的 Grok **网页** CSS token `box-shadow: 0 1px 3px rgba(0,0,0,.06)`。同族第三次踩（B15-CODE 字体族、B16-PILL-SIZE 盘高比例、这次阴影）⇒ **网页 token 不能当 iOS 材质规格**：iOS 26 的玻璃自带边缘与折射，再套 drop shadow 就成贴在白底上的实心贴纸。
- 规则升级：外部 token 表只用来读"意图"（有没有阴影、大概多轻），任何要落到 iOS 的数值必须在 iOS 截图上量出来才算；量不出来就默认不加、以系统材质为准。
- 现在两颗都只剩：玻璃本身（容器 + `glassEffectID`，形变与按压发亮由系统画）+ 胶囊按下时的 `scaleEffect` 与白色高光。删掉的 `restShadow` 常数是本轮我自己造的，非功能。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0。

### B16-FIX-CLOSURE — run 35067152326 红一条：`instance member 'padding' cannot be used on type 'View'`（2026-09-16）
- 真因不在报错那一行：辅助函数写成 `glassRow<Content: View>(@ViewBuilder _ content: Content)`（**值参**），调用处传的是闭包 `glassRow { rowContent }` ⇒ 编译器把 `Content` 推成 `View` 存在类型，于是挂在调用**之后**的 `.frame / .contentShape / .highPriorityGesture` 全成"在协议类型上调实例方法"，第一个（padding/frame）先炸。正解 = 参数改 `() -> Content`、体内 `content()`。
- 🔴 **编译门盲区第五类**（前四类见 B16-FIX-VIS / B15-PILL / B16-SNAP-CLAUDIO 各条）：`@ViewBuilder` 泛型包装函数必须收闭包。**定位口诀**：看到"某修饰符 cannot be used on type 'View'"，往上找上一个自定义 View 函数的签名，别在报错行改。
- 新增全域自查：`grep -rn "@ViewBuilder _ [a-z]*: Content)" src/ios/` —— 本轮扫出 0 处同类遗漏。
- 铁律执行：只改签名，`GlassEffectContainer` / `glassEffectID` 一个没删、没降级、没换实现。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0；tip be9fca6。

### B16-FIX-GROUP — 同一个措辞第二次红：裸 `if #available` 后接链式 modifier（2026-09-16, run 35068323175）
- 报错带位置才看清：`RootModeTabsView.swift:200:10: error: instance member 'padding' cannot be used on type 'View'` —— 上一笔我只修了 picker 的 `glassRow`（值参→闭包），**齿轮这里是同一类的另一种形状**：`@ViewBuilder var gearButton` 里裸写 `if #available { A } else { B }` 然后在 if/else 之后接 `.padding`。编译器把该条件式解析成 `View` 存在类型 ⇒ 下一个 modifier 就是"在协议类型上调实例方法"。
- 修法：条件式包进 `Group { … }`，分支就有了具体合并类型。**这不是我发明的写法** —— 本 target 里早就编译通过的两种姿势：`ModeTabPicker.pill` 用 Group；`ContentView` 的 `SearchBarSurface` / `FABGlassMorphID` 用 `ViewModifier`（后者还证明了 `glassEffectID(_:in:)` 收 `Namespace.ID` 是对的签名）。
- 铁律执行：只加一层 Group，容器、`glassEffectID`、控件身上的 interactive 玻璃、iOS<26 降级分支**一个没删、没降级**。
- 全域自查（新增）：扫 `if #available` 分支结束后第一行以 `.` 开头的写法 —— 本轮两个 ModeTabs 文件已无残留。
- 🔴 **编译门第五类的完整表述**（合并 B16-FIX-CLOSURE）：`@ViewBuilder` 上下文里，**任何"链式 modifier 接在一个无法确定具体类型的表达式上"**都会报 `instance member 'X' cannot be used on type 'View'`，两种触发形状：① 泛型包装函数把 ViewBuilder 参数写成值参（`_ content: Content`）；② 裸 `if #available`/`if-else` 条件式后直接接 modifier。**定位口诀不变**：报错行的 modifier 不是凶手，往上找它挂在那个表达式上，那个表达式就是凶手。

### B16-GLASS-REVERT — 胶囊的容器玻璃盖住了选中文字，回退为普通背景玻璃（2026-09-16, pp 装机 114541b「现在成这样了 看不到字了」）
- 🔴 **机制（判例，可泛化）**：`GlassEffectContainer` 会把它里面的玻璃**合成在兄弟视图之上**。我们的胶囊是 ZStack 里**垫在标签后面的独立视图**，进容器后它的玻璃被系统拎到文字上面 ⇒ 选中标签整颗被白色玻璃盖住 = "空胶囊看不到字"。（齿轮没事：它的玻璃是控件自己的背景，图标住在玻璃里，和 AA composer 的文字一样。）
- 修法：picker 摘掉 `GlassEffectContainer` / `glassEffectID("modePill")` / `@Namespace` / `glassSpacing`（净 −30 行），胶囊回到"普通背景玻璃 + 标签在上"（本仓 B14e 就立过"ORDER IS A SPEC"的家规，我违背了它才出事）。按压缩放与白高光是自绘的（这套在 34e1a32 上 pp 已确认"发光放大有了"），所以观感不变。
- 铁律申报：交互面一字未减 —— 跟手、方向早判+锁存+拒绝态、就近吸附、拖动静默、点按 soft、onLocalRetap、整条热区全保留；iOS<26 降级未动。只换了胶囊材质的渲染路径。
- 代价说明：胶囊的系统形变（同 ID 拉伸）随之放弃 —— 那需要玻璃长在"含文字的那个视图"上（选中段自带玻璃 + 共享 ID 形变），是下一轮可选方向，pp 要再上。
- 齿轮保留容器 + glassEffectID（同包实测图标正常）。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0；tip 4bbe0b0。

### B16-SEGMENT-GLASS — 玻璃长在选中段身上 + 拖动变便宜影子（2026-09-16, pp「看不到字了」+「拖着还是卡 应该是随意拖拽很顺滑啊」）
- 结构终案：**玻璃 = 选中段自己的背景**（`TabGlass` modifier：`.glassEffect(.regular.interactive(), in: .capsule)` + 两段共享一个 `glassEffectID("modePill")`），装进 `GlassEffectContainer(spacing:12)`。字是玻璃自己的内容 ⇒ 永不被盖（上轮兄弟胶囊盖字的病根断根）；`.interactive()` 因长在真控件上而生效；切换时系统把玻璃从旧段形变到新段 = "拉长延伸"，不用我画。
- 拖动 = **便宜影子**：`isDragging` 时一颗 `Color.primary.opacity(0.07)` 的纯色胶囊垫在标签下跟手（非玻璃 ⇒ 不会被容器拎到字上；纯色 ⇒ 每帧重绘很便宜），松手淡出，真玻璃由系统形变过去。
- 🔴 "还是卡"的真根因（两个）：① 旧代码 `interpolatedRect` 把 index **钳死在 0...1** ⇒ 手指拖过一档后胶囊停死，往回拖还有死区才动 ⇒ 修成**越界只阻尼不钳死**（edgeResistance 0.32，继续动）；② 容器玻璃逐帧跟手指重渲染 = 真机上很贵 ⇒ 玻璃拖动中静止、形变只发生在松手。
- 删（全是我自己上批造的、被系统行为替代的过渡件）：胶囊自绘 scale/高光 emphasised、pressedMode 回传、旧独立 pill 视图。保留交互面：跟手、方向早判锁存拒绝态、静默就近吸附、点按 soft、onLocalRetap、整行热区、iOS<26 实色降级。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0；tip a7fa896。

### B16-SWIPE-LOCK — 横向切页时冻结列表纵向滚动（2026-09-16, pp「左右滑动页面的时候容易滑到上下」）
- 机制：外壳 `pageSwipe` 是 plain `.gesture` + 方向门（|dx| > 1.2|dy|），切页会触发，但底下会话 List 的纵向滚动不受影响 ⇒ 斜向快滑 = 边切页边滚列表。
- 修法：`RootTabRouter.pageSwipeArmed`（published）—— 外壳在 swipe 确认那一刻置位、抬手复位；`ContentView.sessionList` 的 Group 挂 `.scrollDisabled(pageSwipeArmed)`（纯环境门：只有横向滑动提交期间生效，复位即失效；纯纵向滚动永远不会 armed，普通滚动手感不变）。
- 死隔离申报：ContentView 是我们已接管的分叉点文件，改动 = 列表上一个环境修饰符，无状态无生命周期无会话逻辑。回归项：非横滑时纵向滚动、行点选/选择、iPad splitList、横滑切页不再带列表位移。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0；tip c95772a。

### B16-LUCIDE-ICONS — ➕ / 🎤 图标 → Lucide 系（2026-09-17, pp「把➕号和语音那个图标替换成 lucide.dev 里面的图标」）
- Files: `AIChatView.swift`(两按钮)、`AppSymbolAssets.swift`(+2 映射)、新增 `Assets.xcassets/aa-Mic.imageset` + `aa-Keyboard.imageset`
- 落地:
  1. ➕ `Image(systemName: "plus")` → `AppSymbol("plus", size: 22)` —— `aa-Plus` 资源与映射**仓内现成**（B8 批），零新增。
  2. 🎤 `Image(systemName: isVoiceActive ? "keyboard" : "mic")` → `AppSymbol("mic", 19)` / `AppSymbol("keyboard", 16)` —— 两资源**新增**: 从 jsdelivr `lucide-static v1.46.0` 取官方 SVG（与 pp 给的 lucide.dev 同源），压成 aa- 格式（stroke #000000 + template-rendering-intent），imageset×2; 映射按字符序插入（keyboard/KeyRound 后、mic/Search 后）。
- 尺寸: 按各自图形在 24 viewBox 的占比反推（plus 14/24→22pt 净≈12.8; mic 20/24→19pt 净≈15.8; keyboard 16/24→16pt 净≈10.7），对齐原 SF 尺寸的光学重量; 真机可微调。
- a11y: ➕ 的 label 原样保留（挂 icon、两分支共用）; 🎤 原 a11y（.isButton + 两态 label）未动。
- Semantics: 两按钮行为面零变化（attach Menu/confirmationDialog 两分支、MicButton 自定义手势与阈值全不动）。
- 死隔离四问: ① 纯图标渲染、无状态分流; ② 无共享路径; ③ 资源走仓内 aa- 管线（官方 SVG 来源）、无新机制; ④ 回归项 = attach 菜单两分支、语音开合、激活态 keyboard 图标、aa-assets 门（91 refs 全命中）绿。
- 备注: keyboard 是同一按钮的激活态图标（「语音那个图标」的两态一致性），一并换成 Lucide; 不想要可单撤。

### B16-SLASH-ICON — "/" 字符按钮 → Lucide puzzle 图标(2026-09-17, pp「把/这个改成我给你的」+ SVG)
- File: `src/ios/Views/Chat/AIChatView.swift`(`slashMenuButton`)
- 落地: `Text("/")` → `AppSymbol("puzzlepiece.extension", size: 17)`(保留 34pt 圆底 / inputIconFg / inputIconBg / 描边结构,零其它改动)。
- 零新增资源: 仓内 `aa-Puzzle.imageset`(B8 批已搬)+ `AppSymbolAssets` 映射 `puzzlepiece.extension` **全部现成**;比对 pp 发的 SVG path 与 aa-Puzzle.svg 的 path **逐字节相同**(同一颗 Lucide puzzle)。
- a11y: AppSymbol 自带 `.accessibilityHidden(true)`,补 `.accessibilityLabel(Text("Command"))` —— 用 xcstrings 现成 9 语词条('Command' 已译 de/es/fr/ja/ko/zh),不新增键(B9 判例)。
- Semantics: 按钮 tap 行为(slash 菜单开合 + 聚焦)一字未动;纯图形替换。
- 死隔离四问: ① AIChatView 本机+远端共用,纯图标渲染、无状态分流;② 无共享路径;③ 资源与映射都是仓内现成件(B16-BAR-ICON 判据:换图标先查仓内同名件),零新机制;④ 回归项 = slash 菜单开合、点按热区 34pt、深浅色(模板渲染跟随 inputIconFg)。

### B16-USERBUBBLE — 用户气泡改 AA-式实色 + 暖调(2026-09-17, pp「把用户发的气泡改为 aa 那种实色，然后颜色调一下 比 aa 暖调一点」)
- Files: `Chat/AIChatView.swift`(`ChatColors.userBubble`)、`Chat/ChatMessageViews.swift`(`UserBubbleSurface` + `ContextMenuPreviewSurface`)
- 改动:
  1. `userBubble`: `UIColor.tertiarySystemFill`(半透明) → **实色微暖**(定稿:浅 `#F0F0EE` R-B=2 / 深 `#22211F` R-B=3)。调温链:初版 `#F6F0E7`(R-B=15,太暖)→ `#F1EFEA`(R-B=6,砍半)→ 按 pp 参照截图实测 `#EFEFED`(R=G、B-2)收短为定稿。AA 原值 = light `Color(white:0.94)` / dark `Color(white:0.13)`(源码实证:`aa-ios` 的 `SessionTimelineRow.UserMessageBubble`);暖调 = R 上抬、B 下压、亮度持平。
  2. `UserBubbleSurface`: 删 iOS 26 的 `.glassEffect(.regular, in: shape)` 分支 → 全 OS 统一实色填充(pp 要实色的确定感,不再采样身后内容)。
  3. `ContextMenuPreviewSurface`: 同步改实色——本文件注释的既有约束「浮板必须与气泡一致,长按抬起不能跳变」;实色自带不透明底,[T-ios-longpress-menu-preview-background] 透明快照 bug 不会复发。
- 未动: queued 态(空填充+虚线)不变;usage 小徽章(`userBubble.opacity(0.6)`)沿用同一常量、会随之略微变暖(同色系,未单独改);气泡形状 `RoundedRectangle(cornerRadius: 18)` 不动(与 contextMenuPreview 的 contentShape 对齐,注释有约束);AA 远端线原装实色不受影响。
- 死隔离四问: ① **已验证** RemoteKit/AuthAA/ModeTabs 不引用 `UserBubbleSurface`/`ChatColors`——本改动只影响本机线;远端 AA 线原装(本就实色),零接触;② 无共享路径;③ 无新机制(普通 Color 常量 + fill);④ 回归项 = 本机:发送/已发送气泡(浅深两态)、长按预览、queued 虚线、滚动流畅度(实色无材质合成更省)。

### B16-SCROLLBTN-GLASS — 浮动滚动按钮(上/下)改液态玻璃(2026-09-17, pp 截图「把这个按钮改为液态玻璃」)
- File: `src/ios/Views/Chat/AIChatView.swift`(`scrollFloatingButtonLabel` + 新增 `ScrollFloatingGlass` ViewModifier)
- 落地: 36pt 圆钮背景 systemBackground 近不透明盘 + 灰描边 + 手搓阴影 → **iOS 26 走 `.glassEffect(.regular.tint(.white).interactive(), in: .circle)`**(浅色白玻璃,与顶部胶囊同一材质语言;深色原色玻璃不 tint);**<26 降级保留原圆盘全套**(描边/阴影,[T-ios-scrollbtn-invisible-lightmode] 可读性修复件不能丢)。手搓描边/阴影只在 <26 保留——iOS 26 玻璃自带边缘光,叠加即贴纸感(B16-NO-SHADOW 判例)。
- interactive: 两颗是真 Button(齿轮 B16-GEAR 先例)——按压发亮由系统给。
- 图标色: `.secondary` → `ChatColors.inputIconFg`(pp 2026-09-17 追加「图标颜色改黑色」;与输入栏三图标同一「图标黑」常数,浅色纯黑/深色 secondaryLabel)。
- 历史教训对齐: 当年「半透明白 0.5 在白底不可读」用加深圆盘修;玻璃是 blur+折射材质,可读性机制不同,且白 tint 对齐胶囊(装机已验证的观感)。EXIT: 若真机浅色可读性差,回退该钮为降级圆盘(单处撤)。
- Semantics: 显隐条件(isNearBottom/isAtFirstTurn)、tap 动作(forceScrollToTop/Bottom)、transition、capsuleProtectedFrame 全不动;纯材质。BrowserDownloadFloatingButton 未点名不动。
- 死隔离四问: ① AIChatView 本机+远端共用,纯视觉、tap 行为不变;② 无共享路径;③ 配方全部仓内既有先例(齿轮 interactive/FAB tint/胶囊白);④ 回归项 = 两端:按钮显隐、上下翻页动作、<26 外观、深浅色、按压反馈。

### B16-SWIPE-SCOPE — 横滑切页收窄到根列表页,聊天页禁用(2026-09-17, pp「为什么聊天页滑动也能滑到remote页?」)
- File: `src/ios/Views/ModeTabs/RootModeTabsView.swift`(pageSwipe onChanged 栅栏区,单处)
- 改动: 起点栅栏最前面加 `guard router.localAtRoot else { return }` —— 本机已 push 进聊天页时整个横滑手势直接退出;只有根列表页(会话列表)才切页。
- 语义对齐: B13-SWIPEFIX-5 的「列表区横滑=切页」本意就是**会话列表**;聊天页(会话内)横滑无消费场景,误触反而打断阅读/滚动。Remote 侧当前无聊天页(connected 态仅状态卡),不受影响;将来 Remote 会话页上线时同规则适用(仍走这一个栅栏位)。
- Semantics: 手势其余部分零变化(速度裁决/锁存/拒绝态/scrollDisabled 门);只加作用域栅栏,localAtRoot 为 B16-GEAR 建的现成镜像状态(只读)。
- 死隔离四问: ① RootModeTabsView 为我们接管文件;② localAtRoot 只读、原消费者(齿轮让位)不受影响;③ 无新机制;④ 回归项 = 根列表页横滑切页如常、聊天页横滑不再切页、齿轮让位逻辑不受影响。

### B16-PILL-WHITE — 静息胶囊发灰的修复:content 显式透明 + 浅色 white tint(2026-09-17, pp 装机 5e1ad0c「顶部胶囊还是灰色啊」)
- File: `src/ios/Views/ModeTabs/ModeTabPicker.swift`(`pillLayer`)
- 双重根因:
  1. content 用了裸 `Capsule()` —— Shape 作为视图吃默认前景填充,半透明玻璃下垫了默认色层,玻璃被压暗成「实色灰」观感。
  2. `.regular` 玻璃在浅色模式的中性基色偏灰,没往白推。
- 修复: content → `Color.clear`(显式透明);浅色 `.regular.tint(.white)`(仓内先例 ContentView:4321 `fabCircleSurface` 的 `Glass.regular.tint($0)`,官方 API);深色不 tint(防泛白)。dragSheen/scale/offset/animation 全保留。
- Semantics: 纯材质渲染层,拖动跟手/发光放大/交互面零变化。
- 死隔离四问: ① ModeTabPicker 为我们接管文件,纯视觉;② 无共享路径;③ tint 用仓内既有先例;④ 回归项 = 浅色白玻璃、深色维持、拖动各态。
- EXIT: 若 tint(.white) 过白/过淡,调为 `.white.opacity(~0.7)` 或去掉 tint 只留 content 修复(两种效果叠加,可单拆)。

### B16-SEND-SMOOTH — 贴底发送零滚动:发送路径竞态收敛(2026-09-17, pp「chatgpt 那种用户发送的文字之后丝滑的效果怎么做的」→「可以」)
- File: `src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`(forceScrollToBottom sink,单处)
- 机制(调研): ChatGPT 丝滑三要素 = ①天然置底(翻转法/锚定插入,无「先插入再滚」两步) ②插入+位移+输入框回缩同一事务同曲线 ③流式直驱不逐帧 scrollTo。本项目已有设施:applySnapshot 尾部在 autoScrolling 时**同帧无动画钉底**;流式生长有 invalidationContext glue(T-ios-stream-natural-transitions);userBrowsing 保护已存在。
- 本批改动: 发送时 forceScrollToBottom 由「永远 animated:true」改为**贴底零滚动**——`isNearBottom()` 为 true 时只用无动画确认(插入已同帧钉底,这一发是幂等保险),真正离开过底部时才用动画带回。消除「apply 同帧 pin × 键盘收起 0.25s × 追滚动画」三方竞争,观感 = 内容从底部顶入(ChatGPT 式)。
- 有意未动: ①apply 尾部的 pin 计算与 80ms coalesced 保险(处理 UIHostingConfiguration 异步测量的 undershoot,历史修复勿扰);②inset 更新路径(已有 T-inputbar-shrink-content-bump 双向 re-pin 修复,成熟);③输入框高度回缩动画(SwiftUI 侧,风险大收益不明,真机看过再说)。
- Semantics: 信号语义零变化(8 处调用点全部受益:贴底幂等/非贴底保留动画);userBrowsing 保护不动;无新增状态。
- 死隔离四问: ① CollectionViewMessageListV3 是本机+远端共用渲染件,改的是滚动行为一处分支,两端同行为(预期);② 无共享文件路径;③ 无新机制(用现有 isNearBottom/scrollToBottomNow 设施);④ 回归项 = 两端:发送(贴底/翻上后)滚动、重试/恢复/回底按钮、流式跟随、键盘收起后位置。

### B16-INPUTBAR — 输入栏:interactive 玻璃放大发亮 + 三图标黑字/#F1F1F1 底 + 圆角(2026-09-17, pp「把输入框改成 claudio 那样放大和发亮…➕号、/号、语音图标改成黑色,背景底色 #F1F1F1…输入框的圆角再圆一点,输入框上面的状态条也圆一点」）
- File: `src/ios/Views/Chat/AIChatView.swift`（单文件）
- 四处:
  1. `ComposerSurface` 输入框玻璃 `.regular` → `.regular.interactive()`（AA ChatComposer 同款配方;按压/聚焦时系统放大 + 提亮）。
  2. `ChatColors.inputIconBg` 浅色 → `#F1F1F1`（深色保持 secondarySystemBackground，避免深色条上泛白贴纸感）;新增 `ChatColors.inputIconFg`（浅色纯黑 / 深色 secondaryLabel）;三颗图标（➕ attachment / ⌗ slash / 🎤 MicButton）foregroundStyle 从 secondaryText → inputIconFg。
  3. 输入框圆角 `20 → 26`（ComposerSurface shape 与 inputBar contentShape 同步）。
  4. Fork 状态条（"Fork to Continue"，浮在输入框上方的毛玻璃条）`.background(.ultraThinMaterial)` 直角 → `in: RoundedRectangle(cornerRadius: 14)`;顺手把 isSuspended 挂起黄条也圆了 12（pp 未点名，留档可撤）。
- Why: pp 与 claudio（AA）输入框对齐——interactive 玻璃是 AA ChatComposer 官方配方;图标黑 / #F1F1F1 是 pp 指定值;圆角是他目测「再圆一点」。
- Semantics: 纯视觉，零删减。三图标 tap 动作、Menu 分支、MicButton 自定义手势、Fork/挂起条出现条件、玻璃绘制路径全不动。
- 死隔离四问: ① AIChatView 本机+远端共用，但只动视觉常数与形状，两端同渲染、无状态分流;② 无共享文件路径;③ interactive 玻璃 = AA 官方配方，图标色/圆角 = 普通 SwiftUI 形状，无新机制;④ 回归项 = 深色模式图标底/glyph 未动（保持原样）、语音波形面板（InlineVoiceInputView）未动、Fork 条文字与动作未动。
- 遗留（pp 已默许）: 深色模式图标底/glyph 保持原样未统一;黄条圆角 12 为顺手改、非点名。

### B16-SWIPE-DIR — 横滑切页的方向分辨改判:速度裁决 + 一次锁存/拒绝 + simultaneous(2026-09-17, pp「左右滑动还是容易滑成上下」→「看业界 chatgpt、claude 怎么精准分辨滑动」→「动手」）
- File: `src/ios/Views/ModeTabs/RootModeTabsView.swift`（pageSwipe 单处）
- 业界调研（2026-09-17）: ChatGPT/Claude iOS 的侧栏 = 左缘 ~20pt 起手 + 跟手 + flick 裁决——**边缘起手带（edge gate）是他们"精准"的第一层**；同一触摸区域内的精准分辨 = UIKit 三件套：`gestureRecognizerShouldBegin`（begin 前用 velocity 裁决）+ `isDirectionalLockEnabled`（锁轴）+ 一次判定不回头。pp 明确不做侧栏，只取"精准分辨"机制。
- 三处改判:
  1. `.gesture` → **`.simultaneousGesture`**: plain gesture 会被 List 的滚动机制 claim 后 CANCEL（B13-SWIPEFIX-2 已记录），判定再准也半路死；simultaneous 全程并行跟踪。
  2. 判定依据 translation → **velocity**: SwiftUI 无裸 velocity，`predictedEndTranslation - translation` 即速度向量（缩放）。累积 translation 被拇指弧线污染（B16-SNAP-ARC 同根），这是"看起来很平的横滑被判成纵滚"的直接原因。1.2× 比率保留（pp 09-16 给的数），语义从位移比变速度比。
  3. **一次裁决 + 双锁存态**: 横向胜 → armed（切页 + pageSwipeArmed 冻列表）；纵向胜 → `swipeRejected`（本手势内彻底退出，列表自然滚）；含糊对角拖到 24pt 按速度主轴强制裁决。旧 36pt translation 闸门（swipeTrigger）删除——速度判定不需要长跑道，12pt 起判。
- 防锁死: `@GestureState swipeInFlight` + onChange 复位（end 与 cancel 都落点，ModeTabPicker B16-GLASS-HOST 判例）；onEnded-only 复位漏 cancel 路径。
- Semantics: 切页能力面零变化（列表区横滑 = 切页，左 Remote 右本机，soft 触感，spring 0.28/0.82）；栅栏零变化（顶栏带/气泡区/listAreaTop）；scrollDisabled 冻结门不变。判得准了，不是判得少了。
- 死隔离四问: ① RootModeTabsView 是我们接管的分叉件，远端不经它；② 无共享路径；③ 无新机制发明（velocity 裁决/方向锁是 UIKit 公认机制的 SwiftUI 等价实现）；④ 回归项 = 纵滚不受影响（rejected 路径）、横滑切页成功率高且不再边滚、tap/行点选不受影响（simultaneous 只在 ≥12pt 拖动激活）、齿轮/胶囊不受影响、已在本页方向滑动（target==mode）仍 armed 冻列表到抬手。
- 真机风险: ① 极慢拖动时 predictedEnd 噪声大（慢速预测量小）——含糊则 24pt 强制裁决兜底；② 极端弧线误判纵为横——velocityRatio 1.2 可收紧。EXIT: 装机若仍偏"易纵"，先调 velocityRatio（1.2 → 1.1）再查。

### B16-DRAG-GLASS — 拖动的胶囊 = 真玻璃本体跟手 + 自绘发光放大（2026-09-17, pp 截图「拖动的那个是灰块…我要的是拖动的那个做玻璃效果发光放大」）
- File: `src/ios/Views/ModeTabs/ModeTabPicker.swift`（单文件）
- 结构改判: 玻璃从「挂在选中段文字上、拖动中静止 + 灰块 ghost 跟手」改为**独立胶囊层** —— `ZStack { GlassEffectContainer { pillLayer }; labelRow }`，文字层是容器**外**的兄弟视图，永远画在玻璃之上（容器只把玻璃合成在**内部**兄弟之上——114541b 盖字事故的机制边界，够不着容器外的视图）。灰块 ghost（`Color.primary.opacity(0.07)`）整个删除。
- 拖动语义: pillLayer 位置由 `interpolatedRect()`（selection.slot + progress，越界阻尼 0.32）自驱，拖动中 1:1 跟手；松手 `withAnimation(settle)` spring 吸附。发光+放大自绘（`dragScale 1.06` + 白高光 sheen 0.22/0.14，colorScheme 分档）——`.interactive()` 在装饰层上不生效（B16-PILL-FEEL 判例），发光放大从来只能自己画。
- 有意放弃: 系统的 glassEffectID 形变（@Namespace/glassEffectID 随单颗玻璃结构移除）。morph 无对象后，点按/松手的切换动画 = settle spring 滑动（Grok 网页 matchedGeometry 同款视觉，B7 时代原效果）。pp 2026-09-17 指令的直接结果。
- 弃用令翻案（留字据）: 2026-09-16「拖动吸附不用触感」只覆盖**触觉**；本次 pp 亲口要回视觉发光放大——不冲突，触觉仍静默。
- 🔴 编译门新判例: availability 检查是**词法**的 —— 调用点的 `if #available` 保护不了 callee 体内的 iOS26 API；`pillLayer` 必须自己标 `@available(iOS 26.0, *)`。旧 TabGlass 靠体内自带分支才过；本批写完自查抓回，CI 前拦截。
- Semantics: 手势面零改动（3pt slop / 方向一次判定+锁存+拒绝 / @GestureState 复位 / didScrub 0.15s / 就近吸附 / 越界阻尼 / onLocalRetap / soft 点按触感全保留）；`<26` 降级 = legacyPillLayer（secondarySystemBackground+描边，SearchBarSurface 家规），能力面持平。真机风险: 玻璃逐帧 offset 的帧率——若掉帧，回退路径 = 拖动中玻璃静止+ghost（B16-SEGMENT-GLASS 形态），台账在此留档。
- 死隔离四问: ① ModeTabPicker 是我们接管的分叉件，远端渲染不经它，零影响；② 无共享文件路径；③ 玻璃配方沿用官方 glassEffect/GlassEffectContainer（仅交互驱动方式改为自驱位置，无新机制发明）；④ 回归项 = 点按切换 spring 滑动、onLocalRetap、纵向让列表、齿轮玻璃不受影响、<26 降级、深浅色两态、盖字不复发。

### B16-GLASS-HOST — 玻璃挂错宿主（40pt 整段 vs 30pt 标签带）+ 拖动永久卡死（2026-09-16, pp「顶部tab又变这样了」「拖都拖不了了」「是那个玻璃没有附在那个上面」）
- **玻璃没附在字上**：`TabGlass` 挂在"整行 40pt 的段"上 ⇒ 胶囊高 40pt（不是量出来的 30pt），看着就是浮在字周围的一块大白片。修 = 修饰符移进 Button 的 label 里、包住 **30pt 标签带**（胶囊贴字，点按热区仍整行，glassEffectID 各段共享 ⇒ 系统形变不变）。
- **拖都拖不了**（两个我的账）：① 方向门"首次含糊即拒绝并锁存"，真手指起手几乎都不是正角度 ⇒ 现在只有**明确纵向**（|dy| > 1.5|dx|）才交给列表，含糊对角允许拖到 20pt 再按主轴判；② 锁存态只在 onEnded 复位，而**手势被取消时 onEnded 不触发** ⇒ 一次取消就永久拒绝。加 `@GestureState gestureInFlight`，结束后**或被取消**都复位 locked/rejected/dragging/progress。
- 门：parse / freeze / import-scan / fork-point / aa-assets 全 rc=0；tip 70d40da。

### B16-CODE-CARD — 代码块卡片 = Claude 式白底黑字 + 头部条（2026-09-17，pp「这是claude的text还是啥卡片 现在我们的卡片是不是黑色的？」→「照这个先出个预览」→「这下对了 落地吧」；两次打回：微灰条没做 + Code 字体没换等宽）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（theme + CodeBlockAttachment.makeView）+ `Views/SettingsSkin/AppSymbolAssets.swift` + 新资源 `Assets.xcassets/aa-Maximize2.imageset`
- 实测取样（pp 截图逐像素/弧线拟合，非猜测）: 浅色 页面#F9F9F7 · 卡片#FFFFFF · 代码字#0B0B0B · 头部分隔线#C9C9C6 · Code 标签#85857F · **圆角 23pt**（左上弧线逐点拟合 R≈69px@3x）；深色 页面#151515 · 卡片#20201F（暖深灰）· 代码字#F0EFEC · 分隔线·图标#5A5957。旧配色（浅 .black+systemGreen 终端风）退役。
- 结构: 固定 36pt 头部条（左 = 等宽 12pt "code"/语言名灰字——实测字形步进均匀 19/20/20px 判定等宽；底 = 全宽 1px 分隔线）+ 右侧双图标按钮（copy=lucide aa-Copy 仓内现成；maximize-2=新资源，与 B16-LUCIDE-ICONS 同源 v1.46.0 管线）。图标 18pt **光栅化**——`UIImage(named:)` 内在尺寸 24pt，UIButton.setImage 无 symbol 配置可缩，必须 `headerIcon` 重绘（不缩会撑大，审查抓回）。
- Semantics: 复制按钮逻辑**零改动**（T-ios16/17 防死双绑+debounce+绿勾反馈全保留，仅图标换 lucide）；语言标签由「仅有语言时 11pt 白字」变为「始终 12pt 等宽灰字（无语言显示 code）」=增强；滚动/流式长高/高度测量未动（topOffset 28/12 → 固定 36）。
- 死隔离四问: ① SelectableMarkdownView 是本机+远端聊天**共用渲染件**——纯呈现层，两端同渲染，无状态分流；② 无共享路径（单文件+资源）；③ 图标走仓内既有 lucide→imageset 管线，无新机制；④ 回归项 = 两端代码块浅/深显示、复制内容正确、内部横竖滚动、流式长高、MarkdownRenderView 路径（编译面）。

### B16-CODE-FULLSCREEN — 代码块全屏查看器（2026-09-17，pp「我们有全屏观看吧」→ 查证仓内无 → 新建）
- File: 同文件新增 `CodeBlockFullScreenView` + `CodeFullScreenText`；`Views/Chat/AssistantBlockView.swift` 接线（ExpandedCodePayload + @State + fullScreenCover）
- 链路: `CodeBlockAttachment.onExpand` → `SelectableMarkdownTextView.onExpandCode` → `SelectableMarkdownView.onExpandCode` → AssistantBlockView 呈现层。**nil handler（分页/文件预览等 standalone）时展开按钮自动隐藏**，不生造死按钮。
- 内容: 全屏可选中可复制；顶栏关闭 + 复制（同 debounce 反馈）；字号跟随 FontSettings；着色与卡片**同源**（共享 CodeSyntaxHighlighter）；深浅同卡片配色（presentationBackground 跟随）。
- Semantics: 纯新增功能面；既有显示/交互零删减。
- 死隔离四问: 同 CARD（共用渲染件呈现层新增）；④ 回归项 = 展开→全屏→关闭、长代码滚动、复制、深浅两态、standalone 场景按钮隐藏。

### B16-CODE-HL — 语法高亮（Grok 色板，自研 tokenizer）（2026-09-17，pp「claude的部分是单色部分是有高亮的 不知道咋区分的」→ 语言围栏机制确认 →「高亮颜色用 gork 的颜色」）
- File: 同文件（theme 增 6 个 hl* 双态色 + `CodeSyntaxHighlighter` ~340 行）
- 实测色板（Grok 浅/深截图逐 token 取样，apple-vision OCR bbox 对齐语义）: **浅色** 标签·选择器#4880B8 · 属性名·at-rule#7068A8 · CSS 属性名#D05828 · 字符串·数字#50A058 · 注释灰（#8A8A86）；**深色** 标签·选择器·属性名#A0C8F8 · CSS 属性名#F8F8B8 · 字符串#B8F870 · 数字#E878F0 · 注释#808060。⚠️ **深浅两套色相映射不同构**（浅紫/深蓝、浅橙红/深黄、数字浅绿/深紫粉），照抄不换算。
- 机制: **语言围栏驱动**——有语言标记 → 按语言着色；裸围栏 → 单色（= Claude/Grok 的"部分单色部分高亮"行为）。覆盖 json / html·xml·vue / css·scss / swift / python / js·ts / go / sh bash / yaml / java·kotlin·c·cpp·rust·php·cs·dart / sql；HTML 内嵌 `<style>`/`<script>` 递归按 CSS/JS 规则着色；未知语言/裸围栏回退单色。**纯 Foundation 自研，零第三方依赖**（仓规：Apple 原生 + 不用第三方高亮库）。
- Semantics: 单色 → 多色（回退路径完整保留）；高度测量仍走单色路径（颜色不影响尺寸）。
- 真机风险: 大代码块流式重渲染的 tokenizer 成本（O(n) 单遍，但 `paint` 的 Range→NSRange 转换每 token O(n) ⇒ 最坏 O(m·n)）。若真机卡：加 attachment 级 attr 缓存（contentFingerprint → NSAttributedString）。EXIT。
- 死隔离四问: 同 CARD；④ 回归项 = 两端 json/html/swift/sh 着色（浅/深）、裸围栏仍单色、HTML 内嵌 style 高亮、全屏着色与卡片一致。

### B16-CODE-FONT — 代码块字体 = Geist Mono Medium（2026-09-17，pp「这个字体是只作用于这个吗 正文的字体会不会影响？」→ 边界确认「可以」→「用claude吧」）
- File: 新资源 `src/ios/Views/Chat/geistmono_medium.ttf`（vercel/geist-font v1.7.2 release 官方包，PS name 实测 = `GeistMono-Medium`，手写 TTF name 表解析确认）+ `src/ios/Minis.xcodeproj/project.pbxproj` **四处纯插入**（照 caveat_wght.ttf 先例：BuildFile/FileRef/Views-Chat 组 children/Resources phase；手术脚本断言链 = 锚点唯一×4 + 括号·括号·方括号平衡 + ID 计数 + 纯插入行集校验；**xcodeproj gem 验证 files=668**）+ `Views/AuthAA/AppFontRegistry.swift`
- 注册: AppFontRegistry 追加 **nonisolated** `geistMonoMedium(_:)`（lazy 自注册，`nonisolated(unsafe)` flag）——`codeBlockFont` 会被非隔离的 TextKit 路径调用，做成 @MainActor 会编译炸；**@MainActor verbatim 部分（Caveat）零改动**。失败策略：Geist **软失败**（log + Menlo 兜底，打包闪失不崩聊天），Caveat 保持 fail-fast verbatim。
- 边界（pp 确认）: 只作用于**代码块 + 全屏查看器**；正文 / 行内代码（SF Mono Medium ×0.95 #FF6A00）/ UI 一律不动。三级兜底 Geist→Menlo→monospacedSystemFont，PingFang SC cascade 保留。
- 死隔离四问: ① 字体注册器为 app 级全局工具（Caveat 既有先例），Chat 引用为同 target 常规使用；② 无共享路径；③ 无新机制（CTFontManager 官方 API，照抄仓内先例）；④ 回归项 = 两端代码块渲染、**正文/行内代码/UI 字体零变化**、Caveat wordmark 不受影响、字体缺失场景 Menlo 兜底。

### TRR — 「新版」工具渲染皮肤（Grok 式工具活动复刻，批 0/A/B/C/E，2026-09-17）
pp 拍板：完全 Grok 式（聊天内 thinking=入口行零展开）、阶段级汇聚、皮肤名「新版」默认新版双端生效、玻璃工具条开关新增、图标=Lucide（memory 保持 SF brain.head.profile、thinking=sparkles）、事件/文案全用 moonveil 自己的（零新事件源，数据层零改动）。

**新增（8 文件 + 1 imageset，`Views/Chat/ToolActivity/`）**：
- `ToolRenderStyle.swift`（N1）：classic/new 枚举 + ToolRenderStyleStore（object(forKey:) 读防 implicit-0 陷阱）+ GlassToolBarStore + `.toolRenderStyleChanged` 通知。默认=.new（H1）。
- `TurnActivityAggregator.swift`（N2）：纯函数分段器（thinking 开段+连续 tool 归段+text/info 截段+无思考头兜底）。19 项断言测试服务器全绿（/tmp/batchA）。
- `ToolActivityGroupView.swift`（N3）：槽状态机（运行=点阵+计时+事件行 suffix(2)；完成=入口行「Thinking ›」单向永留）+ 段级计时（0.7s 无计时→1Hz 起跳，起点存视图层 static 缓存 keyed anchorId）+ shell 停止按钮透传 + onChange(segment)→.thinkingBlockToggled 高度失效复用。
- `ThinkingDotIcon.swift`（N4）：3×3 点阵 TimelineView+Canvas（绕圈0.9+收拢0.3+休止0.4=~1.6s，帧级实证参数）。
- `ToolEventRow.swift`（N5）：事件行（文件类=黑 semibold+mono #F2F2F4 pill；命令类=灰 #7C7C81）+ ToolEventRowFactory（文案复用 ChatModels 既有 fallback）+ ToolActivityIcon（Lucide 键+accent 色映射）。
- `ShimmerText.swift`（N8）：慢扫光（呼吸型 0.5s/波+2.6s 周期+3s 首扫延迟，仅 sheet——聊天内实测无扫光）。
- `ToolCardView.swift`（N7）+ `CometSpinner`（B7 1.4s/圈彗星）：描线卡 #F3F3F3+#E8E8E8 描边+13pt 圆角+copy 按钮+折叠 chevron 旋转。
- `ThinkingDetailOverlay.swift`（N6）：自绘 overlay（无缩放无模糊+flat 22% dimming）+双 detent（45%/7%）拖拽吸附+grabber 47×4+思考行状态跟随+点击展开思考原文（尾部渐显 A6）+时间线竖线 2pt #E3E3E1+卡缩进 8pt。
- `Assets.xcassets/aa-FilePlus.imageset/`：Lucide file-plus（E 批 file_write 用）。

**修改（9 文件）**：
- `AssistantBlockView.swift`：body→皮肤分发（new=锚点渲染组/非锚点空；text/info 与 classic 同）；原 switch 整体改名为 classicBody **字节零改动**（python 平衡扫描+逐字节等价证明已跑）；+@AppStorage 皮肤观察（H3 双路径即刷）。E 批：file_write icon 键 doc.text.fill→doc.plus（**有意改动**——SELECTION 全局换版拍板覆盖 classic 冻结范围，仅此一处）、statusOrIcon→AppSymbol（memory SF 特例+未知键兜底 SF）、ThinkingIcon→sparkles ×2。
- `ToolLiveSheet.swift`：FloatingToolBar 加 `floatingToolBarEnabled` 总开关（body→bodyContent 拆分，H7 两版通用）+ toolIcon switch 换 AppSymbol。
- `AIChatView.swift`：+ToolActivityDetailContext/@State + fullScreenCover(item:)（presentationBackground(.clear)+interactiveDismissDisabled）+ .toolActivityDetailRequested 通知接收（messageId 归属校验防多实例误弹）。
- `CollectionViewMessageListV3.swift`：+.toolRenderStyleChanged 订阅→全量高度缓存失效（照 handleAttachmentSizeChanged 三步姿势）。
- `ContentView.swift`（AppearanceSettingsView）：+Tool Rendering Picker（classic/new，经 store 写入+发通知）+ Glass Toolbar Toggle。
- `ConfigRegistry+Builtins.swift`：+chat.toolRenderStyle（IntCodedEnum defaultIndex 1）+chat.glassToolBar。
- `AppSymbolAssets.swift`：+手动映射 "doc.plus"→"aa-FilePlus"（标注：重新跑 sync-symbols 需把 file-plus 加进生成源）。
- `ModelGroupDetailView.swift`：ThinkingIcon→sparkles。
- `Minis.xcodeproj/project.pbxproj`：+ToolActivity 组（8 文件挂载，脚本手术+括号平衡+xcodeproj gem 严格解析双过）。

**StatRow 处 ThinkingIcon 已换（E2 补批，pp 令 2026-09-17）**：`StatRow.customIcon` 从 `Image?` 放宽为 `AnyView?`（private struct，仅本文件 8 处调用，其余 7 处不传参零影响），Thinking 行 → `AnyView(AppSymbol("sparkles", 14))`。ThinkingIcon 代码引用全域清零（资产文件保留未删）。

**死隔离四问申报**：①两端影响=AssistantBlockView 是本机+远端共用渲染件，皮肤分支对两端同行为（预期且 pp 拍板 H5 双端）；数据层/Agent 逻辑/事件源零改动。②共享文件 gate=classicBody 字节等价证明+glassBody 拆分零行为变化+AppSymbolAssets 纯插入；class 皮肤下唯一视觉变化=图标 Lucide 化（pp 全局拍板）。③官方等价物=AppSymbol 体系（上游 sync-symbols 管线+89 资产已覆盖 9/10 所需图标，仅新增 FilePlus）；通知/高度失效/设置项均复用现有通道与先例。④回归项=两端：classic 皮肤渲染零变化（图标除外）/new 皮肤全功能/皮肤切换往返/玻璃工具条开关/小窗预览开关/工具执行/stop/重跑/记忆撤销/汇聚页交互。

**待 pp/装机**：A10 产物卡生命周期（存疑）、A9 输入框三态（超出本域未做）、任务卡对应物（不做）、思考行完成态文案（初值=Thinking）、滚动条/顶部滚动行为（默认标准实现）、慢扫光/detent/折叠时长/dimming 精确参数（装机校准）、StatRow ThinkingIcon。

### B16-TABLE-ALIGN — 表格单元格统一左对齐（2026-09-17，pp 装机反馈「表头两列左两列右」+ Claude 基准截图 photo_8FD01B78）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（TableAttachment cell 循环，一处）。
- Why: 模型给数字列写 `---:`/`:---:` 对齐标记，渲染器自上游开源版以来忠实跟随 → 表头行出现 2 左 + 2 右混排（pp 装机反馈 photo_654DA3AB）。Claude app 的表格无此混排，全部左对齐。
- Fix: 单元格 alignment 统一 `.left`（表头与数据同规则，一处 switch → 直接赋值）。
- 回归: 文本表（应无变化，此前即全左）/ 含 `---:` 标记的数字列表现在全左 / 表头 semibold 不变 / copy-as-image 同源。

### B16-TABLE-FONT2 — 表格字号 0.9× → 1.0×（=正文，2026-09-17 pp 再拍板）
- File: `src/ios/Views/Chat/SelectableMarkdownView.swift`（`tableCellFontSize`，一处）。
- Why: pp 装机对照 Claude（photo_B78EF524）问「claude 的表格字体大小和正文是不是一样的」→ 实测确认一样大（表格数据墨高 42px vs 正文 41px @3x；表头同尺寸仅加粗）→ pp「改」= 与正文同大。
- 覆盖: B16-TABLE-FONT（0.9×「低正文一档」，同日撤销）。
- 回归: 行高/内距动态计算（`boundingRect + cellPaddingV*2`）无 0.9 硬编码依赖; 字号滑杆仍跟随 baseFontSize; 表头 semibold 不变。

### AGG-SHEET-V3 — 汇聚页第三轮：对齐 Grok/Claude 全套改判（2026-09-18，pp 指单链 photo_CF243117 → photo_353E81A2 → photo_2F211FE1 → Claude 纯思考截图 →「有工具的话这里应该是 Thought 了多少s」+ 错误重试计时冻结）
- **Files**: `Views/Chat/ToolActivity/ThinkingDetailOverlay.swift`（重写）、`ToolCardView.swift`（重写）、`ToolActivityGroupView.swift`（ThinkingRunClock 三态 + ThinkingElapsedText + 接线）。
- **视觉规格（photo_353E81A2 / photo_2F211FE1 @3x 逐像素实测）**：
  1. sheet 底 #F3F3F3 → **#F5F5F5**；顶部标题改 13pt semibold #6E6E6E 居中（有工具=「思考结果」/ 纯思考="Thought for Ns"）；抓条间距 4→16（fd7875f 已半做）。
  2. 描边卡：底=#F5F5F5（同 sheet，不浮起）+ 1px 描边 #EBEBEB（strokeBorder）+ 圆角 28；标题 13pt semibold、图标近黑（视觉 15pt；SF 15 / AppSymbol 17）、copy 16pt 视觉（size 18、热区 32）；完成态去 chevron（折叠手势保留：点标题行）；分隔线 #DCDCDC；mono 内容 #111；标题行 v-padding 12（行高≈42pt）；内容 pad top 16 / bottom 14。
  3. 无输出工具 = **✓ 完成行**（SF checkmark 12pt #7A7A7A + 12.5pt #3D3D3D 标题，行高 22）；有输出/运行中 = 描边卡（运行中永远卡+spinner，防流式闪烁）。
  4. timeline：贯穿长线 → **项目间短竖线段**（1.33pt×5.5pt #DCDCDC，gutter 列居中 x≈25.7pt）；gutter 12 + gap 7 + 卡额外缩进 11（卡左缘 x≈49.3pt）；行距节奏 22+14=36pt（Grok 实测 36.3）。※ 短线段精确起止（上 10.3/下 16.7pt）为近似值，装机校准。
  5. 纯思考段（无任何工具）= **原文衬线直展**（.system 15.5 serif 纯黑、无折叠行 / 无 timeline / 无 chevron），流式尾部渐显 [A6] 保留。
- **计时三态**（pp：「模型问题弹出重试，思考时间还是继续记秒。点继续之后正确逻辑是什么」→ 拍板 冻结/续走）：`ThinkingRunClock` 增 `pause/resume/settle/frozenValue`——错误出现冻结显示（不涨）、重试续走（暂停时长折入 offset 平移，数字不回跳）、阶段完成落定终值（错误等待不计入「Thought for Ns」）；接线 = `message.error` / `segment.isDone` 两处 onChange。旧消息无落定值 → 阶段行 fallback "Thought"、纯思考标题 fallback「思考结果」。
- **回归**：运行槽秒数连续（无错误不冻结）/ 错误冻结不涨 / 重试从原值续走 / 完成后打开 sheet 取落定值 / 多段消息各段独立 / 本地+远端会话同路径（AIChatView 单宿主 [H5]）。
- **死隔离申报**：三个文件均为 B16 后自造渲染件（非上游 verbatim 范围）；零数据模型/协议/生命周期改动（ChatModels.swift 未触碰）；计时为纯视图层内存态（app 重启/消息重载后无时长 → fallback 生效）。
- **有意保留待验**：无输出工具暂定 ✓ 行（灰胶囊留给未来系统级事件）；「✓ 完成」尾行未加（Grok 图C 有，待 pp 拍板）；短线段/行距微观值装机校准。

### CLOCK-FIT-V2 — Claude 时钟图标参数替换（2026-09-18，pp：「把这个替换你手写的那个时钟，颜色改成现目前那个灰色」）
- File: `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（ClaudeClockIcon，一处）。
- 来源: photo_8E721157.png 像素级拟合（18 参数坐标下降优化，软 IoU 0.951；存档 shared/claude-clock-svg/fitted2.json + SVG 双版本 + compare.png）。
- 参数（24 画布，外缘=12 撑满）: 环中径 10.6438 / 线宽 2.7123；缺口弧 264.7046°→527.6624° 顺时针圆头（缺口 97°）；三点等大 φ2.9256 @ 190.356/215.060/239.836°（R 10.2809）；指针折线 (11.2483,6.9451)→(11.4659,12.4278)→(16.0784,14.3009)。
- 覆盖: photo_25B6FFE9 初版（252°→186° 弧 / 递进三点 2.5-1.9-1.4 / 线宽 2.0）——以新版拟合为准。
- 颜色: 不变（调用点 headlineGray #7A7974 暖灰）。
- 回归: 入口行时钟灰/16pt 不变；形状对照 photo_8E721157 装机并排；classic/new 皮肤同路径（无皮肤分支）。

### AGG-OVERLAY-HOST — 汇聚页翻页浮层宿主修复（2026-09-18，pp 装机截图「弹出来的动画是这样的」）
- **Files**: `src/ios/Views/Chat/AIChatView.swift`（浮层挂载点迁移 + toolbar 可见性 + topInset 传参）、`src/ios/Views/Chat/ToolActivity/ThinkingDetailOverlay.swift`（topInset 属性 + 整体下移预留）。
- **根因**: 浮层原挂 `inputPopupOverlay.padding(.bottom, inputBarHeight)`（斜杠/提及弹出菜单容器；空闲时 0 尺寸）。`.overlay(alignment:.trailing)` 下浮层以「容器 trailing 边 = 屏幕中线、容器高 ≈ 输入栏高」落位 → 整页被压成 ≈393×147pt 板块，从右滑入后停在屏幕左下 [0..196]×[705..852]pt（与 pp 截图逐像素吻合）。`move(edge:.trailing)` 转场本身正确，**宿主尺寸错**才是病灶（#117 跳转 bug 掩盖了它，c30c2e6 修复后首次真正可见）。
- **Fix**: ①挂载点移到 body 根 ZStack（kernelBootOverlay 同级，屏幕级宿主）→ 恢复「全屏、从右推入/右滑出」；②`topInset`（承接 `topSafeAreaInset`，刘海/灵动岛机型常态 59）整体下移，列表头部与详情页头部共用一处预留；③浮层打开期间隐藏本页原生导航栏（浮层自带返回钮；原生返回 = pop 会话，语义冲突），关闭自动恢复。
- **回归**: 入口行点击开浮层（列表/纯思考两形态）/ 详情 push/pop / 返回钮关闭 / 原生栏隐藏与恢复 / 聊天页滚动输入不受影响 / classic 皮肤不受影响（浮层仅 New 皮肤路径）。
- **死隔离申报**: ①两端=AIChatView 本机+远端共用容器，只改「浮层展示宿主与顶栏可见性」，两端同行为（预期）；数据/会话/工具流/事件源零改动。②共享 gate=不触导航栈状态机（toolbar 可见性为声明式开关）；转场/内容语义未动。③官方等价物=toolbar(Visibility) 系统原生 API；宿主=既有屏幕级 ZStack 结构。④回归项=两端如上。
- **装机重点验证**: 原生栏隐藏/恢复（本机制首次启用）；浮层顶部留白观感（59 基于 topSafeAreaInset 常态值）；翻页速度/曲线如需微调在 0.28s 一处。
- [2026-09-18 三改] ⤴ 本方案已被 **AGG-SHEET-RETURN** 取代（pp 拍板回原生 sheet）；留档备查。


### AGG-SHEET-RETURN — 汇聚页回归原生 sheet（Claude 1:1，2026-09-18 pp 拍板「1:1复刻修改…用原生的东西」）
- **Files**: `src/ios/Views/Chat/AIChatView.swift`（撤回全屏 overlay → `.sheet(item:)` 原生从下弹起；删 nav 栏隐藏与 topInset 传参）+ `src/ios/Views/Chat/ToolActivity/ThinkingDetailOverlay.swift`（删 topInset；头部返回钮 → X 关闭钮；行尾 chevron 收窄；运行中图标改点）。
- **依据**: pp 参考图 photo_32363DEB（Summary sheet：系统抓条 / 左上白圆底 X / 居中标题 / 时间线列表 / 底部 Thinking… 灰点行）+ photo_3F81BF3F（详情：白圆底 < 返回 + 左标题 + Input/Output 代码卡）+ pp 字面流程「从下弹起 → 汇聚页 → 有输出的点进去 → 切页从右滑出新页」。
- **规格（逐像素实测）**: sheet 顶边 ≈0.69 屏高 → `presentationDetents([.fraction(0.69), .large], selection:)`（钉住防横跳）+ `.presentationDragIndicator(.visible)`（系统抓条）；头部行心 ≈38pt 距顶（44pt 白圆钮 → 上内距 16）；chevron 仅「有输出/运行中的工具行」（思考行保留可点、无箭头）；运行中当前项 = 普通灰点 7.3pt（撤 CometSpinner 展示）。
- **supersede**: 取代 AGG-OVERLAY-HOST（ffee261：屏幕级宿主 + 全屏 move(.trailing) + nav 栏隐藏 + topInset）。详情页保留 sheet 内 ZStack 从右切页（c30c2e6）。
- **回归**: 入口行点开（完成/运行中）/ 纯思考全文 / 详情 push/返回 / X 与下拉两种关闭 / detent 拖动防横跳 / classic 皮肤零影响。
- **死隔离申报**: 仅 New 皮肤汇聚页路径；数据/会话/工具流零改动；自绘面缩小（回系统 sheet/grabber/detents/dimming）。
- **待装机**: ①标题文案保留动态版（思考结果/Thought for Ns/Thinking…），参考图为固定 "Summary"——要 1:1 固定词说一声；②运行中灰点若 Claude 实为脉冲动画，可一行加。

### SHIMMER-V2 — Thinking 扫光 v2：TimelineView 帧驱动 → mask 位移 + repeatForever（2026-09-18，pp 装机反馈「tinking 还是没有扫光」）
- File: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`（SweepTextShimmerModifier 重写；API `sweepShimmer(base:period:)` 不变）。
- 根因: v1 用 TimelineView(.animation) 每帧重建 foregroundStyle 渐变——聊天流 cell（UIHostingConfiguration）里 display-link 闭包不驱动（同环境 withAnimation 系动画正常，pp 实证文字滑入有、扫光无）。汇聚页标题同 modifier 一并失效。
- v2: 峰色文字层 + 移动窄带 mask（Rectangle fill clear/white/clear 渐变，带宽=max(0.5×文字宽,28)，PreferenceKey 量宽）+ offset 由 withAnimation(.linear 3s repeatForever) 驱动；端点停顿用带子滑出视野外空程近似；峰色 = color-mix(base 30%, white)，alpha 同式 0.3a+0.7（修 v1 丢 alpha 的偏差）。
- 回归: 运行槽 "Thinking" 扫光（静止态 = base 灰不变）/ 汇聚页标题扫光 / 文字选中复制不受影响（峰层 allowsHitTesting(false)+a11y hidden）/ 深浅色模式（峰色跟随 base 动态取色）。
- 死隔离: ShimmerText.swift 为自造渲染件（非上游 verbatim）；零数据/生命周期改动；旧呼吸式 ShimmerTextModifier 保留未动。

### GROK-CAROUSEL — 工具行轮播 push 动画（Grok 1:1，2026-09-18 pp 拍板「开始吧」）
- **File**: `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（+50/−1；无新文件、无 pbxproj 改动）。
- **依据**: Grok 录屏 video_CDFAF826.mov 60fps 逐帧拆解（服务器 ffmpeg+PIL+kymograph）：垂直轮播队列——新行从视口下一个行距处上滑进场（opacity 0→1 ≈0.25s + blur ~2.7pt→0 ≈0.35s，清晰化晚于淡入收尾），存量行同曲线上移一个行距（0.42s 前载 ease-in-out 无过冲，t=0.2→41%/0.4→83%/0.6→99%），最老行跟队上滑+淡出+变糊，到头部区前近透明；两次事件轨迹逐帧一致=确定性固定参数。
- **Fix**: ①删行级 `.transition(.opacity.animation(easeInOut 0.35))`（旧=原地淡入，无队列位移）；②新增 `ToolRowCarouselTransition`（ViewModifier 三态：enteringActive=+pitch/opacity0/blur4、exitingActive=−pitch/opacity0/blur4、settled）挂 `.transition(.toolRowCarousel)`（asymmetric）；③容器 `.animation(Self.carouselSpring, value: eventBlocks.map(\.id))` 一轨驱动——ids 增删时存量行布局位移与进/离场转场同轨同弹簧（`.smooth(duration:0.42)`=bounce 0，iOS17+，目标 26.2）。pitch=38（行高~20+spacing18，Grok 实测 36pt）/blur=4 集中一处装机可调。
- **已知差异（留痕）**: 单事务插入≥2 行（罕见突发）进场 offset 恒 38pt 不按行数倍增（流式每事务一行，常规路径无影响）；离场行 z 序在 header 之上靠淡出规避压字（t≈60% 已 ~0.15，Grok 同为软淡出无硬裁剪）；不复制 Grok 的 1 帧插帧延迟。
- **回归**: 事件行进场（1→2→3 成长段与 3→满轮播段）/ 离场行方向速度 / 运行槽整体点开汇聚页（外层 Button 不变）/ stop 内层按钮 / 计时+扫光不受影响（自驱 withAnimation）/ 段完成 entryRow 0.25s 交叉淡变不变 / classic 皮肤零影响（本组件仅 New 皮肤路径）。
- **死隔离四问**: ①本机+远端共用此视图，动画变化两端同行为（预期非污染，B15-CODE2 同判例），数据/会话/工具流/聚合器签名零改动；②共享路径 gate=改动圈定 runningSlot ForEach 一处+文件内新增两个 internal 类型，未触状态机/协议字段；③官方等价物=SwiftUI 原生 transition/animation/blur/offset（Apple 原生优先，无自绘引擎）；④回归项两端一致如上。

### FIRE-SLIDER-SELFDRAW — Effort 滑块自绘 thumb + 帧率无关火焰（2026-09-18，pp 装机 4 bug）

pp 装机 Ultracode 预览页反馈 4 个 bug：thumb 是圆球（应为圆角方块）、
thumb 到不了最右、白色拖动球颤抖、"Ultracode" 文字截断成 "Ultraco..."。
死隔离：全部在 Settings/ 呈现层，两端同视图同变化=预期。

**根因与修法（判例可复用）**：
1. **圆球**：UISlider 在 iOS 26 无视 setThumbImage，回退默认圆形玻璃
   thumb（实测无平直边/超出轨道/无白渐变）。弃 UISlider → 自绘
   EffortSlider（SwiftUI GeometryReader + DragGesture），thumb 用
   RoundedRectangle 圆角方块。**判例：iOS 26 自定义 thumb 形状只能自绘，
   setThumbImage 不可靠**。
2. **到不了最右**：旧 45pt 透明画布 thumb 图把 UISlider 行程缩短，
   球右缘悬空 8pt。自绘后 thumb 中心 = thumbSize/2 + progress*(width -
   thumbSize)，value=100 右缘贴轨道右端。
3. **颤抖**：弃 UISlider 后消除其坐标回写/玻璃渲染竞态；方向锁存
   （水平拖动锁定，dy>6&&dy>dx 时留给 ScrollView）防滚页误改值；
   minimumDistance:2 + 有位移才锁，纯点击不设值。
4. **Ultracode 截断**：内容区 320pt 足够但文本被压 → statusText 加
   .fixedSize() 钉固有宽度。判例：HStack 里 Text 被压出省略号先量
   内容区宽度（够却截 = 加 fixedSize），不是字体/字号问题。

**引擎 v2（pp 批准合并）**：SimUniforms 加 u_dt，decay 改 pow(0.90,u_dt*60)
帧率无关（60fps==参考 0.90/帧）；FireRenderer 加 lastFrameTimestamp 算
uDt（下限 1/120 防后台恢复爆 pow）+ 高刷 CAFrameRateRange(60,120,120)
+ comp 管线 bgra8Unorm_srgb（防色调发灰）；FireCanvasView 同步 sRGB。

commit 3f81b1a。装机验证：拖动贴端/状态翻转/火焰燃起/滚页不受干扰。

### GROK-CAROUSEL-FIX + THINKING-START-FIX — 轮播不播/Thinking 消失只剩点阵/扫光不可见三连根因修复（2026-09-18 pp 装机反馈「全链路找证据链」拍板）

- **File**: `ToolActivityGroupView.swift`（+81/−11）+ `ShimmerText.swift`（+42/−41）；无新文件、无 pbxproj、无数据/聚合器改动。
- **根因链（全链路取证）**：
  1. **轮播不播**：cell 宿主挂 `.transaction { $0.disablesAnimations = true }`（CollectionViewMessageListV3 1266/1292/1316/1332 四处，防 ViewGraph use-after-free）→ 子树内**隐式**动画（`.animation(_:value:)`/`.transition` 默认事务）全被吞 → 行插入删除瞬时完成。仓内先例自证：ToolSheetPresenter 注释「avoids the cell's disablesAnimations which would suppress the sheet's slide-up animation」。对照实证：withAnimation 显式事务（两段式 D 出现）不受影响。
  2. **Thinking 消失只剩点阵**（双根因）：①**传播断**——流式 delta 只写 `thinkingContentBuffer`（非 @Published），`content` 节流 flush（0.3~1.5s）后发的是 **AssistantBlock**.objectWillChange；本视图只订阅 message，blocks 数组是引用、引用不变 → message 永不发通知 → `thinkingHasStarted` 在纯思考阶段零重估时机（展开的思考块能实时显示正因它订阅 block 本身）；flush 处的 publishUnlessTransitioning()（vm 级）因本视图未订阅 vm 而够不着。②**状态丢失**——cell 重建（滚动回收/config 替换）重置 @State textAppeared=false，onAppear 不补查当前值，onChange 只监听「变化」（true→true 不触发）→ 已开始的思考永远只剩点阵（startedAt 有 static cache 对付重建，textAppeared 没有——「有时候消失」的来源）。
  3. **扫光不可见**：①被根因 2 遮蔽（挂在 Thinking 文字层，opacity 0）；②独立实现 bug——v2 用 onPreferenceChange 回传量宽，该重算不在动画事务里 → offset 目标从 ±travel(0) 跳到 ±travel(真实宽) → repeatForever 循环被替换、带子静止在左缘外永久不可见。**修正旧判例**：v1「TimelineView 在 cell 不驱动」不成立——ThinkingDotIcon 同用 TimelineView(.animation) 在同 cell 一直工作；v1 真因是峰色 alpha 计算丢 alpha（f1f009e 自己也写了「修了 v1 丢 alpha 的偏差」）。
- **Fix**：
  ① 轮播改**显式驱动**：`@State carouselIds` + `onChange(of: eventBlocks.map(\.id))` 里 `withAnimation(carouselSpring)` 更新，`ForEach(carouselIds)` 内现查 eventBlocks（离场行 id 出 suffix(3) 窗口 → if let 失败 → removal transition 自然触发）；删旧隐式 `.animation(value:)`。onAppear 首渲染直接落位（历史行不播插入动画）。
  ② thinking 判定三路汇合到幂等 `markThinkingStartedIfNeeded()`：onChange(segment 变化路径) + **ThinkingFlushWatcher**（零尺寸 overlay 子视图，onReceive 段内首个 thinking block 的 objectWillChange = flush 落地时刻）+ onAppear 补查（cell 重建后 @State 重置的解药）。判定改双读 `!content.isEmpty || !thinkingContentBuffer.isEmpty` 消除 flush 滞后。
  ③ 扫光 v3：GeometryReader 在 body 内**同步**读尺寸（不经 @State/preference 回传）+ `w>1` 启动门——循环启动时 travel 已是真实值、此后尺寸不变 → 循环永续；guard !sweeping 防重复启动。峰色/mask/API 全保持。
- **回归**: 轮播进场/离场/存量行位移（1→2→3 成长段与 3→满轮播段）/ 运行槽点开汇聚页 / stop 内层按钮 / 计时+扫光 / 段完成 entryRow 交叉淡变 / Thinking 文字+计时在纯思考阶段出现且滚动往返后不消失 / 汇聚页标题扫光（第二调用点同受益）/ classic 皮肤零影响 / ThinkingRunClock 三态与 startCache 未动。
- **死隔离四问**: ①两端共用渲染件，动画/判定变化两端同行为（预期非污染，B15-CODE2 同判例）；②改动圈定两文件的呈现层（@State/onChange/overlay watcher/量宽方式），零状态机/协议/数据流改动；③官方等价物=SwiftUI 原生 withAnimation 显式事务/GeometryReader/onReceive（Apple 原生优先，无自绘引擎）；④回归项如上，两端一致。

### CLOCK-ARC-DIR — 时钟主弧方向修复（CC，2026-09-18，pp 装机截图「现在这个图标和我预览的不一样」）
- **File**: `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（ClaudeClockIcon；1 词 + 4 行注释。无新文件、无 pbxproj、无数据/聚合器改动）。
- **根因**: `Path.addArc(264.7046°, 527.6624°, clockwise: true)` —— **SwiftUI 的 `clockwise` 与直觉相反：`false` = 角度递增路线**。递增才走 264.7°→(跨 0°)→527.66° 的 263° 主弧；写 `true` 走递减，264.7°→167.66° 只跨 97° —— **把「缺口」当主弧画了出来（缺口与主弧互换）**，主弧（顶→右→底→左下）整段不渲染。CLOCK-FIT-V2 的拟合参数本身正确，错在渲染 flag（参数对 ≠ 画出来对）。
- **取证（像素量测定案，可复用）**: pp 截图暗像素连通段中心线最小二乘圆拟合 → 圆心 (71.4, 76.2)、R=21.06（残差 rms 0.36px）、**角度范围 164.6°→264.7°（≈97°，正是缺口段）**；再按 16pt@3x 换算（u=1.98px/单位，画布 47.5px）逐项比对：指针竖杆 x=70.0（应 69.9）、臂末 (79.5, 82)（应 (79.5, 80.8)）、三点 215.1°/190.4° 落点误差 <0.3px —— **尺寸/颜色/指针/三点全对，唯弧错**。同参数渲"坏/好"两版并排：坏版与 pp 截图形状逐像素吻合，根因锁定。
- **旁证**: `src/ios/Views/ContentView.swift` 的 FolderSegmentBorder（圆角矩形，装机显示正常）用 `clockwise: false` 画 180°→270° 的 90° 角 —— 方向语义反证。全库 `addArc` 仅 3 处，第三处 CometSpinner 为单帧小段（0.09 rad）方向无关，已核不受影响。
- **Fix**: `clockwise: true` → `false` + 注释（写明语义、判据、旁证，防复发）。
- **回归**: 入口行 16pt 时钟环完整（顶→右→底→左下 263°，圆头端点）/ 缺口左上三点位置与直径不变 / 指针折线与线宽不变 / 颜色 headlineGray 不变 / classic 皮肤同路径（无皮肤分支）。
- **死隔离四问**: ①两端共用自造渲染件，纯几何常数，两端同行为；②改动圈定单个绘制调用，零状态/数据/协议/生命周期改动；③官方等价物=SwiftUI 原生 `Path.addArc` 方向参数（无自绘替代）；④回归项如上，两端一致。
- **验证**: pp 复核对比图确认「现在对了」（2026-09-18）。**装机复验待出包**：出包后看入口行时钟环是否完整、缺口三点位置是否在左上。

### NEWSKIN-HEIGHT-ESTIMATE — 新皮肤高度估算对齐（滚动卡顿 + 画面来回跳的根因）（CC，2026-09-18，pp 真机日志实锤）
- **File**: `src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`（+90/−2：seed 段 + `estimateItemHeight` + 新增 static helper/常量；无新文件、无 pbxproj、无数据/聚合器/协议改动）。
- **症状**: pp 装机——聊天页「往上滑一顿一顿的、有时候画面来回跳，agent 没在回复也这样」。
- **根因（真机日志直证）**: 新皮肤把 thinking/工具块收进「活动槽」渲染，但高度估算表还是**经典皮肤的值**：
  - `AssistantBlockView.newStyleBody`：`text`/`info` 走 classicBody；`thinking` + 全部工具类走 `newToolActivitySlot` —— **只有段锚点渲染 `ToolActivityGroupView`（完成态 = 入口行），同段其余块渲染 EmptyView = 0 高**；而估算给每个块 36/40pt。
  - `BridgedAssistantHeaderV3` 在 New 皮肤是 `Color.clear.frame(height: 0)`（e696e77），估算仍是 28pt。
  - 日志：`[SettleJitter][decel-inv] idx=11..33` 连纠 ~20 条 `src=est`（`36→0 / 40→0 / 36→24 / key=h: 28→0`），**每秒 7-8 次全量重排**（`[ReflowGap] coalesced re-flows=7~8`），`contentSize` 3874→3681→3389→3149 连塌；修正绝大多数落在视口内/上方（`inside`），而 `!isTracking && !isDecelerating` 才做 offset 补偿 → 拖动/惯性中重排 = 画面位移。**一顿一顿 = 每纠一行一次全表重排；来回跳 = 同一批修正上下滑各来一遍。**
- **Fix**: 新增 `newSkinActivitySlotEstimate(msg:block:isMessageActive:)` 按渲染事实估：非锚点 → 0；锚点完成态 → 入口行；`text`/`info`、classic 皮肤、**活动状态未知的锚点** → 返回 nil 交回经典估算（运行槽 ≈62~138pt，低估比高估糟）。入口行高度按 `FontSettings.shared.scaledApp(20)`（chevron 是 `@ScaledMetric`，随 App 字号档位缩放；真机实测 24.3pt @ pp 当前档，默认档 26 —— 不能钉死常数）。seed 的活跃判定改用 `vm.messages.last?.id`（与视图 `bridge.isActiveMessage` 同源，避免 internal-bridge 行造成的滤波数组分歧）。
- **对抗审查（一轮，pp 批准「改完审查一次就行」）**: 二高五中低。已修 = D1（兜底路径 `isMessageActive:false` 会把运行中锚点低估成 24pt → 改 nil 不猜）、D2（24 硬编码 → 按档位算）、D5（活跃判定同源）、触感副作用分离。**登记不做** = D3（seed 内 O(N²)，改前已因 `blocks.first(where:)` 存在，量级未变）、D4（切皮肤后离屏条目仍带旧皮肤估算 —— 清了不重播种会退化成 200pt 默认值，风险大于收益；**验证时勿中途切皮肤**）、D6（`ToolRenderStyleStore.current` 每项读 UserDefaults，微秒级可忽略）。
- **回归**: classic 皮肤逐字节不变（helper 首行 guard）/ 0 高 cell 不加 itemSpacing（同空 text 块既有形态）/ 文本块与 user 气泡估算不动 / 流式期不新增低估 / 40→24 一类思考锚点同路径。
- **死隔离四问**: ①两端共用渲染件，估算与视图同源同行为；②改动圈定「估算表」一处，零状态机/协议/生命周期改动；③官方等价物=UIKit self-sizing + `estimatedItemHeight` 既有机制（不新增测量）；④回归项如上。
- **装机判据**: 滚历史时日志不再成片 `[SettleJitter][decel-inv] … src=est (36→0)/(28→0)`；`[ReflowGap] coalesced re-flows` 从 7~8 掉下来。
- **验证**: 待装机（本笔修复由 pp 真机日志驱动，改后需同场景复测）。

### THINKING-HAPTIC-SCOPE — Thinking 触感误发到「进聊天页」（CC，2026-09-18，pp：「点进聊天页就有触屏反馈，那个不是只有 Thinking 才有吗」）
- **File**: `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（+11/−3：签名 + 三个调用点）。
- **根因**: 触感写在 `markThinkingStartedIfNeeded()` 里，而这个函数是**三路汇合的幂等置位入口**（① `onChange(thinkingHasStarted)` 真事件、② ThinkingFlushWatcher 真事件、③ `onAppear` cell 重建补查）。③ 是当天 `5f91299` 为修「cell 重建后 Thinking 文字消失」新加的**补记路径**——它补的是"已经发生过的事实"（历史消息重建 / 进页面重现），跟着发触感就把每个已完成回合都震一遍 = 用户感知「点进聊天页就震」。
- **Fix**: 状态置位三路照旧（断的是 @State 不是事实），触感抽成 `haptic:` 参数，只有真事件路径 ①② 传 true。**判例：幂等置位入口不得携带副作用**——它被"补记/恢复"路径复用时，副作用会被无差别重放；副作用要挂在"事件"而不是"状态"上。
- **回归**: 思考真开始仍震一次（①②）/ 进页面、滚动回看、cell 重建不震 / 状态置位与计时起点不变 / classic 皮肤同路径。
- **验证**: 待装机（入口：点进有历史思考的会话，不应有触感；发消息等思考开始，应有一次轻震）。

### SWEEP-DRIVE-V4 + SUMMARY-DARK + THINKING-DETAIL-RENDER/STREAM（CC，2026-09-18 pp 装机反馈四连：字体/颜色不一致 · 扫光不循环 · 汇聚页渲染+不流式 · 暗色未适配）

**Files**: `Chat/ToolActivity/ShimmerText.swift`（驱动重写）· `Chat/ToolActivity/ThinkingDetailOverlay.swift`（色板合并 + 去 markdown + 补订阅）· `Chat/ToolActivity/ToolActivityGroupView.swift`（字体/颜色/常量上提）· `Chat/ToolActivity/ToolEventRow.swift`（两色动态化）· `Chat/AIChatView.swift`（detent 0.69→0.57）。

**1) Thinking 行字体/颜色对齐**（pp：「聊天流 thinking 字体和灰字入口不一样」→「颜色也改成灰字入口一个颜色」）
- 运行槽 "Thinking" 原 `.system(size: 14, weight: .medium)` + `Color.secondary`；完成态入口行是 `.system(size: 14)`（regular）+ 写死暖灰 `#7A7974`。**字号同、字重差一档、色冷暖不同**。
- Fix：两处都改 14pt regular + `#7A7974`；`headlineGray` 从 `ToolActivityGroupView` 静态成员**上提为文件级 `ThinkingRowStyle.headlineGray`**（同文件 `ThinkingElapsedText` 拿不到 private 成员，否则 "· N秒" 会留在 medium+secondary → 一行两粗细）。计时文字同步对齐。

**2) 扫光不循环**（pp：「聊天流中的 thinking 没有循环扫光」）
- **根因（本笔的赌注，见下方"判例冲突"）**：`SweepTextShimmerModifier` 用 `withAnimation(.linear.repeatForever)` 驱动亮带 offset = **隐式动画**；聊天 cell 宿主挂 `.transaction { $0.disablesAnimations = true }`（`CollectionViewMessageListV3` 1266/1292/1316/1332，防 ViewGraph use-after-free），而 `.transaction` 作用于该视图内**所有**事务 → 循环被禁 → offset 直接跳终点（文字左缘外）→ 带子停在文字外面，整行不扫。
- **Fix（v4）**：驱动换 `TimelineView(.animation(minimumInterval: 1/30))` 按绝对时间算相位（`offset = travel − phase·2·travel`）——与同 cell 一直工作的 `ThinkingDotIcon` 同款驱动、且不走动画事务。周期 3s/方向右→左/带宽/`peak()` 峰色算法（v3 修好的 alpha 语义）**全部沿用**，只换驱动；`onAppear` 启动门随 `withAnimation` 一并删除（相位取自绝对时间，无需启动时机）。
- **⚠️ 判例冲突（留痕，勿再互相打脸）**：`PATCHES.md:593`（v2 当时）记「TimelineView 在 cell 里 display-link 不驱动」（同环境 withAnimation 系正常）；`ShimmerText.swift:15`（v3 后来）**推翻该判例**——点阵同用 TimelineView 在同 cell 一直工作，v1 真因是峰色丢 alpha。本笔采信后者并引入第三条：**两条可同时成立**（TimelineView 不归动画事务管 → 活；withAnimation 归它管 → 死），且有 `CollectionViewMessageListV3:5432` 团队记录背书（该护栏会 suppress sheet 上滑动画，故 sheet 被刻意放在 cell 树外）。**若装机仍不扫 → 换 CA 驱动（CABasicAnimation 位移 mask），不再猜第三条。**

**3) 汇聚页思考详情：渲染 + 流式**
- 渲染根因：两处 `thinkingMergedText` 把「已落定正文」与「最后 24 字流式尾」**各自**跑一次 `AttributedString(markdown:)`（全仓仅本文件用该 API）→ ① 跨 24 字边界的 markdown 结构被劈开、两半都解析失败 → `**`/反引号原样外露且随流式闪现；② 与聊天流思考正文（`AssistantBlockView:968` 纯 `Text`，零解析）渲染不一致；③ 默认 full 语法把软换行当空格 → 分行丢失挤成一坨。
- Fix：4 处改纯 `Text`，换行原样保留；衬线/字号/配色不动。
- 流式根因：本 sheet 只订阅 `message`（`ChatMessage` 不转发 block 通知，blocks 数组引用不变也不发通知），而增量落在 `AssistantBlock.@Published content` → 打开那一刻画面冻死。
- Fix：段内每个思考块挂零尺寸 `ThinkingFlushWatcher`（该 watcher 由 private 提为 internal，两处共用）→ flush 落地即 tick 重算，节奏与聊天流一致（0.3~1.5s 节流，不做逐 token 重绘，避免重演 thinking 卡顿判例）。

**4) 暗色适配**（pp：「新版的部分 ui 没有暗黑模式适配」→ 批量审 28 条，必修 16 条）
- 根因面：暗色下 `sheetBg` 等仍是写死浅色，而正文/标题用 `Color.primary`/`.label`（暗色=白）→ **白底白字**；`ToolEventRow` 路径胶囊同理（`#F2F2F4` + `.label`）。
- Fix：新增 `SummaryPalette`（文件级，三处重复的 `sheetBg` 合并为单一来源）：`sheetBg` #F5F5F5/#181818、`rowInk` #1D1D1D/#EDEDED、`muted` #888681/#A0A0A0、`connector` #DCDCDC/#2E2E2E、`circleButton` 白/#2E2E2E（浅色"白比 #F5F5F5 亮"的同关系）；`ToolEventRow`：`pathCapsuleBg` #F2F2F4/#2C2C2E、`commandGray` #7C7C81/#A0A0A0。深色档取设计规范的中性暖灰（禁蓝调）。
- **pp 点名不改**：点阵 `ThinkingDotIcon.dimColor`、入口行 `headlineGray`（保持写死唯一值）。

**5) 汇聚页初始高度 0.69 → 0.57**（pp：「第一次弹出来的高度能别这么高吗」+「你算一下」）
- `.fraction(n)` = `context.maximumDetentValue × n`，**不是屏高**（SwiftUI 内部实现；本次实测反推）。标定：0.69 渲染顶边 y=927px → sheet 543pt = 屏高 63.7% → maxDetent = 543/0.69 = **787pt**；Claude App Summary 弹窗顶边 y=1211px → sheet 448pt → **448/787 = 0.5697 → 取 0.57**（渲染 448.6pt，与 Claude 差 1px）。两处同步改（detents 首项 + `sheetDetent` 初值，不一致会先落错高度再吸附）。标定截图：Claude `debug-1789704841591`（y=1211）与 moonveil `debug-1789704991170`（y=927）。

**回归**: classic 皮肤零影响（改动全在 New 皮肤路径 + 汇聚页 sheet）· 入口行/点阵观感（pp 点名不动）· 扫光静止态=base 灰不变 · 思考详情 push/pop 与尾巴灰渐显不变 · 代码卡 `SelectableMarkdownView` 不受影响（未动）· detent 用户拖拽吸附不变。
**验证**: 待装机（① 扫光是否循环 ② 汇聚页弹窗高度是否与 Claude 一致 ③ 思考详情是否随流式增长 ④ 暗色下汇聚页/工具行是否可读 ⑤ Thinking 行字体颜色与入口行一致）。**装机取证建议**：录 5s 屏（聊天流 thinking + 汇聚页标题扫光同框），抽帧判定 —— 见本文档 1) 与 2) 的判例冲突尚未有帧证据。

### SWEEP-PARAMS-V5 — 扫光参数改照 **iOS App 实测**（不再照网页 CSS）（CC，2026-09-18 pp：「那你改吧」）

- **File**: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`（+42/−10：周期/方向/节奏 + phase 分段函数 + ease；`sweepShimmer` 扩展默认值同步）。
- **起因**: v1~v4 的参数一直是照 **claude.ai 网页版生产 CSS**（`cds-shimmer-text-shine`），而 pp 的参照物始终是 **iOS App**。他录了一段 14s 屏幕录制（当"文件"发微信 → 桥解密落盘）→ ffmpeg 抽帧 → 逐帧量"亮带质心"。
- **App 实测（与网页 CSS 三处不同）**：
  - **周期 ≈ 2.0s**（120 帧 @60fps；14s 录到 7 圈，自相关峰值 0.80，谐波落 240/360 帧）。网页 CSS 是 **3s** —— App 快 1.5 倍。
  - **方向 左→右**（亮带质心 48 → 165 单向前进）。网页 CSS 的 `background-position 83.333% → 16.667%` 按 `background-size 300%` 换算同样是左→右；**我们此前实现是右→左 = 反的**。
  - **节奏不对称**：慢扫过去 ~1.6s（S 曲线：中间快、两端慢）+ 快扫回来 ~0.4s。网页 CSS 的"两端各停 15%"在 App 上**不存在**（不是停，是快速回扫）。
  - 带宽（≈文字宽一半）与峰色算法（base 30% + white 70%）**一致**，不动。
- **Fix**: `period 3.0 → 2.0` + 新增 `outbound = 1.6`；`phase(date:period:outbound:)` 分段（去程 0→1 左→右 / 回程 1→0 右→左，各套 smoothstep）；offset 由 `travel − phase·2·travel` 改为 `−travel + phase·2·travel`（翻向）。
- **⚠️ 踩点留痕**: 调用方都不传 `period`，**扩展 `sweepShimmer(base:period:)` 的默认值也必须一起改**，否则改结构体默认值完全不生效（两处默认值 = 同一份参数，改一处等于没改）。
- **方法学留痕**: 微信桥不支持视频（只有一行占位字、CDN 是 AES 密文且 key 不落盘）→ **录屏存「文件」App 再当"文件"发**，桥走 file 链路自动解密落盘；再用 ffmpeg crop+rawvideo 抽灰度帧 + PIL 求"亮带质心"。注意 iPhone 录屏是 **VFR**（本次 58.3fps 且开头有重复帧），按帧号算周期会有偏差，精确值需按 pts_time 重采样。
- **回归**: 聊天流 "Thinking" 行扫光 / 汇聚页标题扫光（同一 modifier 两处调用同受益）/ 静止态 = base 灰不变 / 深浅色峰色跟随 base / classic 皮肤零影响。
- **验证**: 待装机（对照 App：同样是 2s 一圈、左→右、慢去快回）。

### THINKING-TRIGGER-TOOLPATH — 「Thinking」在无思考流的模型下永不出现（CC，2026-09-18 pp：「明明都在做任务了、都在调用工具，有时候 thinking 都不出现」）

- **File**: `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（判定属性 + 7 处引用重命名）。
- **症状**: 点阵正常转、工具行正常长，但「Thinking」文字与秒数**整轮都不出现**（pp：点阵没问题，是这个判定有问题）。
- **根因**: **thinking 块只在收到 `.thinkingDelta` 时创建**（`AIChatViewModel+SSEStream.swift` 该分支），这是 **Anthropic 系专有**概念。而「Thinking」文字/计时的判定 `thinkingHasStarted` 只看"thinking 块有没有内容" → 接 OpenAI/Gemini 等不出思考流的模型时该条件**恒为假**，整轮只显示点阵。pp 那台会话用的正是 `Atria Dawn Preview · OpenAI 2`。
- **Fix**: `thinkingHasStarted` → **`workHasStarted`**：`!segment.toolIds.isEmpty`（工具已在跑 = 模型在干活）**或** 思考内容到达（双读 buffer，保留原逻辑）。计时起点随之 = 该条件首次成立的时刻——**等待模型响应那段仍不计入**（保持 09-18 的选择：点阵先行、"思考"从模型开始回应起算）。
- **回归**: 纯文本回合（无 thinking 无工具）仍不显示该行（活动槽不成立）/ 等待响应阶段仍只有点阵 / 工具的段「Thinking」+秒数出现并持续到段结束 / 完成态入口行与摘要 fallback（`thinkingHeadline ?? lastToolSummary ?? 思考结果`）不变 / classic 皮肤零影响。
- **验证**: 待装机（用无思考流的模型发一个会调工具的任务 → 「Thinking」与秒数应随第一个工具调用出现，不再是"只有点阵"）。

### TEXT-ESTIMATE-CJK — 中文段落高度估算少一半（「点阵行贴到上一条正文」的根因）（CC，2026-09-18 pp 装机两张截图）

- **File**: `src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`（+45/−2：`unitsPerLine` + `widthUnits` + `isFullWidth`）。
- **症状**: 流式期间，正文段落最后一行下面**紧贴**着活动槽的点阵行（间距被吃掉），同屏工具行间距正常；**滑出聊天页再进来就恢复**（pp 12:59 / 13:00 两张截图同款）。
- **根因**: `estimateTextBlockHeight` 的 `cpl = tw / (scale * 0.5)` 假设**平均字宽 = 0.5×字号**（拉丁字母均值），而中文/日文/韩文每字 ≈ **1×字号** → **中文段落行数被低估约一半**，高度估小约一行。实测对照（pp 截图那段中文）：实际 3 行 ≈ 71pt vs 估算 2 行 ≈ 48pt，**差 22pt = 正好一行**。下一格（活动槽的锚点格）按这个少了 22pt 的高度落位 → 压进段落溢出区 =「贴上去」。
  - **为什么"滑出再进就正常"**：流式期间 markdown 未缓存，走的正是这条粗估；缓存之后走 `SelectableMarkdownView.ctFramesetterHeight`（±1pt）→ 高度对了、位置就对了。
  - **旁证**：同文件 3804 行注释早已记录同款症状（user 气泡分支："a 3-line message estimated as 2 lines"），当时靠"改用精确测量"绕开、**估算函数本身没修**；assistant 文本块在流式期没有 cachedAttributedString 可测，走的还是它。
- **Fix**: 字符按类型折算宽度（全角 1.0 / 半角 0.5），`unitsPerLine = max(1, tw / scale)`；行数 = `ceil(units / unitsPerLine)`。纯 ASCII 段落行为不变（旧式 = 全半角各半时的特例）。
- **回归**: 表格 / 代码块 / 图片 / 引用分支不动 · 估算只作用于流式期与离屏预取，settle 后仍以实测为准 · classic 与新皮肤同用此估算（两边都受益）· 不改变任何渲染宽度或字号。
- **验证**: 待装机（中文长段落流式回复时，段落与点阵行之间应保持正常间距，无需滑出重进）。

### STREAM-HEIGHT-THAW — 流式 cell 高度三层冻结（「Thinking 槽有时候贴正文」的完整根因，含 4009c78 修不到的部分）（Doris，2026-09-18 pp：最新包 4009c78 装机仍贴）

- **File**: `src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`（+57/−0，纯插入：`remeasureStaleStreamingCells()` + `doFlushStreamingLayout` 一行调用）。
- **症状**: pp 装 4009c78 包（TEXT-ESTIMATE-CJK 已含）后仍报「tinking 有时候会贴正文」；截图正文 2 行中文段落 + Thinking 槽，间距 ≈3pt（正常 ≈18pt）。
- **根因（三层冻结链,4009c78 只修了第三层的数据源）**: 流式 cell 一旦被 PLAF 真测过一次——
  1. **cell 侧** `lastComputedHeight` 被 PLAF **第一道无条件短路**（MessageListInfrastructure.swift,缓存命中直接 return）锁死,失效条件只有 applyContentConfiguration / prepareForReuse / clearCachedHeight 三个;
  2. **layout 侧** `heightCache[index]` 被 `invalidate(forPreferredLayoutAttributes:)` **无条件写**（477 行）→ 写入的就是那个中间态高度;
  3. **数据源侧** `setEstimatedHeight` / `setPrecalcHeight` 都有 `guard heightCache[index] == nil` → 正文此后增长时,修正后的 CJK 粗估（4009c78）与定稿后的 TextKit 精测**全部被 guard 拒之门外**;
  4. `doFlushStreamingLayout` 每 100ms 只 `invalidateLayout()`、不清任何缓存 → prepare() 永远用冻结高度排 frame → 下一格（活动槽/点阵）贴上来。
- **「有时候」**: 只有当 PLAF 真测恰好落在正文中间态（1 行）、而正文随后长到 2 行时才锁死;真测时正文已定稿则高度正确。「滑出聊天页再进就正常」= 重进触发 clearHeightCache 重新播种。
- **Fix**: 流式 flush 时定向解冻——对流式 ranges 内的 item 用 `estimateItemHeight` 现算粗估,与冻结的 `heightCache` 差 >10pt（约半行）的 cell 跑一次 `remeasureVisibleCells` 同款 both-sides 流程（invalidateHeight + clearCachedHeight + reconfigureItems + invalidateLayout + 二次 clear）,让下一次 PLAF 真测拿到当前内容的权威高度。remeasure 是真测（authoritative）,粗估只做 gate。
- **成本**: gate 把触发收敛到「粗估高度真的变了」（每多一行正文一次）;估算恒定的 cell（工具胶囊 36 / thinking 头 / header/footer）永不命中。reconfigure + hosting 真测是 blockContentFilledSignal / thinkingToggle 已有机制同款,频率再被 flushStreamingLayout 节流（100ms auto-scroll / 3s browsing）压一层。
- **死隔离申报**: 聊天列表呈现层-only（布局/高度缓存域）;不改消息数据、SSE、聚合器、任何 agent 链路;无状态机/生命周期改动。回归项 = ①普通流式文本增长高度正常 ②浏览模式（browsing,3s 节流）滚动无抖动 ③工具胶囊/思考块/入口行高度不受影响 ④重进页面行为不变 ⑤流式结束 settle 不跳动。
- **验证**: 待装机（长中文回复流式时,正文与 Thinking 槽/工具行保持正常间距;日志 `[StreamFlush] remeasure stale streaming cells` 只在真正长行时出现）。

### SHIMMER-V6 — Thinking 扫光前 5 版全失败的结构性根因（弃 mask/overlay/GR，改 foregroundStyle 渐变文字）（Doris，2026-09-18 pp：「扫光依旧没有，修了很多遍」）

- **File**: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`（+38/−34：body 重写 + 新增 `shimmerStops`）。
- **全链路审查结论**: 前 5 版（b868d01 TimelineView 渐变 / f1f009e CA mask / GeometryReader+preference / v4 TimelineView+mask / v5 参数照 App 实测）全部依赖 **mask + overlay + GeometryReader** 这套系统层机制。这些在**普通 SwiftUI 视图**里能工作，但在**聊天流 cell（UIHostingConfiguration + `.transaction { $0.disablesAnimations = true }` 宿主）里不被渲染** → 真机永远看不到。同一 cell 里 ThinkingDotIcon 一直能动，前提是 **TimelineView 每帧重算 body + Canvas 命令式重绘**（纯值更新，不依赖系统视图层/mask）——这正是 5 个版本都缺失的。
- **sweepShimmer / shimmerText 共用**: 两个调用点（运行槽 Thinking 文字 / 汇聚页标题）自动受益；API 不变（`sweepShimmer(base:period:)` 签名未动），峰色/相位/带宽逻辑保留（v5 的 2s / 左→右 / 慢去快回）。
- **Fix**: body 改为 `TimelineView(.animation(minimumInterval: 1/30))` 内直接给 `content.foregroundStyle(LinearGradient(stops: shimmerStops(...)))`——亮色位置随 phase 在 0→1 移动（左→右），两端 base，形成"亮光扫过文字"，**无 mask、无 overlay、无 GeometryReader**，必然渲染。
- **细节**: `shimmerStops` 的 locations 必须升序且 clamp 到 [0,1]——亮带贴边时 lo/hi 重合，LinearGradient 允许同 location 的 stop（顺序渐变）。带宽 0.45（App 实测亮带 ≈ 文字宽一半）。
- **判例（可复用）**: ①**cell/UIHostingConfiguration 里凡是要"动"的视觉，优先走 TimelineView 每帧重算 body + 纯值更新**（foregroundStyle 渐变 / Canvas 重绘），不要走 mask/overlay/GeometryReader 这套需要系统渲染层配合的机制——后者在 disablesAnimations 宿主里不被渲染。②扫光 = 文字 foregroundStyle 渐变即可，无需 mask。
- **死隔离申报**: 呈现层-only（文字着色），不改消息数据/SSE/聚合器/agent 链路；纯新增函数 + body 重写，无 pbxproj/资源改动；回归项 = ①运行槽 Thinking 文字 ②汇聚页标题 ③ThinkingDetailOverlay 标题 ④峰色/方向/周期参数不变 ⑤accessibilityHidden 从 content 移除（不再隐藏底层文字，VoiceOver 可读）。
- **验证**: 待装机（聊天流 "Thinking" 行应有左→右亮光扫过；汇聚页标题同；30Hz 与点阵一致但带宽 45% 不闪烁）。

### SHIMMER-V7 — 对齐经典版卡片 ShimmerOverlay 机制 + 可见度/频率对齐经典版（覆盖 V6；Doris，2026-09-18 pp：「经典版的卡片都有扫光 你看看呗」+「可见度、频率也跟经典版保持一致」）

- **File**: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`（+49/−36：body 重写、`shimmerStops` 改稳定 bell 版、增 `@State progress` / `@Environment colorScheme` / `peakOpacity`）。
- **为什么改**:
  - V6（上一笔）方向错了：用 **TimelineView 每帧重建渐变**,恰恰踩了经典版 `ShimmerOverlay` 注释明说的坑——“**rebuilding gradient stops every frame** ... CAGradientLayer colorspace teardown race (EXC_BAD_ACCESS at encode_colorspace)”。真机不可靠（要么渲染异常要么崩溃）→ 扫光仍不显示。
  - pp 点名「经典版的卡片都有扫光」= `AssistantBlockView.ShimmerOverlay`（line 248）在聊天流 cell 里**能正常显示**,它靠的是:① 稳定渐变 stops(一次构建,不每帧重建)② `withAnimation(.repeatForever)` 驱动 offset ③ GeometryReader **同步读尺寸**(不走 onPreferenceChange 回传——那是 v2 跳变的根因)④ `.clipped()`。
- **V7**: body 改为 ShimmerOverlay 同款——`GeometryReader` 内底层 base 文字 + `overlay` 一条**峰色 bell 渐变光带**(稳定 stops),`withAnimation(.linear(period).repeatForever)` 驱动 `progress` 0→1 使 offset 从左缘外→右缘外扫过文字。**无 mask、无 TimelineView、无 preference 回传**。
- **可见度/频率对齐经典版**: `period` 默认 **2.8s**（ShimmerOverlay 同款）；`peakOpacity` = 浅 **0.75** / 深 **0.25**（对齐 ShimmerOverlay.peakOpacity）。`sweepShimmer` 扩展默认 period 同步改 2.8（v5 判例：两处默认值必须一致）。
- **保留**: `phase`/`ease`（unused,未删）、`peak(base)`（峰色=base 混白）、两个调用点 API 不变。
- **🔴 判例（可复用）**: ①cell 里要动的视觉,若仓内已有**验证可靠**的同屏实现(ShimmerOverlay),**直接对齐它的机制**,不要在它之外发明;②**稳定渐变 stops + offset 动画** 是 cell 里扫光的正解,`TimelineView 每帧重建渐变` 会踩 colorspace teardown;③「disablesAnimations 吞 withAnimation」的旧判例**不成立**——经典版 ShimmerOverlay 正是 withAnimation repeatForever,在聊天 cell 里能动;v2 失败真因是 **onPreferenceChange 回传跳变**（offset 目标 0→真实宽,repeatForever 被替换）。
- **死隔离申报**: 呈现层-only（文字扫光修饰器重写）,不改消息数据/SSE/聚合器/agent 链路;回归 = ①运行槽 "Thinking" 文字 ②汇聚页标题 ③ThinkingDetailOverlay 标题 ④深浅色 peakOpacity 自适应 ⑤VoiceOver 不受影响（光带 allowsHitTesting(false)）。
- **验证**: 待装机（聊天流 "Thinking" 行应有左→右亮光扫过、2.8s 一圈、可见度与经典版一致;汇聚页标题同步;深色模式 0.25）。

### INLINE-CODE-PAD — 行内代码灰底去掉后残留 hair space 间距（pp 09-18 装机：「之前正文的橙色文字有灰底占位 然后现在去掉了之后间距还在」）

- **File**: `src/ios/Views/Chat/SelectableMarkdownView.swift`（−2/+2：body `renderInline .code` 分支去掉 `\u{200A}` hair space 包裹）。
- **根因**: 灰底 pill 时代，行内代码用前后 `\u{200A}`(hair space) 给高亮框做视觉 padding；pp 09-17 把背景置 clear(`minisInlineCodeBackgroundColor = .clear`)后，这俩 hair space 没删 → 橙色字(`next` / `.bin`)周围残留多余间隙。table-cell 的 `renderCellInline` 本就不加 hair space，body 与之不一致。
- **Fix**: `NSAttributedString(string: "\u{200A}\(code)\u{200A}")` → `NSAttributedString(string: Self.breakableInlineCode(code))`，去掉前后 hair space，橙色字贴合正文。
- **回归**: ①copy 时 `plainTextWithTables` 已 strip U+200A 不受影响 ②tap-to-copy 读 `.inlineCodeText`(原始 code)不受影响 ③breakableInlineCode 的 `\u{200B}`(零宽,仅 >24 字符)保留 ④table-cell / 代码块不受影响。
- **验证**: 待装机(正文 `next`/`.bin` 橙色字与两侧文本贴合、无多余间隙)。

### CHAT-BG-THEME — 聊天背景主题切换(默认系统 / Claude 官方背景)(Doris, 2026-09-18 pp:「能不能加个聊天主题切换 就是聊天背景 加一个claude风格的 相当于两套主题风格」+「就只换背景颜色就行」)

- **File**: `src/ios/Views/Chat/AIChatView.swift`(+22：`ChatBackgroundTheme` enum + `ChatColors.claudeBackground` + `@AppStorage("chatBackgroundTheme")` + 背景切换)、`src/ios/Views/ContentView.swift`(+12：`AppearanceSettingsView` 加 `Chat Background` 切换 Section)。
- **Claude 背景色(官方实测)**: 查 claude.ai 登录页 / docs.claude.com / 深色会话页,`data-color-version="v2"`:
  - 浅色 body/页面背景 **#FCFCFB**(微暖米白),底 surface #F9F9F7;
  - 深色 body/页面背景 **#151515**(暖黑),底 surface #0B0B0B。
  - ⚠️ 网上常传的 `#FAF9F5 / #262624` 是 Claude **旧版**;当前官方用 #FCFCFB / #151515(以实测为准)。
- **实现**: `ChatBackgroundTheme`(system/claude)@AppStorage("chatBackgroundTheme") 持久化;`ChatColors.claudeBackground` 动态 trait(浅 #FCFCFB/深 #151515)。AIChatView 背景按主题选;`AppearanceSettingsView` 加 Picker 切换,同 key 联动自动刷新聊天背景(不用重启)。
- **范围**: 只换聊天区背景色(pp 明确);气泡/文字/输入栏不动。默认 = `ChatColors.background`(systemBackground),行为零变化。
- **死隔离申报**: 呈现层-only(背景色/设置入口),不改消息数据/SSE/聚合器/agent 链路;@AppStorage 新 key 不与现有 key 冲突;切换不影响会话/布局。
- **验证**: 待装机(设置 → Appearance → Chat Background = Claude → 回聊天区,浅色米白 #FCFCFB / 深色 #151515;切回默认=系统背景)。

### SHIMMER-V8 — 严重 bug:外层 GeometryReader 被拉伸 →「思考结果」sheet 大竖渐变带(修复 v7 结构)(Doris, 2026-09-18 pp 截图:「思考闪光严重bug」)

- **File**: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`(+21/−23:body 结构调整,机制不变)。
- **症状**: 「思考结果」sheet 标题下方出现一条**跨全屏的大竖直渐变带**(pp 截图 photo_879CE548),标题布局同时被破坏。
- **根因**: v7 把 `GeometryReader` 放在 modifier **最外层**(直接包 content)。GR 是 greedy 的——挂在「本来就要填满的卡片」上无害(经典版 ShimmerOverlay 正是这种宿主),但 sweepShimmer 挂在**自然尺寸的文字**(标题 Text / 单行 "Thinking")上时,GR 被父容器(ZStack/sheet)拉伸到远大于文字的尺寸:①光带 `height = geo.size.height` = 拉伸后高度 → 跨全屏竖带;②content(Text)被 GR 的 topLeading 放置 → 标题布局破坏。
- **Fix(v8)**: GR 挪进 `.overlay { }` 内——overlay 的 proposal = content 实际尺寸,GR 填满它 = 量到真实尺寸,且 **overlay 不参与父布局、不影响 content frame**。光带高度 = 文字行高,恢复正确。机制保持 v7(稳定 bell stops + withAnimation repeatForever 驱动 offset + .clipped 裁缘外)。
- **🔴 判例(可复用)**: **GeometryReader 直接包 content 会改变宿主布局**(GR greedy 吃满父 proposal,把自然尺寸的 content 拉伸/topLeading 放置);要「量 content 尺寸且不影响布局」,GR 必须放在 `.overlay { }`/`.background { }` 内(overlay 的 proposal = content 实际尺寸)。经典 ShimmerOverlay 的外层 GR 只对 fill 型宿主成立,不可照搬到自然尺寸文字上。
- **死隔离申报**: 呈现层-only(扫光修饰器 body 结构);不改消息数据/SSE/聚合器;回归 = ①聊天流 "Thinking" 行扫光正常、布局不变 ②汇聚页标题扫光正常、标题居中恢复 ③思考结果 sheet 不再有大竖带 ④深浅色 peakOpacity 不变。
- **v9.1(同日 pp:「聊天流你也要给我实现啊」)**: 聊天流 Thinking 行所在 cell 宿主挂
  \`.transaction { \$0.disablesAnimations = true }\`(防 ViewGraph use-after-free 护栏),
  库的隐式 .animation(_:value:) 在 cell 内被吞 → 扫光不动。新增
  \`SweepTextShimmerTimeline\`:同几何(UnitPoint 端点 + bandSize 端点延伸 + overlay
  .sourceAtop)、同配色(ShimmerStyle.shimmerGradient/peak 共享,bandSize 0.3→1.0 对齐
  v5 实测亮带≈文字宽一半),驱动换 TimelineView(.animation) 相位 —— 纯时间函数,
  无 @State 无事务,disablesAnimations 管不到(ThinkingDotIcon 同管线实证可动)。
  ToolActivityGroupView:202 换 \`sweepShimmerTimeline\`;sheet 标题保持库版 \`sweepShimmer\`。
  **判例**: 同一视觉同一宿主族里「隐式动画被吞」的唯一可靠解法 = 时间驱动重绘
  (TimelineView/Canvas),不是换动画 API。

- **验证**: 待装机。

### STREAM-THAW-WIRING — 贴正文根因修复:解冻挂上真实触发源(A1 applySnapshot 后 + A2 每次 flush 信号)(Doris, 2026-09-18 pp 拍板「一起做」;调查报告见会话)

- **File**: `src/ios/Agent/Chat/AIChatViewModel.swift`(+8:`streamingTextFlushSignal` 定义 + 每次 flush 发送)、`src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`(+20:订阅 + applySnapshot completion 后解冻)。
- **根因回顾(调查结论,pp 已确认)**: 正文流式增长只更新 `block.content`(只发 block 级 objectWillChange;message/vm 级均不发)→ `lastMessageSub(message.objectWillChange)` 不触发 → `doFlushStreamingLayout` 不跑 → **b94729b 的 `remeasureStaleStreamingCells` 在正文增长路径上从未执行(死代码)**。三层高度冻结(PLAF 第一道缓存 / heightCache 无条件写 / set*Height guard)无人解冻 → 新 anchor 插入时落在旧高度之下 =「贴」。b94729b 挂错了事件源。
- **A1**: applySnapshot 的 diffable-apply completion 里(syncScrollFlags 后)`async` 调 remeasure——新 block(anchor/工具行)插入引发的布局 pass 会把正文 PLAF 真测锁死在中间态,此刻正是需要解冻的时机;async 防本 apply 收尾重入。
- **A2**: 新增 `streamingTextFlushSignal`(每次 streaming text flush 发送,节流已在 SSE 层 0.2~2.0s 做过;deferred 合并更新在 flushDeferred 补发),VC 订阅 → remeasure。覆盖「纯文本流式(全程无新 block 插入)」场景——A1 对它无效。
- **B 说明(并入 A,不单独做)**: 「seed 循环可覆盖写入」若只写 estimated/heightCache 会被 PLAF 第一道缓存返回旧值 + `invalidate(forPreferred:)` 无条件写回**冲掉**,单独无效;它的完整形态就是 remeasure 的 `invalidateHeight + clearCachedHeight + reconfigure`(清 cell 侧缓存让 PLAF 真测拿新值),已含在 A1/A2 触发的 remeasure 里。
- **gate 数值核对**: scale=16 / lineHeight=22.4(AIChatView.swift:3845),1 行 est≈30.4pt vs 2 行 est≈52.8pt,行差 22.4pt > 阈值 10 → gate 对整行级冻结有效;remeasure 是真测(权威),粗估只做 gate。
- **死隔离申报**: 布局层 + 信号接线,不改消息数据/SSE 协议/聚合器/agent 链路;新 signal 为纯新增(无既有订阅者受影响);remeasure 自带 gate(无 stale 时零成本,只遍历流式 ranges 现算粗估);deferred(suspended)路径不提前发信号。回归项 = ①纯文本流式正文增长不贴 ②正文段+Thinking anchor 插入不贴 ③工具行/思考块/入口行高度正常 ④browsing 模式(3s 节流)无抖动 ⑤重进页面行为不变 ⑥流式 settle 不跳。
- **验证**: 待装机。日志判据:流式中段应出现 `[StreamFlush] remeasure stale streaming cells idx=...`(此前为零);贴正文不再复现。

### SHIMMER-V9 — 弃自研，直接引 markiv/SwiftUI-Shimmer 包(Doris, 2026-09-18 pp:「这个不是有现成的吗」)

- **File**: `src/ios/Views/Chat/ToolActivity/ShimmerText.swift`(重写 SweepTextShimmerModifier,-103/+34)、`src/ios/Minis.xcodeproj/project.pbxproj`(+15:挂 SPM 包)、`THIRD_PARTY_LICENSES.md`(+1)。
- **背景**: v1~v8 自研路线连续踩坑(TimelineView 每帧重建渐变 → preference 回传跳变 → GeometryReader 量宽 → withAnimation repeatForever 被 cell 宿主 `disablesAnimations` 吞 → v8 最外层 GR 被 sheet 拉伸成跨全屏大竖渐变带)。pp 拍板停止自研,直接用 https://github.com/markiv/SwiftUI-Shimmer(1.5.1, MIT, 零依赖, iOS13+)。
- **机制**(为何这个包能避开我们踩的所有坑): 渐变端点 = 依赖 `@State isInitialState` 的 **UnitPoint 计算属性**,由隐式 `.animation(_:value:)` 驱动插值 → **无 GeometryReader**(不会被父容器拉伸,治 v8)、无 offset 状态(治 preference 跳变);端点延伸到视图外(`min=-bandSize`/`max=1+bandSize`),亮带从视图外扫入扫出两端无硬切。
- **配置**: mode `.overlay(.sourceAtop)`(渐变只画在文字像素上 = 亮带横扫,非 mask 模式的整行变淡);gradient = `clear → 峰色 → clear`;`bandSize 0.3`;animation `.linear(2.8).repeatForever`。**周期 2.8s / 峰色 color-mix(base 30%,white) / 可见度 0.75·0.25 全部沿用我们装机实测值**,只换驱动机制。
- **调用点**: `sweepShimmer(base:period:)` API 不变,ThinkingDetailOverlay(汇聚页标题)与 ToolActivityGroupView(聊天流 Thinking 行)零改动。
- **⚠️ 已知限制**: 隐式 `.animation(_:value:)` 在聊天流 cell 宿主(`.transaction{disablesAnimations}`)同样被吞 —— 与旧 withAnimation 路线同级问题,非回归。本修饰器仍只用于汇聚页(sheet);聊天流那条路另案。
- **🔴 判例(可复用)**: **同一视觉机制连续 8 版自研失败时,停止造轮子,引成熟开源包**(pp 明确拍板可引第三方)。自研渐变扫描的几何(量宽/offset/端点延伸)在 SwiftUI 各宿主(cell/sheet/ZStack)下行为差异极大,成熟库用 UnitPoint 归一化坐标一次性绕开全部尺寸问题。
- **死隔离申报**: 呈现层-only;新增 SPM 包为纯新增依赖(不触碰任何共享件);不改消息数据/SSE/聚合器/agent 链路。回归项 = ①思考结果 sheet 标题有左→右亮带扫过、无跨屏竖带、标题居中不变 ②聊天流 Thinking 行行为不退化 ③深浅色峰色正确 ④其余 4 个 SPM 包构建不受影响。
- **验证**: 待装机。

### SHIMMER-V9.1/V10/V10.1 — 聊天流扫光三连发:v9.1 死代码 → v10 统一 Timeline → v10.1 mask 分层(Doris+Qoder, 2026-09-19 pp:「装了最新包扫光还是没显示」)

- **v9.1(30f4376, Doris)**: 聊天流 Thinking 行加 TimelineView 驱动版 `sweepShimmerTimeline`。**实际失败**: 只改了注释没改调用点方法名,库版仍在跑 → 被 cell 宿主 disablesAnimations 吞 = 死代码(记账漏两笔,本次一并补)。
- **v10(f84c513, Doris)**: 合并成单一 `sweepShimmer` modifier(TimelineView 驱动 + foregroundStyle 渐变当文字前景),亮带砍到 0.3×字宽治灰块。调用点零改动,死代码自动激活。pp 05:1x 装机(v10 CI 05:17 才出,实际装的疑为 v9.1;pp 坚称最新包,按 v10 已装处理)。
- **v10 装机反馈**: 深浅色**完全不可见**(pp:「浅色模式我也看不到」)。排查发现两个独立缺陷:
  1. **峰色 alpha 数学错**: 峰色 `peak(base).opacity(0.25)` 在 foregroundStyle 语义下 = 文字变透明透出页面底色,不是提亮。暗色(#151515 底)实算 0.478→0.268,对比 1.7:1 ≈ 数学上不存在。经典版 0.75/0.25 是 `.white.opacity` **叠在文字上的 overlay** 用法,搬成文字前景色后语义完全变了。
  2. **foregroundStyle 通道可疑**: 调用点 Text 自带 `.foregroundStyle(headlineGray)`,modifier 外层再挂渐变——层级 foregroundStyle 对已自设样式的 Text 是否穿透未验证;浅色下渐变若生效应有 ±50% 亮度横扫绝不可能看不见,实测看不见 = 渐变大概率没参与渲染。**根因未闭环(缺帧证据),本版对两种死法都免疫。**
- **v10.1(本次, Qoder)**: 改 **mask 分层** — ZStack{ base=content 原样实体色全程可见; peak=同 content 副本 `.foregroundStyle(实心峰色)` + `.mask(移动白色亮带)`},亮带是实心提亮(#7A7974→≈#D1D0CD,深 4.7:1),不再依赖 alpha 混合或前景解析路径。驱动仍 TimelineView 纯值更新(不走事务);peak 层 `allowsHitTesting(false)+accessibilityHidden`;`sweepShimmer(base:period:)` API 不变,两调用点零改动。
- **🔴 判例(可复用)**: ①「可见度 0.75/0.25」这类参数**绑定的是渲染机制**(overlay 叠加 vs 前景 alpha vs mask 提亮),换机制必须换算,直接搬运数值得不到同样观感;②Color.opacity 用于文字前景 = 变透明不是变亮——要提亮用**实心提亮色**或白色 overlay;③连续多版失败的视觉问题,新方案必须**同时绕开所有已实锤死法**,而不是在单一疑点上再猜一轮。
- **⚠️ 下一手(若 v10.1 仍不出)**: 不再猜第五条。按 交互与体验.md:285 判例走 CA(CABasicAnimation 位移 mask),且先向 pp 要 5s 录屏抽帧,定死失败环节(静态=驱动死/颜色对不动=渲染层/颜色不对=色值)。
- **死隔离申报**: 呈现层-only(单文件 ShimmerText.swift + 两行注释),不改消息数据/SSE/聚合器/agent 链路;新增仅 ZStack 一层,无新依赖。回归 = ①聊天流 Thinking 行扫光 ②汇聚页标题扫光 ③ThinkingDetailOverlay 标题 ④文字选中复制(peak 层不吃点击) ⑤深浅色 ⑥VoiceOver 不双读(accessibilityHidden)。
- **验证**: 本机无 swiftc,编译靠 CI;装机判据 = 聊天流 Thinking + 汇聚页标题同框录 5s 抽帧。

### TAIL-GRAY-FIX — 汇聚页思考尾巴灰渐显完成后不转黑:segment 快照冻结(Qoder, 2026-09-19 pp 截图:「这个思考文字的尾部为什么是灰色」)

- **症状**: sheet 里思考原文最后 24 字灰尾,消息早已完成(标题都显示 Thought for 30s)仍灰。
- **根因**: `ThinkingDetailOverlay.isSegmentRunning = !segment.isDone`,而 `segment: TurnActivitySegment` 是**打开 sheet 瞬间的值类型快照**(AIChatView 667 通知携带 → 771 塞入)。运行中打开 → 快照永远 isDone=false → 灰尾永久冻结。旁证: `isActiveMessage` 参数声明后全文件零引用(死参数),消息终态压根没接进来。flushTick 流式修复只救文字不救状态。
- **修复**: 运行态改现读三条件,语义与聚合器 isDone 逐条对齐——①段块之后出现 text/info 块(closedByContent)→ done;②段内工具 toolStatus streaming/running → 运行中;③其余看 `isActiveMessage()` 闭包现读 vm.isProcessing(调用点补末条判定,防旧消息被新消息 processing 误判)。完成瞬间 message @Published / vm 翻转 → 尾巴灰转黑。
- **附带效果**: sheet 打开后消息才完成的场景(原冻结路径)与"运行中打开→完成"翻转均正确;ThinkingDetailPage 484 行同款尾巴经父视图传值同步受益。
- **🔴 判例(可复用)**: 值类型快照 + "打开瞬间定死"的状态参数,凡是语义上会随时间翻转的(运行/完成),在常驻视图(sheet/详情页)里必须闭包或对象现读,不许信快照;死参数(`let x: Bool` 零引用)是接线断裂的指纹,grep 一下就知道。
- **死隔离申报**: 呈现层-only(状态读取方式),不改消息数据/SSE/聚合器/agent 链路;ThinkingDetailOverlay 全仓唯一实例化点已同步改。回归 = ①运行中打开 sheet 尾巴灰+完成转黑 ②完成后打开 sheet 全程黑 ③标题三态(Thinking…/Thought for Ns/思考结果)翻转正常 ④工具行灰字当前项判定不受影响 ⑤多消息并发时旧 sheet 不误判。
- **验证**: 本机无 swiftc 靠 CI;装机判据 = 运行中点开汇聚页等完成,尾巴应自动转黑。

### SHIMMER-V11 — 扫光 v10.1 装机仍双双不可见 → CA 驱动 mask 亮带(Qoder, 2026-09-19 pp 06:11 实机:「为什么还是没有扫光」)

- **装机反馈**: v10.1(TimelineView 每帧移 SwiftUI mask 渐变 + 实心峰色分层)装后,聊天流 Thinking 行与汇聚页标题**双双无扫光**。文字显示正常、无灰块 → 峰色副本从未露出 = mask 通路整体没参与渲染。至此 SwiftUI 侧"每帧重算渐变/mask"路线两次证伪(v10 foregroundStyle 渐变 / v10.1 mask 渐变)。
- **同帧澄清(非 bug)**: pp 截图里灰尾当时是**正确行为**——Shell command「等待 30 秒」仍在跑,段未结束,尾巴按设计应保持灰;TAIL-GRAY-FIX 的验证场景是"完成后"转黑,该截图不构成反证。
- **v11 修复(判例兑现:不再猜第五条,走 CA)**: 分层结构不变(底=实体色全程可见 + 顶=峰色副本),只把"带怎么动"换成 `CABandMaskView`(UIViewRepresentable):UIView 的 `mask` = CAGradientLayer(clear→白→clear, 层宽 2×视图宽, locations 0.425/0.5/0.575 = 亮带恰 0.3×视图宽),`CABasicAnimation(position.x, -0.15w→1.15w, 2.8s, repeatCount=∞)` 平移。**CA 动画挂在 render server 独立时间线**:不经 SwiftUI 事务(disablesAnimations 管不着)、不要求 body 重算(TimelineView 失效与否无关)。layoutSubviews 拿到真实宽后幂等启动; dismantle 时 removeAllAnimations。
- **亮带几何沿用 v10 标定**: 0.3×字宽 / 1.5×跨度 / 2.8s / 左→右 / 实心峰色 mix(base 30%, white)。API `sweepShimmer(base:period:)` 不变,两调用点零改动。
- **🔴 判例(可复用)**: ①SwiftUI 声明式"每帧重算"路线在同一视觉功能上连续两版证伪后,该功能降级到 UIKit/CA 层实现,不再在声明式层内变花样;②装机反馈要先做**语义甄别**再认领 bug——同一截图里"运行中的灰尾"是正确行为,不能顺着用户"还是灰的"就回去改已修对的逻辑。
- **死隔离申报**: 呈现层-only 单文件;新增 UIViewRepresentable 属仓内既有模式(Agent 区域已有多处)。回归 = ①聊天流 Thinking 扫光 ②汇聚页标题扫光 ③文字选中复制(peak 层不吃点击) ④深浅色 ⑤VoiceOver 不双读 ⑥sheet 打开后消息完成,灰尾转黑(TAIL-GRAY-FIX 顺带验证)。
- **验证**: 编译靠 CI;装机判据 = 同框录 5s 抽帧。**若 v11 仍不出:停止盲修,必须先拿录屏**(静态带=CA 没启动/无带=mask 通路仍断/带在动但看不见=色值),下一手改为在测试页放一个超大对比度探针(红底白字 5s 扫光)分离"机制死"与"参数弱"。
- **CI 首红(43deaae, 8m4s)修复**: `ShimmerText.swift:79 cannot assign value of type 'CAGradientLayer' to type 'UIView'` — iOS 18 SDK 起 UIView 自带 `mask: UIView?` 属性,`v.mask = band` 解析到它而非 CALayer 的 mask。改为 `v.layer.mask = band`。**判例**: 给 UIView 挂 CALayer mask 一律写 `layer.mask`,裸 `.mask` 在新 SDK 有 UIView 重载歧义。

### SHIMMER-V11.1 — v11 装机仍无扫光，审出"构造性不可见"根因：mask 层根本没像素(Qoder, 2026-09-19 pp 实装后反馈)

- **实机反馈**: v11(43deaae+7cff100 CI 绿)装机后依旧零扫光。
- **根因(代码审读即判死, 无需装机)**: `v.layer.mask = band` 语义用反——layer.mask 是"用 band 的 alpha 裁剪**宿主视图自绘内容**"; 宿主 `backgroundColor=.clear` 无内容 → 裁了个空 → representable 渲染输出处处 alpha=0 → SwiftUI `.mask()` 全遮 → 峰色副本 100% 不可见。亮带要从"裁剪层"变成"被画出来的层"。
- **修复(一行半)**: `v.layer.addSublayer(band)` + `v.layer.masksToBounds = true`。band 本身 clear→白→clear 渐变自带 alpha, 画出来即 mask 所需灰度; CA position.x 动画原样保留(render server 时间线)。几何/周期/峰色全不动。
- **判例**: UIView 层树里"谁裁谁"方向: `layer.mask`=拿参数层裁本层内容; 要"本层内容=渐变本身"用 sublayer。SwiftUI `.mask(View)` 读参数视图的**渲染 alpha**——放进 mask 位置的 UIViewRepresentable 必须自己**画**出灰度图, 空白视图套 mask 层 = 恒全遮。
- **止损条款(仍有效)**: 若 v11.1 仍不出 → 停止盲修, 必须拿 pp 5s 录屏抽帧, 并按计划上红底白字对比度探针。

### SHIMMER-V12 — 放弃自研，移植 Facebook Shimmer 机制（UILabel + 文字渲染 alpha 掩膜亮带）(Qoder, 2026-09-19 pp：「你能不能去找开源项目？」)

- **装机反馈**: v11.1（CI 517de51 绿）装后依旧零可见。按止损条款停止自研路线盲修，转开源调研。
- **调研结论**: SwiftUI 系 shimmer 库（Exyte/SwiftUI-Shimmer 等）全部用 `withAnimation(.linear.repeatForever)` 驱动渐变端点——正中本项目已实锤死因①（cell 宿主 disablesAnimations 事务吞动画），整体排除。唯一与两大死因同时免疫的是 **FBShimmeringLayer 机制**（facebook/shimmer-ios，十年验证）：**不给文字重上色**，UILabel 照常渲染底色，其上盖一条白色渐变亮带，亮带 `mask` = 文字自身渲染副本的 alpha → 亮带只在字形像素上显形。
- **v10 根因② 从此消失**: 颜色直接写进 UILabel（attributedText 级），不经过 SwiftUI foregroundStyle 穿透链路——v10.1/v11/v11.1 三代分层结构其实全压在"外层 foregroundStyle 能穿透自带样式的 Text"这条未证假设上（Text 自带前景色时外层样式**不生效**是文档化行为 → 峰色副本与底色副本同色 → mask 动了也看不见）。v12 不再需要这条假设成立。
- **实现**（ShimmerText.swift 全重写 + 2 调用点换 `ShimmerLabel`）: ①host UIView 内 UILabel(14pt/17pt 沿用标定字体色)；②band=CAGradientLayer(clear→白→clear, locations .35/.5/.65, opacity 0.62≈峰色标定值) `addSublayer` 盖在 label 之上；③`band.mask = textMask`，textMask.contents = `UIGraphicsImageRenderer` 渲染的 label 图像（**UIImage 本体非 cgImage**，防 contentsScale 放大 N 倍坑）；④动画 = 两条 CABasicAnimation 同 duration 平移 `startPoint/endPoint`（span 恒 1.0 纯平移；frame 恒等文字矩形 → mask 全程对齐，无需 v11 式整层位移）；⑤文本/字体/色/traits 变化经 key 门控重渲掩膜，颜色比较用 `!=`（`!==` 会被 UIColor(Color) 动态包装每次误判，自审抓出）。API 换形：`sweepShimmer` modifier 退役（仓内仅 2 调用点），新增 `ShimmerLabel(text:uiFont:baseColor:textAlignment:)`，两处补 `.fixedSize()` 防 representable 被拉宽（否则 0.3×行宽的带失去"局部点亮"观感）。
- **判例**: ①同一视觉功能 ≥3 版失败即停止自研变体，转开源机制比对（用项目已实锤死因清单当筛子）；②"给文字提亮"在 SwiftUI 里不可依赖外层 foregroundStyle 覆盖 Text 自带样式——要么调用点交出颜色所有权，要么走 UIKit 渲色；③mask 方向三连：v11 裁空白（死）、v11.1 画了但两层同色（死）、v12 画亮带+文字alpha裁形（FB 原样）。
- **死隔离申报**: 呈现层 3 文件（ShimmerText/ToolActivityGroupView/ThinkingDetailOverlay），无新文件、不碰数据/SSE/聚合器；Grok 呼吸式 shimmerText 独立路径未动。回归 = ①聊天流 Thinking 扫光 ②汇聚页标题三态文案+扫光 ③深浅色 ④Thinking 行与计时器基线对齐（UILabel vs Text 度量差 ≤2pt，装机目测）⑤VoiceOver 单读 ⑥长文不抖动（elapsedCounter 每跳 updateUIView 不触发掩膜重渲=key 门控）。
- **验证**: CI 编译 + 装机。**若 v12 仍不出**: 必须拿 pp 5s 录屏（静止亮带=CA 死/局部发白=掩膜错位/全无=组件没进视图树），且红底白字探针上包。

### SLOT-DONE-TOOLGUARD — 活动槽完成态判定补「工具在飞」条，治回合边界塌成入口行（Qoder, 2026-09-19 pp：「制定解决方案」→「可以」）

- **File**: `src/ios/Views/Chat/ToolActivity/TurnActivityAggregator.swift`（+17：`isDone` 加一条 guard + 判例注释）。
- **症状（pp 截图）**：调用工具途中，用户气泡「搜索网页 30s」与上一条的「Thinking · 62秒」点阵行挤在同一条带上；退出聊天页重进又复现。
- **根因**：`TurnActivitySegment.isDone` 原式只有 `closedByContent || !isMessageActive` 两条，**漏了「段内工具仍在飞」**。回合边界（`[StreamDiag] done(endTurn)` → 下一次 `req#N DISPATCH`）`isMessageActive` 瞬断 → 还在跑的活动槽被判完成 → 渲染塌成入口行高度（真机 24pt vs 运行槽 125pt）→ `MessageListLayout.prepare()` 按塌后高度排 frame → 点阵行顶进上一条消息的条带。
- **实锤（pp 08:50–08:51 装机日志）**：两次 `[ThinkingCollapse] HIT frameH=24.0 → POST 125.0 delta=101.0`，时刻 `08:51:39.289` / `08:51:44.542`；对应 `req#8 DISPATCH 08:51:39.293` / `req#9 DISPATCH 08:51:44.543` —— **差 4ms 与 1ms**。24.0 恰等于 `newSkinActivitySlotDoneHeight`（`CollectionViewMessageListV3.swift:3817-3820`）。
- **同一谓词的第二份实现早已修过、这份没跟上**：`ThinkingDetailOverlay.isSegmentRunning`（115-132 行，`edfd086` 09-19 灰尾修复）按 ①closedByContent ②消息终态 ③**段内工具 active** 三条实现，注释明写「语义与 TurnActivitySegment.isDone 逐条对齐」——但聚合器只落了 ①②。**驱动布局高度的是聚合器这一份**，所以塌的是列表而不是详情面板。本改动 = 把落后的那份对齐上去，不是新造语义。
- **只判 `isToolActive` 不判 `isThinkingActive`**：`isActiveThinking` 的定义式里带了 `isActiveMessage`（`ToolActivityGroupView.adapt` 393 行），断言它正是本处要防的瞬态 → 死条件。`toolState == .active` 来自 `block.toolStatus`（`.streaming/.running`），不受 `isActiveMessage` 影响，故能穿越瞬断。
- **连带效果（安全方向）**：`newSkinActivitySlotEstimate`（`CollectionViewMessageListV3.swift:3858`）在工具在飞时改判 `isDone=false` → 返回 `nil` → 交回经典估算，即注释原话「宁可高估，不猜运行槽」。
- **死隔离申报**：纯判定函数，不改数据/SSE/agent 链路/布局记账；无新文件。回归 = ①回合结束后活动槽必须从点阵行收口成入口行（**若工具态卡在 `.running` 不退，点阵行会永转，这是本改动唯一新风险**）②`ToolActivityGroupView:166 onChange(segment.isDone)` 的收口动画与 `.thinkingBlockToggled` 广播仍触发 ③非新皮肤不受影响（`ToolRenderStyleStore.current != .new` 时估算直接 return nil）。
- **验证**：待装机。日志判据 = `[ThinkingCollapse]` 中**不再出现** `frameH=24.0` 紧跟 `DISPATCH`；气泡与点阵行不同排；回合结束后点阵行正常收口。
- **[doris 09-19 补注] 「逐条对齐」有实现顺序偏差**：本实现把「工具在飞」排在「正文已收口」之前，与基准（closedByContent 优先）相反——「正文已回 + 工具仍在飞」交叉态会继续转槽而非收口。已由下节 `SLOT-DONE-TOOLGUARD-ORDER` 修正顺序；工具守卫增量本身保留。

### TOOLBAR-DROP-PROBE — 症状一（工具条掉到输入框下面）只加探针不改逻辑（Qoder, 2026-09-19）

- **File**: `src/ios/Views/Chat/ToolLiveSheet.swift`（+52：`BottomBarProbe` enum + 胶囊/容器两处 `onGeometryChange`）、`src/ios/Views/Chat/AIChatView.swift`（+6：输入框回调 + `onDisappear` 上报）。
- **为什么不直接改**：症状一的机制已连续三次证伪，全部记档以免下轮重走 —— ①「两块玻璃经 GlassEffectContainer 合并」→ 全仓 grep `GlassEffectContainer`/`glassEffectID` 零命中；②「`.frame(minHeight:38)` 无上限 → 胶囊被 ZStack 拉到 65」→ `.frame(minHeight:)` 只 clamp 不 fill，HStack 回内容理想高 ≈28 → 结果就是 38，且 pp 目视确认缩略图/胶囊关系正常；③「`capsuleProtectedFrame("inputBar")` 把 VStack 钉成输入框高」→ 查定义（`VoiceProviderResolver.swift:326-350`）只是 `.background(GeometryReader)` 上报位置，不约束尺寸。静态读下来 `VStack { floatingToolPreview; inputBar }` 顺序写死、外层 `.overlay(.bottom)`，找不到任何能把工具条放到输入框下面的分支。
- **探针设计**：`bar`（工具条容器）/ `pill`（玻璃胶囊）/ `input`（输入框）三者 global frame 合成一行打进 `InputBarLayout`。判据字段 `gapBar`/`gapPill` = 输入框顶 − 该元素底，**负值即"布局真的掉下去了"**；`gap` 正常而肉眼仍觉得掉了 → 是层序（被压住）问题，方向完全不同。**action 内不回写任何布局状态**（`[T-ios-geometry-observer-crash]` 同条约束）。
- **节流的一个坑（已修）**：变化落在 250ms 窗口内时**不能先写 slot 再丢弃** —— 错误状态常是"一次几何回调之后不再变化"的稳态，先写就把那一帧永久吞掉。改为节流时保留旧值，下个窗口必补打。
- **已排除的挂载点**：`FloatingToolBar(` 全仓两处，第二处 `ToolLiveSheet.swift:193-208 FloatingToolPreviewContainer` 是 `private` 且零调用 = 死代码；活挂载点唯一 = `AIChatView.swift:2931`。
- **🔴 临时件，定位后整体删除**：删 `BottomBarProbe` enum + 三处 `onGeometryChange`/`reportBar(.zero)`/`reportInput` 调用点。
- **验证**：待装机。pp 正常用一遍发日志，不需录屏。

### SLOT-DONE-TOOLGUARD-ORDER — isDone 守卫顺序改回基准（closedByContent 优先）·11b7561 follow-up（Doris, 2026-09-19，pp：「交给你处理」）

- **File**: `src/ios/Views/Chat/ToolActivity/TurnActivityAggregator.swift`（isDone 两行顺序对调 + 注释）。
- **Why**: 11b7561 把「工具在飞」提到「正文已收口」之前 → 与 `ThinkingDetailOverlay.isSegmentRunning`（基准顺序：①closedByContent ②工具 active ③消息态）相反，属新语义而非对齐，且与 pp 09-17「回复了正文=阶段完成」相悖。本提交恢复基准顺序；两份实现重新逐条一致。
- **覆盖不变**: 纯「工具在飞」窗口（closedByContent=false）仍不判完成，11b7561 的有效增量保留。
- **死隔离申报**: 纯判定函数两行顺序；无新文件、不碰数据/SSE/链路。
- **回归**: ①「正文已回+工具在飞」交叉态收口为入口行（与基准一致）②纯工具在飞窗口槽继续转 ③同 11b7561 其余回归项。

### SLOT-FRESH-MEASURE — 活动槽「首测竞态」治本 + 重进自愈 + [SlotMeasure] 探针（Doris, 2026-09-19，pp：「交给你处理，必须解决问题」）

- **Files**: `ToolActivityGroupView.swift`（init 预置 carouselIds / onAppear 播种后补发重测 / 打点）、`MessageListLayout.swift`（提交/解冻两处打点）。
- **症状（pp 09-19 截图）**: ①任务进行中用户气泡与「Thinking · N秒」同行（实测标题墨迹 42-55.3pt、气泡 38.7-75.3pt）②工具行探进浮动玻璃工具条带（tool3 行 146.7-154pt vs 缩略图带 128-192pt）。
- **根因**: 活动槽单元格「已提交高度」塌成 **24pt**（≈标题行高），内容仍 125pt → 单元格按 24pt 排位、内容在框内**居中**渲染 → 上下各溢出 **(125−24)/2 = 50.5pt**（像素级吻合：槽内容 37→162、逐行间距 33.7 与运行槽常数一致）。实锤 = `[ThinkingCollapse] HIT frameH=24.0 → POST 125.0 delta=+101.0` @08:51:39.289 / @08:51:44.542；两次前 0.7-2.7s 均「退出聊天页→马上重进」（列表重建 → 重造格首测落在事件行空启动窗口 → 24pt 写进 heightCache；工具运行期无 segment 变化/无流式 flush → 补测通道全静默 → 挂到下一次工具事件才修回）。
- **修复**: ①治本=init 预置 `carouselIds`（首帧即完整运行槽，首测量不到空槽）②保险丝=onAppear 对运行中段补发 `.thinkingBlockToggled`（复用既有 HIT 重测链，1-2 帧修回，不再依赖"下一个工具事件"）③探针=[SlotMeasure]×3（swift 播种 / commit / thaw，明确"定位后删除"）。
- **与 Qoder 笔关系**: 其 isDone 守卫治不了本机制（重进→首测 24pt 与完成判定无关）；其 BottomBarProbe 量错对象（工具条/胶囊/输入框实测均正常，掉的是列表格高）。两探针留本版供数据存档，定位后一并删除。
- **死隔离申报**: 呈现层两文件；不碰数据/SSE/agent 链路/桥；无新机制（全部复用既有通知链与测量流程）；`ToolActivityGroupView(` 全仓构造点唯一（AssistantBlockView:186），新 init 带默认参不破坏调用；`AppLogger` 为同 target 既有设施。
- **回归**: ①任务中反复「退出重进」×10 不塌不溢出 ②长工具运行期稳定 ③收尾边界不闪、入口行正常收口 ④Stop 正常 ⑤贴正文/扫光 v12/轮播/计时/汇聚页不回退 ⑥本地+远端会话各一遍。
- **验证**: CI 编译 + 装机日志（[SlotMeasure]：首测 cellFrameH≈125；重进后不再 `frameH=24.0` 紧跟 `DISPATCH`）。
- **补记（09-19 独立审查修正）**: onAppear 补发加**视图外冷却门闩**（`lastRemountPing` ≥1s）——config 替换会重置 @State 并重跑 onAppear（本文件 [pp 09-18 根因②] 自述），不加闩会形成"通知→reconfigure→新子树 onAppear→再通知"的运行期无界回环（hosting-graph 重入=仓内登记崩溃面）。审查代理发现（Q2 项），随下笔提交修复。

### SLOT-FRESH-MEASURE-2 — 重挂载首帧"行缓存"兜底，治"退出重进闪一下"（Doris, 2026-09-19，[SlotMeasure] 实证）

- **File**: `src/ios/Views/Chat/ToolActivityGroupView.swift`（+`lastRowsCache`/`rememberRows` 静态行缓存 + 统一数据源 `displayRows`（实时优先/缓存兜底）；init 播种、onAppear、onChange、ForEach 四处统一走 displayRows；探针加 `cached=` 字段）。
- **实证（pp 10:50:54–10:51:21 完整日志）**: 每次"退出重进"（列表重挂载）活动槽格先提交错高 **24.0**（`[SlotMeasure][commit] idx=200 40.0→24.0`），~25ms 后被自愈链修回 **91.3/125.0**（`HIT frameH=24.0 → POST 91.3`），单场测试共 14 次同类 → 视觉=帧级闪塌。首挂载时 `carouselSeeded=/rows=` 均正确 → 错误发生在"首次 config 数据尚未就绪"的首帧（上一版 init 播种取到空）。冷启动另有一条支线：isProcessing 未同步时按 done 渲染（24.3），~1.4s 后修回（登记待办）。
- **修复**: 静态缓存"上次成功渲染的行"（引用，保持实时状态）；首帧/重建时实时为空则用缓存播种并渲染（实时非空不用缓存）；onChange 实时瞬空时不清行；FIFO 上限 64 anchor。
- **死隔离申报**: 仅本文件（呈现层）；无新机制（静态缓存同 `startCache` 模式）。
- **回归**: ①任务中反复退出重进 ×10：槽不再闪塌（不应再出 `40.0→24.0` 类提交）②离场行动画/轮播不受影响 ③冷启动支线观察 ④其余同 SLOT-FRESH-MEASURE。

### SLOT-COLDSTART-PENDING — 冷启动"中断待恢复"回合不再渲染为完成态入口行 + 计时冻结（Qoder, 2026-09-19，pp 批准第 4 轮，Doris 主编）

- **Files**（6 处，全为呈现/判定层）:
  - `src/ios/Agent/Chat/AIChatViewModel.swift`（+18：`interruptedPendingResume` 内部纯 var（非 @Published）+ `canResume` didSet 一处随清）
  - `src/ios/Agent/Chat/AIChatViewModel+Persistence.swift`（+6：`recheckCanResumeFromHistory` 检测分支置位，唯一写入点，先于 `canResume = true`）
  - `src/ios/Agent/MessageList/MessageListInfrastructure.swift`（+4：bridge 新增 @Published 字段）
  - `src/ios/Agent/MessageList/CollectionViewMessageListV3.swift`（+38：updateBridge 同闸写入 + `[ColdStartDiag]` 临时探针；updateLastCellBridge prev 清理配套；`FooterHeightShape` 加「不入列」锁死注释；新皮肤槽估算加 `interruptedPending` 参数 + seed 调用点同判据传入——isLast 与 `vm.messages.last` 同源）
  - `src/ios/Views/Chat/AssistantBlockView.swift`（+5：消息级参数默认 false，仅透传给 ToolActivityGroupView）
  - `src/ios/Views/Chat/ToolActivity/ToolActivityGroupView.swift`（+45：init/属性新增；`running` 式扩一条；onAppear 冻结 + 补发条件 `!isDone`→`running`；onChange 双向（→true 补冻结+纠高重测、→false 续走）；`[SlotMeasure]` 探针加 `slotRunning=`（视图渲染真值）+ `interrupted=` 字段）
- **症状（pp 装机 10:50:53–56 日志实证，Doris 已核）**: 任务进行中冷启动 → 打开会话，未完成回合的活动槽渲染成完成态入口行（≈24.3pt、「思考结果」语义），点「继续」后才切回运行槽。`[SessionLoad] detected interrupted agent loop, canResume=true`（54.406）早于首帧绑定（54.5），但视图完成判定只读 `isMessageActive`（=isLast && isProcessing），"中断待恢复"没进判定。
- **根因**: 同上——判定信号缺一路，非时序竞态。
- **信号选择（反向约束的解法）**: `vm.canResume` 不可直接用——进程内 Stop（Case1 工具取消/Case2 文本取消）、断流/maxTokens/refusal/turn 上限等 12 处都置 true，会误伤"停止的回合保持现状"。改用**专用标记**：仅 `recheckCanResumeFromHistory` 的检测分支（load/缓存重开时从持久化尾巴判定）置位。穷举核验：①进程内 Stop 不走该分支 → 标记恒 false → 外观不变 ②同进程"Stop 后退出重进"命中 `else if !canResume` 门外（canResume 已 true）→ 不置位 → 外观不变 ③清除收进 `canResume` didSet 唯一汇合点（resume()/新回合/队列 drain/正常完成/尾巴不再中断，全路径覆盖，永不残留）④bridge 侧再与 `canResume && !isProcessing && !trackerActive && error==nil` 同闸（与 resumeBanner 判据对齐），非末条消息恒 false。
- **修复形态（按任务首选）**: 中断待恢复期间活动槽渲染 `runningSlot`（信息上=未完成）+ 计时冻结——复用 `ThinkingRunClock.pause/resume`（「错误冻结」先例同机制），点「继续」→ `isProcessing` 翻转令 `isDone` 也转 false，running 全程 true → 无缝切回、秒数续走。`closedByContent` 段不受标记影响（标志是消息级，同消息内已收口历史阶段不得复活）。估算层同步改判（`interruptedPending` 开放段 → 交回经典估算，与运行中同源，不预置 24.3pt）。
- **与前四批交互**: 不碰 `isDone` 本体（05255c0/11b7561 语义不变，扩的是视图层 `running`）；补发门闩 `allowRemountPing` 原样复用（含晚到翻转的纠高重测），冷却仍单次收敛（ce70682/84858b5/1ed5af3 不回归）；行缓存/displayRows 对中断槽照常工作（首帧播种取已加载 blocks）。
- **🔴 临时探针（定位后删除）**: `[ColdStartDiag]`（updateBridge 值变化时单行）+ `[SlotMeasure][swift]` 的 `interrupted=` 字段。装机判据：冷启动首帧 `interrupted=true running=false→视图 running`，点继续后 `interruptedPendingResume true→false` 一行。
- **死隔离四问**: ①另一端（远端 agent/SSE/agent 循环/桥/持久化）零触碰——只读 VM 既有状态做呈现；②共享文件（updateBridge/V3）改动全部 `interruptedPendingResume` 门控，false 路径逐字节等价现状；③无新机制（标记=pause 门闩、冻结=错误冻结、重测=thinkingBlockToggled、清除=canResume didSet 同型先例 `isRedetectingInterruptedTail`）；④回归清单见下，本地/远端会话各一遍。
- **回归**: ①冷启动中断回合首帧即运行槽（冻结秒数）、点继续无缝续走 ②**用户停止回合外观不变**（进程内 Stop 必测；Stop→退出→重进 亦不变）③正常进行中/历史已完成回合不变 ④重进三批修复不回归（判据：不再出 `40.0→24.0` 类提交；`[SlotMeasure]` 首测 ≈125/91）⑤几天前老中断会话=运行槽冻结外观（合理，可点继续）⑥计时冻结/续走与错误冻结互不解锁（error 非空时 onChange 不动表）⑦经典皮肤零影响（估算/视图均默认 false）。
- **验证**: 本机无 Swift 工具链——**待 CI 编译验证**（重点：6 文件作用域/memberwise init 参数顺序/调用点：ToolActivityGroupView 构造点全仓唯一 AssistantBlockView:190，AssistantBlockView 两调用点 ChatMessageViews:501 靠默认参不破坏）+ 装机按 ①–⑦ 走查 + `[ColdStartDiag]` 日志。
- **审查记录（09-19）**: 三轮自查（正确性/影响面/一致性）+ 独立对抗审查（子代理）全过。对抗结论：无致命/重要代码缺陷；次要四项已处置——估算与 bridge 的 isLast 同源化（trackerActive 差量在估算层不可达：该窗口 vm.canResume=false，已注释锁死）、`slotRunning=` 探针字段、`FooterHeightShape` 锁死注释、晚到翻转的 onChange(true) 冻结+纠高重测兜底。攻击失败面：12 处 canResume=true 全不置标记、清标记路径穷举无残留、resume 同 tick 三翻转无可渲染中间帧、补发经门闩无风暴、pause/resume 幂等与错误冻结互不解锁。
- **待确认项**: A)「工具执行中按 Stop → 杀进程 → 冷重启」的尾巴与 crash 在持久化层结构不可分（Case1 无停止标记；Case2 文本停止有 system-reminder 且本就不判中断）→ 该子集会按"中断待恢复"显示冻结运行槽；如需彻底区分需在 Stop 落盘时加标记（数据层，本批未动）。B) 汇聚页 `ThinkingDetailOverlay.isSegmentRunning` 未接入本标记（点中断槽进详情，面板按其自身判据显示）——任务范围外，未动。C) 中断槽秒数从"打开会话首帧"起冻结显示为 0（计时起点缓存是内存态，冷启动后原始起点不可恢复），续走后从冻结值续走。

### SLOT-LOOP-BREAKER + SLOT-HEIGHT-FLOOR — 断"修复循环" + 运行槽高度地板（Doris, 2026-09-19，#162 循环实证）

- **Files**: `ToolActivityGroupView.swift`（`repairSuppressUntil`/`noteProgrammaticReconfigure`/`slotFloor`；allowRemountPing 加抑制窗；运行槽 `.frame(minHeight:)`）、`CollectionViewMessageListV3.swift`（handler 入口登记抑制）。
- **实证（pp 11:19–11:34 #162 全量日志，Doris 核）**: ①**自动循环**：修复 reconfigure → 重建 → onAppear 补发 → reconfigure……约 **1.3s/圈**持续（app 后台悬挂也持续 45s+；门闩只限速未截断——此前两份静态审查"已截断"结论被实测推翻；11:21–11:22 段 `HIT frameH=24.0` ×45+/分钟）。②每圈首测仍 = 24.0（`carouselSeeded=3 cached=3` 也拦不住——重建过渡帧的测量时序早于 @State 就位），塌陷相位即 pp 截图来源。
- **修复**: ①`noteProgrammaticReconfigure`：修复侧 reconfigure 前登记 2.5s 抑制窗，窗内 onAppear 补发跳过 → 循环终止（真实重进在窗外观测照常补发）。②`slotFloor`：运行槽 `.frame(minHeight: 24+33.7×min(displayRows.count,3))`——地板挂 displayRows（含缓存）不依赖 @State 时序 → 冷启动/重配/重建任意一帧都量不到 <地板，"过渡态 24pt"从根上不可提交。
- **死隔离申报**: 呈现层两文件；零新机制（复用既有 static 缓存/门闩模式）；不碰数据/SSE/agent 循环/桥；Qoder 冷启动批（2f65c44）语义不动，其"中断待恢复"槽走 runningSlot → 地板同样生效。
- **回归**: ①任务中退出重进 ×10 不再闪塌（日志不再出 `40.0→24.0` 类提交）②循环断（不再有 ~1.3s 周期 ThinkingCollapse HIT 流）③完成态/历史回合外观不变 ④新段起步（无行）仍 24pt 合法 ⑤高度不虚高（地板=真实高度同源常量）。

## FONTS-2 — body line spacing coefficient ×0.25 → ×0.5（2026-09-19，pp 拍板：“行”）

- 背景：与 Claude 逐像素对账——moonveil 行距/字号 1.44× vs Claude 1.73×（紧 24%）；公开资料舒适区：中文 1.5–1.8×、Web 1.5–1.6×。
- `SelectableMarkdownView.swift`：`bodyLineSpacing` 系数 0.25→0.5（行距比 1.44→1.69，对齐 Claude 1.73 且保留微调余量；系数制——字号档位变化时行距等比跟随，比例恒定）。
- `CollectionViewMessageListV3.swift`：列表高度估算 `lineHeight` 1.4→1.7（同步渲染比例，宁高勿低）。
- 影响面（隔离声明）：正文/列表/引用行内行距同步变宽；块级公式上下留白随变（罕见场景，暂观察）；两端模式（本地/Remote）共用渲染层=预期同步；不触碰状态机/数据流/缓存（内存缓存，app 重启重建，无需版本 bump）。
- 不动面：段落边距（0/12 固定值）、列表项间距（listItemTopMargin ×0.25 按原样，属另一视觉参数）、标题/表格边距、代码块行距（固定 4）、字号体系（档位不变，FONTS-1 保持）。
- 回归项：正文行距≈24.5pt（XS 档）、估算与渲染同源、扫光/工具详情/塌陷机制零触碰（未涉及文件）。

## SPACING-1 — inter-cell spacing 8 → 22（2026-09-19，pp：“工具和文字之间的距离是不是没调”）

- 背景：FONTS-2 行距变宽后，块间（工具区/思考行↔正文）空白仍为旧值；与 Claude 对账：思考行↔正文空白 Claude ≈104px(34.7pt) vs moonveil ≈63px(21pt)。
- `MessageListInfrastructure.swift`：`itemSpacing` 8→22（+14pt，块间总空白 21→35pt ≈ Claude）。
- 隔离声明：layout `prepare()` 与高度累计自动跟随（单一参数）；footer-hug 策略不变；两端模式共用布局=预期同步；不触碰状态机/数据流。
- 不动面：块内 padding（各组件自有）、消息内行距（FONTS-2）、footer 紧贴策略。
- 回归项：块间空白≈35pt；消息间距同步拉宽（统一+可微调）；流式布局无塌陷；扫光/工具详情零触碰。

## CLASSIC-FREEZE-1 — classic skin keeps pre-alignment parameters（2026-09-19，pp：“旧版能不能保持原来的参数”）

- 语义：FONTS-2（行距 0.25→0.5）与 SPACING-1（itemSpacing 8→22）**仅对 new 皮肤生效**；classic 完整保持改动前参数（行距 0.25、间距 8）。
- 改动：`SelectableMarkdownView` bodyLineSpacing 按皮肤分叉；`CollectionViewMessageListV3` 估算器分叉（1.7/1.4）+ `handleToolRenderStyleChanged` 补 itemSpacing 更新与文本缓存失效；`MessageListInfrastructure` itemSpacing 初值按皮肤。
- 隔离声明：皮肤=**显式 gate**（ToolRenderStyleStore）；切换路径沿用既有 “skin switch → full invalidation” 链 + 对称字号变化链（invalidateAttributedStringCaches）；两端模式共用=预期同步；不触碰状态机/数据流。
- 回归项：切换皮肤后行距/间距即时正确（含历史消息）；new=0.5×+22pt，classic=0.25×+8pt；流式无塌陷；扫光/工具详情零触碰。

## TOOLSPACING-1 — tool row spacing setting（2026-09-19，pp：“新版工具之间的间隔…如果是固定值就在设置加一个调节”）

- 背景：新版工具活动行间距（runningSlot VStack spacing）为硬编码 18pt（固定值，不随字号动态）；现加设置可调。
- `ToolActivityGroupView`：@AppStorage("toolRowSpacing")（默认 18）消费；`ContentView` 设置（Tool Status Bar 区）加 Slider（8–30pt，step 2）；新通知 `.toolRowSpacingChanged` → Coordinator 复用全量重排链（handleToolRenderStyleChanged）。
- 隔离声明：新 UserDefaults key 为显式 gate；仅新版渲染消费（classic 胶囊不走该组件）；两端模式共用=预期同步；不触碰状态机/数据流。
- 回归项：拖动滑杆行间距即时变化（含历史消息）；重启保留；默认 18pt 与改动前一致；classic 模式零影响。

## TOOLSPACING-2 — block spacing setting, both sliders new-skin-only（2026-09-19，pp：“两个都做可调节，只针对于新版”）

- A（已有 TOOLSPACING-1）：工具行间距滑杆（Tool Row Spacing，8–30pt，默认 18）——天然仅新版（classic 胶囊不走该组件）。
- B（本批）：块间距滑杆（Block Spacing，8–40pt，默认 22）——仅 new 皮肤取可调值，classic 固定 8（CLASSIC-FREEZE-1 保持）。
- 实现：`ToolSpacingSettings`（显式默认值的 UserDefaults 读取）；`MessageListInfrastructure` 初值 + `handleToolRenderStyleChanged` 均读 helper；新通知 `.blockSpacingChanged` → 复用全量重排链。
- 隔离声明：新 UserDefaults key 为显式 gate；classic 固定值零影响；两端模式共用=预期同步；不触碰状态机/数据流。
- 回归项：两滑杆各自实时生效（含历史消息）；重启保留；默认值（18/22）与改动前一致；classic 零影响。
- **2026-09-19 追加（pp拍板）**：Block Spacing 默认最终定 8（恢复历史值；途中曾定 22→ 11）；滑杆 step 2→1。

## SLOT-ERROR-RETRY + SLOT-ROW-UNION — 报错待重试不收口 + 工具行并集自愈（Qoder, 2026-09-19，pp 真机双 bug 报告，session F67FB197）

- **Files**: `ToolActivityGroupView.swift`（init/属性新增 `errorPendingRetry`；`running` 式扩一条；onAppear 冻结扩分支；新 `onChange(of: errorPendingRetry)`；`renderIds` 并集纠偏 + ForEach 数据源替换）、`AssistantBlockView.swift`（透传参数，默认 false）、`MessageListInfrastructure.swift`（bridge 新 @Published 位）、`CollectionViewMessageListV3.swift`（updateBridge 写入 + updateLastCellBridge 清零 + cell 透传）。
- **Bug A 症状（pp 装机 16:49:56–59 日志实证）**: 上游 422 报错 → 整槽 125.3pt↔24.3pt 来回翻两轮（报错塌、重试弹回、正文收口），"thinking 也随着工具一起跳动"。
- **Bug A 根因**: 422 走 send() 的 catch（AIChatViewModel:2704–2733）——写 `last.error`、**不置 canResume**、epilogue 置 `isProcessing=false` → `isActiveMessage=false` → `segment.isDone=true` → 视图塌 entryRow；`retry()` 清 error 重转 → 弹回。视图层无"错误待重试"信号可用（`isActiveMessage = isLast && isProcessing`，报错瞬间即 false）。
- **Bug A 修复（任务选项 1）**: 新增消息级标志 `errorPendingRetry = isLast && message.error != nil && !vm.isProcessing`（updateBridge 与 isActiveMessage 同一次调用写入 → 同帧生效、无中间塌缩帧；与 interruptedPendingResume 互补，那条要求 error==nil）。`running` 消费该标志：未 closedByContent 的段在"错误待重试"期间保持运行槽；计时冻结=既有 `message.error` onChange pause 链 + onAppear/标志双向 onChange 补冻结（冷启动读到错误尾巴也首帧冻结）。撤销：重试续走（段本就活跃）或用户开新回合（不再是尾部 → updateLastCellBridge 直写清零）→ 正常收口，不永久卡运行态。
- **Bug B 症状**: 工具运行中 live 只渲染 2 行（高度够 3 行），退出聊天页重进才 3 行齐全。
- **Bug B 根因**: `carouselIds` 三个赋值时机（init 播种/onAppear 同步/`onChange(of: eventBlocks.map(\.id))`）共享同一结构性窗口——结构体在 init 取数与首帧 body 评估之间数据换血时，onChange 只比较相邻两次评估、初评即新值 → 变化沿丢失，队列停在旧 id 集；`ForEach(carouselIds)` 查不到即静默不渲染（无 else/占位），而 slotFloor 挂 displayRows 按数据行数撑高 → 恰好表现为"高度够、行数少"；只有真重建（重进）重新播种才补齐。
- **Bug B 修复**: 渲染层 `renderIds = displayRows ∪ carouselIds` 纠偏——数据行当帧必渲染（有几行数据渲染几行），队列多出的 id 留尾部（离场动画依赖其短暂存在，行为不变）；稳态 queue ≡ data 时并集恒等 carouselIds → 轮播动画路径零扰动。纯 computed、零新增通知/reconfigure，不触碰 allowRemountPing/noteProgrammaticReconfigure 冷却机制。
- **死隔离申报**: 仅新版渲染路径（classic 不走 ToolActivityGroupView；`ToolRenderStyle` 分叉不动）；新参数全部默认 false（SwiftUI 列表路径 ChatMessageViews:501 行为零变化）；不碰 `TurnActivityAggregator.isDone` 三条件语义；不碰数据/SSE/agent 循环/持久化；正文=阶段完成语义保留（两条 pending 分支均要求 `!closedByContent`）。
- **回归项**: ①422 报错→重试期间槽保持 125pt 不再瞬翻（日志判据：不再出现同 cell `125.3→24.3→125.3` 1.5s 内往返）②重试成功后秒数续走外观无缝（注意：settle 先于 resume 落终值是**既有行为**，本批未改，见自审报告"已知风险"）③用户开新回合后旧槽正常收口成 entryRow ④正文到达收口路径不变（16:49:59 那条语义保留）⑤工具行 3/2/1 任意数据量当帧全渲染，退出重进不再变化 ⑥轮播进/退场动画不变 ⑦重进自愈/高度地板/2.5s 抑制窗零回退 ⑧classic 皮肤零影响。
- **验证**: 本机无 Swift 工具链——括号/方括号平衡度与 HEAD 逐文件一致 + 调用点参数序核对；**编译与上述 ①–⑧ 需 CI + 装机验证**。

## SLOT-ROW-RESYNC + SLOT-CLOCK-REARM — 轮播动画保真 + 报错重试秒数续走（Qoder 第二轮, 2026-09-19，Doris 复核 + 自审 §四.1）

- **File**: 仅 `ToolActivityGroupView.swift`（上一批 SLOT-ERROR-RETRY + SLOT-ROW-UNION 的语义修正，其余文件不变）。
- **补 A（renderIds 并集→状态层 task 兜底）**: 一轮的 `renderIds = displayRows ∪ carouselIds` 在"数据到达帧"即渲染新行，早于 `onChange` 的 `withAnimation(carouselSpring)` 事务 → 结构 diff 被吃掉，新行进场滑入动画丢失（红线条②）。改为状态层对齐：删掉 renderIds，`ForEach` 回退 `carouselIds`，新增 `.task(id: displayRows.map(\.id))` 兜底——task 按**取值**而非变化沿触发（覆盖"初评即新值"丢沿场景），运行时数据已落定，差额插入包在与 onChange 同款 `withAnimation(carouselSpring)` 里；正常帧 onChange 先对齐、task 复跑恒为 no-op（`guard targetIds != carouselIds`）。不用 `onChange(initial:true)`：初值回调在 body 评估期触发，与 onAppear 无动画同步有先后竞态；task 挂载后运行、顺序确定。Bug B 自愈能力保留（有数据必对齐、当帧必渲染）。零新增通知/reconfigure，不触碰 allowRemountPing/noteProgrammaticReconfigure。
- **补 B（计时器报错重试续走）**: 一轮遗留 §四.1——报错沿 `isDone false→true` 触发 settle 钉死 `frozen`，重试成功后 resume 被 `frozen != nil` 守卫挡掉 → 秒数永久冻结。修复：`.onChange(of: segment.isDone)` 在 `errorPendingRetry && !closedByContent` 时**推迟 settle**（错误待重试=假收口，不落终值）；`.onChange(of: errorPendingRetry)` 撤销沿且 `message.error != nil`（真收口=用户开新回合放弃）时补 settle。重试续走路径：`retry()` 先清 error 再转 isProcessing → resume 时 frozen 为 nil → 从原 startedAt + pausedOffset（冻结等待已折叠）续走，不重数/不跳回。ThinkingRunClock API 零改动（共享组件，消费点见自审报告第二轮章节：写仅本视图，读 ThinkingElapsedText.elapsed / ThinkingDetailOverlay.frozenValue）。
- **保持项**: 冷启动错误尾巴→冻结运行槽（一轮 onAppear 冻结链）保留不动；§四.5 汇聚页 `isSegmentRunning` 判据不消费新标志——非局部低风险改动，仅记录不改。
- **回归项**: ①live 新工具行进场滑入动画与改前同款（补 A 核心验收）②Bug B 不回退：3 行数据 live 全渲染，退出重进不变化 ③422 报错→重试续走后秒数继续走（不冻结）④彻底放弃（开新回合）后槽收口且聚合页「Thought for Ns」为有限值 ⑤closedByContent 正文收口 settle 路径不变 ⑥red line：轮播动画/正文语义/classic 冻结/slotFloor/冷却机制全部无回退。
- **验证**: 本机无 Swift 工具链——括号平衡度与 HEAD 一致；①–⑥ 需 CI + 装机。

## SLOT-ROW-FALLBACK — 缺行两全兜底：队列自愈为主 + 仅"持续缺行"才并集（Qoder 第三轮, 2026-09-19，pp：“一轮保渲染丢动画、二轮保动画赌自愈，要两全”）

- **File**: 仅 `ToolActivityGroupView.swift`（新增 `@State fallbackRowIds` + `renderIds` computed + `.task(id:)` 二段化 + ForEach 换源 renderIds）。
- **机制（为什么两全成立）**: 一轮渲染层并集在数据到达帧即并入 → 抢在 `withAnimation(carouselSpring)` 事务前渲染 → 进场动画被吃；二轮纯自愈动画保真，但"缺行根因不在队列落后"时治不到。三轮把并集降级为**持续缺失判据**：task 首检同帧差量对齐（带动画，原逻辑不变）→ `Task.sleep(120ms)` 复检 → 仅当数据 id 仍不在队列才写 `fallbackRowIds`（尾部补画，可接受不播动画）；正常帧 onChange/首检都在同一更新事务内对齐（≤1–3 帧），复检时刻 missing 恒空 → `renderIds ≡ carouselIds`，ForEach 结构与二轮逐帧恒等 → 动画路径零扰动。兜底态幂等可撤销（filter 去重：队列迟到补齐即回恒等，不依赖 task 再跑）。
- **不自激论证**: task 的 id 挂在 `displayRows.map(\.id)`（数据侧派生），写 `fallbackRowIds` 不改变该取值 → task 不重跑，无循环；数据再变时新 task 重算，`Task.isCancelled` 守卫防旧复检回写过期结论。
- **约束自查**: 兜底态只在 task 内写（非 body 评估期）；零新增通知/reconfigure；不触碰 allowRemountPing/2.5s 抑制窗/slotFloor；classic 冻结；一/二轮语义（errorPendingRetry 桥、settle 缓放/补落定）零回退。
- **回归项**: ①live 进场滑入动画与二轮/基线同款 ②人为制造自愈失效（难）时缺行 ≤0.12s 补画 ③Bug B 3 行当帧全渲染不回退 ④快速连发工具无兜底闪烁（复检幂等）⑤报错重试秒数续走（二轮项）⑥classic 零影响。
- **验证**: 括号平衡度与 HEAD 一致；①–⑥ 需 CI + 装机。

## DETAIL-COMPLETION — 汇聚页工具详情页补全：代码卡平铺 + memory_write 正文 + browser/read_image 图片卡（Qoder, 2026-09-20，pp：“代码卡片平铺、自适应高度”/“全部都要修”+“第二条那个要显示操作目标”）

- **Files**: `SelectableMarkdownView.swift`（新增 `codeBlockAutoHeight` 开关：struct/renderer/`attachmentBounds`/`makeView`/`updateView` 共 5 处透传）；`ThinkingDetailOverlay.swift`（详情页 `ToolSummaryDetailPage`：`detailMarkdown` 的 `SelectableMarkdownView` + `codeCard` 平铺、新增 `case .memoryTool`、新增 `isImageTool`/`imageToolHasContent`/`browserTargetURL`/`operationTargetText`/`imageToolCard`、`detailView` 分派插图片卡分支、根视图挂 `.fullScreenCover`）。
- **缘起（pp 三条）**：① 详情页代码卡固定 400pt 需卡内手动滚，不合理 → 平铺 + 自适应高度、整页滚；② memory_write 详情只显 "Memory saved to X (N chars)" 确认串、无正文；③ browser/read_image 详情缺截图与操作目标（根因：旧 `detailMarkdown` 只特判 file_write/file_read/shell/memory，其余落 default 只读 `block.content`、从不读输入参数也不渲染图）。
- **修复**：
  - A 代码卡平铺：三处高度点（`attachmentBounds:1685`/`makeView:1791`/`updateView:1969`）统一 `autoHeight ? .greatestFiniteMagnitude : (400-offset)`；∞ 被 `min(contentHeight,∞)` 钳成有限值、不溢出；`makeView` 的 `alwaysBounceVertical = !autoHeight` 避免满高滚动区与外层页面 ScrollView 抢手势（横向长行滚动保留）。
  - B memory_write 正文：`detailMarkdown` 加 `case .memoryTool(action)`——write 取输入 `args["content"]`（复用 `extractWriteContent`，与 file_write 同键）；get 保持 output（output 本身即召回正文）。
  - C browser/read_image 图片卡：`detailView` 在 fileEdit 分支后、`detailMarkdown` 分支前截走；卡 = 操作目标一行（browser→`action  URL` 取 `block.browserURL ?? args["url"]`；read_image→path；等宽 muted 可长按选择，不搬小窗蓝胶囊）+ 等比缩放内联图（小窗 `browserResultContent` 同款 `Image.scaledToFit().frame(maxWidth:.infinity)`，点按 → 全屏 `ImagePreviewView` 缩放/保存/分享，长按复制图）+ 结果文本（同款平铺卡）；图/目标/结果三者全空 → 回退旧 Input/Output 双卡。
- **死隔离申报**：聊天流 `SelectableMarkdownView` 默认 `autoHeight=false`、`alwaysBounceVertical=!false=true` 与改前逐位一致；全项目 7 处 `SelectableMarkdownView(` 调用均带标签传参、新属性中插不错位；**详情页不传 `messageId`** → `makeCoordinator` 缓存分支跳过 → 每次拿新 renderer + 空附件缓存，`autoHeight=true` 恒生效，绝不复用聊天流按 `messageId` 缓存的 false 附件（亦不反向污染）；不碰 `ToolBlockContentView`（小窗）、聊天 `AssistantBlockView`、SSE/agent 循环/持久化。
- **已知偏离（pp 请裁）**：pp 原选"内联可缩放 `ZoomableImageView`"被替换为"已验证等比 `Image` + 点按全屏缩放"——`ZoomableImageView` 系 GeometryReader、依赖 `geo.size.height`、全项目零调用方、放进纵向 ScrollView 高度歧义（本机无法编译/预览验证），保守起见闻功能保留（缩放移入全屏）。若 pp 要内联捏合，改回并加有界高度外壳。
- **回归项**：① 聊天流代码卡仍 400 封顶内滚（autoHeight=false）② 详情页代码卡完整撑高、整页滚、卡内不内滚 ③ memory_write 详情显正文 ④ browser 详情显 action+URL+截图+结果，捏合/保存/分享在全屏可用 ⑤ read_image 详情显路径+图+视觉文本 ⑥ 旧消息重启后图从 `imageFilePath`/mediaRef 恢复显示 ⑦ 小窗 browser/read_image 渲染不变 ⑧ 深色模式图边框/文本可读。
- **验证**：本机（Linux）无 Swift/Xcode 工具链、无法编译；上述为静态三轮 + 对抗复核对着代码（含 renderer 缓存污染、首帧闪烁、memberwise init 参数序三处挖坑排除）；**编译与回归 ①–⑧ 需 CI + 装机验证**。

## HOME-BOTTOM-CAPSULE — 聊天列表底部栏：圆形玻璃 FAB → 静态胶囊（Qoder, 2026-09-20，pp 截图 + "aa 有发起对话的胶囊 可以搬" + "文案新会话、搜索框文字不变"）

- **Files**：`Views/ContentView.swift`（重写底部栏 + 删死代码 + 收敛搜索生命周期）；`Shared/Config/ConfigRegistry+Builtins.swift`（删失效设置 `chat.fabOnLeft`）；`Localizable.xcstrings`（加 key `"New chat"`）。
- **缘起**：pp 给目标截图，要求把聊天列表底部两个可拖拽圆形玻璃 FAB（新建=品牌色气泡 / 搜索=放大镜，点搜索才展开成胶囊）改成**静态胶囊**——右上「新会话」深色胶囊 + 全宽常驻搜索胶囊。pp 点明 AA 有现成"发起对话"胶囊可搬；查证 `AppGlassButton` 早已搬进本仓库（`Views/AuthAA/`），直接复用、零新造。
- **修复**：
  - A 底部栏重写：`fabRow`/`fabRowContent` → `bottomBar`（`VStack{ HStack{Spacer; newChatPill}; searchBarCapsule }`）；两处调用点（compact / iPad sidebar）`else { fabRow }` → `else { bottomBar }`；删 `if !sessions.isEmpty` 外层 gate（胶囊始终显示）。
  - B `newChatPill` = `AppGlassButton(AppLocalized("New chat"), systemImage:"square.and.pencil", style:.prominent, maxWidth:nil){...}` + 原样搬长按「New Chat with Group」分组 `.contextMenu`。`.prominent` 走 `AppTheme.primaryControl*`（dark=白底黑字/light=黑底白字）天然满足 pp"深色反相"，且 iOS<26 自动降级 `.borderedProminent`。
  - C `searchBarCapsule`：复用展开态搜索栏内容（magnifier + `TextField("Search chats...")` + `searchClearButton`，占位文字不动）+ `SearchBarSurface` + `contentShape(.capsule)`；删 GeometryReader/barX/barWidth 避让数学 → `frame(maxWidth:.infinity).frame(height:56)`；X 改为仅有文字时显示。
  - D 状态/生命周期收敛：删 `@AppStorage fabOnLeft`、`fabDragOffset`、`showSearchBar`、`fabDidDrag`、`searchDragOffset`、`searchDidDrag`、`@Namespace fabGlassNamespace`；`isSearching` 改纯看文字（`!trim.isEmpty`）；键盘避让两处 `edges: showSearchBar ? [] : .bottom` → `searchFocused ? [] : .bottom`；`dismissSearch`/`dismissSearchIfEmptyOnNavigate`/`focusSearch` 去掉展开态；进页面不再自动弹键盘（原 `.onAppear{searchFocused=true}` 删）。
  - E 本地化：`Localizable.xcstrings` 加 key `"New chat"`（en="New chat"、zh-Hans="新会话"；其余 7 语言暂缺回退 en，pp 认可"可后续补"）。`"New Session"`（AIChatView:899 在用）值不动以免串改。
- **死代码清除**（改造直接产物）：删文件级 `private struct DraggableFAB`、`private struct FABGlassMorphID`，及仅 fabRowContent 用的 4 个私有成员 `fabCircleSurface`/`newChatBrandColor`/`newChatGlassTint`/`newChatIconColor`。全库 grep 零符号引用（他处仅剩说明性注释文字提及旧名，不影响编译）。
- **共享配置面申报**：删 `ConfigRegistry+Builtins.swift` 的 `chat.fabOnLeft` 注册块（"FAB on left" 设置项，原写 UserDefaults `fabOnLeft` 供已删的 `@AppStorage` 读；FAB 移除后成失效开关）。该键无云同步 schema、全库仅注册处引用；老用户 UserDefaults 残留 `fabOnLeft` 无人读、无害。经 pp 批准删除。
- **死隔离**：只动底部栏 + 其搜索生命周期 + 1 本地化 key + 1 失效设置；不碰列表行 `SessionRow`、多选 `selectionToolbar`、`folderMiniBarOverlay`、`AppGlassButton`/`AppTheme` 本体（只调用不改）、AIChatView 的 "New Session"、SSE/agent/持久化、搜索后端 `ChatStore.searchSessions` + debounce。
- **回归项**：① 底部见全宽搜索胶囊 + 右上「新会话」深色胶囊 ② 点胶囊新建会话 ③ 长按胶囊弹分组可选组新建（⚠️ contextMenu 挂在 AppGlassButton 外层，需真机确认能弹）④ 点搜索→键盘升+列表抬升+即时过滤 ⑤ X→清空+失焦、胶囊栏仍在 ⑥ ⌘F→聚焦搜索 ⑦ 深色模式胶囊反相白底黑字 ⑧ iOS<26 borderedProminent 实心胶囊 ⑨ iPad 侧栏同款 ⑩ 中文显示"新会话" ⑪ 多选态 selectionToolbar 正常、空列表不崩、搜索高亮/片段不回退。
- **验证**：本机（Linux）无 Swift/Xcode 工具链、无法编译；已做静态三轮 + 对抗复核（AppGlassButton/AppLocalized/SearchBarSurface 签名与可见性、ForEach Identifiable、括号平衡 delta 与基线一致、全库零悬空引用）；**编译与回归 ①–⑪ 需 Mac + 真机验证**。


## BOTTOM-BAR-ALIGN + SWIPE-BOTTOM-FENCE — 底栏对齐参照图 + 底部条带退出切页判定（Doris, 2026-09-20，pp：「底部的胶囊尺寸和大小还有位置，对齐图二」+「底部的搜索栏用液态玻璃」+「滑动这两个也会触发切页 修下bug」）

- **Files**：`Views/ContentView.swift`（`bottomBar` 边距/位移）；`Views/ModeTabs/RootModeTabsView.swift`（pageSwipe 新增底部条带栅栏 + 常量）。
- **缘起**：pp 装机（HOME-BOTTOM-CAPSULE 批次）后发两张截图——实机（新会话胶囊 + 搜索栏）与参照图（Claude 列表页底栏），要求：① 胶囊尺寸/大小/位置对齐参照；② 搜索栏用液态玻璃；③ 从胶囊/搜索栏上滑动会误触发切页，修。
- **测量（两张 1179×2556@3x 逐像素 + Vision OCR 交叉锚定）**：
  - 参照 vs 实机：搜索文字中心距屏底 51.3pt vs 81.2pt（Δ≈30）；胶囊文字中心距屏底 116.5 vs 146.3（Δ≈30）；胶囊→搜索文字相对距 65.2 vs 65.2（**已一致**）；胶囊右缘距边 23 vs 16.3pt；胶囊高 44.7 vs 47.0pt（Δ2.3 容差内）。
  - 结论：（a）整体下移 30pt 贴底；（b）水平边距 16→22pt；（c）spacing 12pt、搜索栏高 56pt、字号均**保持**（相对关系已一致 / 差在容差内）。
- **改动**：
  - A `bottomBar`：`.padding(.horizontal, 16)` → `22`；追加 `.offset(y: searchFocused ? 0 : 30)`（聚焦归零——键盘抬起后维持原「栏贴键盘上沿」行为，避免 30pt 压入键盘；offset 只动视觉，safeAreaInset 高度与列表 inset 不变）。
  - B `pageSwipe` 栅栏：`listAreaTop` 顶部栅栏之后新增底部条带判定 `start.y > screenHeight - bottomBarZoneHeight`（160pt）→ 直接退出。修「从胶囊/搜索栏起手横滑切页」——旧 bubbleZone 仅盖右下角（x>W-120 且 y>H-160），搜索栏左半（x<W-120）与胶囊左缘是「洞」。bubbleZone 保留（x 条件语义独立）。
  - C 材质：搜索栏维持 `SearchBarSurface`（iOS 26 `.glassEffect(.regular, in: .capsule)` 液态玻璃）——要求②现状即满足，无改动（含命中区 `contentShape(.capsule)` 不变）。
- **死隔离**：只动 bottomBar 布局常量 + pageSwipe 栅栏 + 1 新常量；不碰搜索逻辑/列表行/selectionToolbar/AppGlassButton 本体/Remote 侧。
- **回归项**：① 底栏视觉贴底（与参照一致），compact / iPad sidebar 两处调用点同步 ② 点胶囊新建/长按分组不回归 ③ 搜索栏玻璃与键盘避让正常（bar 不压键盘）④ 从底栏区域起手横滑**不再切页** ⑤ 从列表其他区域横滑切页仍正常（本机↔Remote 双向）⑥ 竖直滚动不受影响 ⑦ 多选 selectionToolbar 不受影响 ⑧ 深色模式。
- **验证**：静态检查（替换唯一性 + 括号平衡）通过；**编译与回归 ①–⑧ 需 CI + 真机**。

**追加（2026-09-20，pp「搜索栏为什么点不发光回弹？」）**：`SearchBarSurface` 的 iOS 26 分支 `.regular` → `.regular.interactive()`——液态玻璃的按压/聚焦反馈（系统放大 + 提亮）由 `Glass.interactive()` 提供；同 AA ChatComposer 配方（B16-INPUTBAR，pp「改成 claudio 那样放大和发亮」）与齿轮/滚动钮「真控件挂 interactive」先例。修正原条目 C 的「材质无改动」表述：材质本体（glassEffect in capsule）不变，交互层此前缺失、本次补上。

**追加 2（2026-09-20，pp「搜索的那个图标是不是用的黑色」）**：`searchBarCapsule` 放大镜 `.secondary` → `ChatColors.inputIconFg`——输入栏三图标同一「图标黑」常数（B16-INPUTBAR：浅色纯黑 / 深色 secondaryLabel），与参照图实测（放大镜 ≈ 纯黑 rgb22-43）对齐。占位文字/清除按钮颜色不动。

**追加 3（2026-09-20，pp「新会话的颜色有没有对齐图二」）**：胶囊底色实测——参照 rgb(42,42,41) vs 实机 rgb(25,25,25)（tint=纯黑渲染后偏深 17）。修：`AppGlassButton` 新增 additive `tintOverride` 参数（默认 nil=原 AppTheme 行为，两 init 对称、存量调用零影响），`newChatPill` 传 `#111111`（浅色）/ 白（深色保持原样）——按「材质偏移恒定」推算渲染 ≈42，装机后按实拍微调。文字白字两图一致（255/255），未动。

**追加 4（2026-09-20，pp「搜索会话后面那三个点不要」）**：搜索占位去省略号——`"Search chats..."` key 重命名为 `"Search chats"`（9 语言值全去尾部 `...`：搜索对话 / 搜索對話 / Chats durchsuchen / Buscar chats / Rechercher des conversations / チャットを検索 / 채팅 검색 / Поиск чатов / Search chats）。两处调用点同步：底部搜索栏 `TextField`（ContentView）与聊天页 `.searchable(prompt:)`（AIChatView）。

## SEARCH-JUMP — 列表搜索命中 → 进入会话自动定位到该消息（Doris, 2026-09-20，pp：「搜索会话了之后点击聊天卡片进去现在没有做自动到搜索关键词那位置 出个方案解决一下」）

- **Files**：`Agent/Chat/ChatStore.swift`（SearchResult + SQL + bind）；`Views/ContentView.swift`（命中消息 id 字典 + 两处 AIChatView 构造点传参）；`Views/Chat/AIChatView.swift`（init 参数 + @State + 列表传参）；`Agent/MessageList/CollectionViewMessageListV3.swift`（anchor 参数 + 消费 + 首屏定位 + `scrollToMessage`）。
- **方案（数据流）**：① 搜索 SQL 的 snippet 子查询旁边并列一个同条件 id 子查询 → `SearchResult.matchedMessageId`（跟随既有「取最新一条匹配」语义，与 snippet 同源）；② ContentView 搜索态存 `searchMatchMessageIds[sessionId]`；③ 打开会话的**两个构造点**（NavigationStack destination / iPad detailView）注入 `searchAnchorMessageId: isSearching ? map[id] : nil`（additive init 参数，非搜索进入恒 nil → 零回归）；④ AIChatView 转 UUID 后传给消息列表；⑤ 列表在**首次快照应用的 isFirstLoad 分支**改走「定位到该消息」而非 `scrollToLastItem()`，并**关掉 8s 底钉**（`clampAfterSessionLoad = false`——否则 clamp 窗口内的高度修正 re-pin 会把视图拽回底部）；⑥ 定位配方复用 `scrollToPreviousUserTurn` 的 diffable 查找（`.wholeMessage(id)` → indexPath → `scrollToItem(at: .top)`）+ 0.5s 二次重锚（首屏高度估算修正后校正）；⑦ 目标不在快照（工具组折叠/压缩丢弃）→ 降级贴底 + `[ScrollDiag][searchJump]` 日志。
- **语义决策**：跟随现有 snippet 语义（`ORDER BY sort_order DESC` = 最新一条匹配）；`scrollMode = .userBrowsing`（不因后续流式生长被拽回底部）；v1 **不做消息内高亮**（列后续）。
- **死隔离**：只加参数/状态/一条新方法 + 首屏分支的一次分流；非搜索路径（anchor == nil）行为与改前逐字节同；不碰 vm、不改既有滚动信号的任何语义。
- **回归项**：① 搜索命中消息 → 点卡片进入即停在命中消息处（不再贴底）② 非搜索进入仍贴底（原行为）③ title-only 命中（无消息命中）不跳、贴底 ④ 搜到的是最后一条消息 → 位置自然靠近底部 ⑤ 进入后向上/向下滑正常、↑/↓ 按钮状态正常 ⑥ 后续流式/重试不会被拽回底部 ⑦ 工具组折叠场景降级贴底不崩 ⑧ iPad 宽度布局同效。
- **验证**：静态检查（替换唯一性 + 括号平衡）；**编译与回归 ①–⑧ 需 CI + 真机**。

**追加（2026-09-20 深夜，pp「胶囊大小还是没有跟图二尺寸一样 我要的是一样尺寸」+「拖动新会话那个胶囊怎么也会切页」）**：
1. **NEWCHAT-WIDTH**：逐像素实测——参照胶囊外壳 **126.0×44.7pt**（内容 90.3 + 系统内边距 ~2×19）；实机 **111.7×47.0pt**（中文「新会话」内容 73，内边距同）。宽度差 14.3pt。修：`AppGlassButton` 加 additive `labelMinWidth`（默认 nil 零回归），`newChatPill` 传 **87pt** → 外壳 ≈ 87+38.7 ≈ 126pt 对齐；用 minWidth 而非固定宽（英文等长文案不压缩）。位置（顶距屏底 139.7 vs 139.3）与配色（40,40,41 vs 42,42,41）本轮实测已对齐，不动。
2. **BOTTOM-BAR-FENCE-EXACT**：pp「**拖动**新会话胶囊也会切页」——原判定是「手势 start.y（**视图局部坐标**）> `UIScreen.main.bounds.height` − 160」，依赖「局部坐标 == 窗口坐标」与 UIScreen 取值两个假设（实测胶囊顶距屏底 139.7pt < 160，若假设成立本应被拦 → 说明假设之一不牢）。修：`ContentView.bottomBar` 用 GeometryReader 上报**窗口坐标顶边**（`BottomBarFence.topY`），页切手势改 `coordinateSpace: .global` 并优先按上报值（−8pt 余量）排除；未上报时退回 160 条带。回归项追加：⑨ 从胶囊/搜索栏任意位置起手滑动或拖动都不切页 ⑩ 列表区横滑切页仍正常。

**追加 2（2026-09-20，pp「底部做渐隐」）**：`bottomBar` 加**渐变背景**（顶部透明 → 0.6 位置全实心 `Color(.systemBackground)`，`allowsHitTesting(false)`）——列表内容滚到底部栏区域时逐渐融入背景，而不是硬切/从栏后透出；参数按参照图二校准（内容在搜索栏顶 ~60pt 处淡尽）。同聊天页 composer 的既有做法（AIChatView `LinearGradient` 背景）。两处调用点（compact / iPad sidebar）因共用 `bottomBar` 同时生效。回归项追加：⑪ 内容滚到底部逐渐淡出、栏间隙拖动列表不受影响、深浅色一致。

**追加 3（2026-09-20，pp「只要弹出来输入搜索了 就弹不回去了」）**：搜索键盘**收起出口补齐**——现状聚焦后无任何出口（清除 X 仅在有文字时显示；SwiftUI 列表的 `scrollDismissesKeyboard` 默认 `.automatic` 在非 `searchable` 场景等于 `.never`，滚动不收）。加三条：① 列表 `.scrollDismissesKeyboard(.immediately)`（滚动即收，compact / iPad 两处）② 列表 `.simultaneousGesture(TapGesture())` 点任意处收起（不拦截行点击/导航）③ 搜索 TextField `.submitLabel(.search)` + `.onSubmit { searchFocused = false }`（键盘右下角「搜索」键即收）。点搜索栏自身不受影响（栏在列表之上）。回归项追加：⑫ 未输入文字时：滚列表 / 点列表 / 按键盘搜索键都能收起键盘 ⑬ 点行仍正常进入会话 ⑭ 有文字时 X 仍可用。

**BOTTOM-FADE-2（2026-09-20，pp「你渐隐做反了？」+ 实机图）**：首版把渐变挂在 `bottomBar` 的背景上，实机实测**淡化只挤在最底部约 20pt 内完成**（截图像素对比：屏底 179pt 处淡化 54%、159pt 处已全无；参照是 180→60pt 平缓过渡）——观感像被切掉而非渐隐。重做为**列表的 `overlay`**（对齐底部 + 显式 `frame(height: 200)` + `ignoresSafeArea(edges: .bottom)`），位置/范围完全显式，不再随底部栏布局盒子漂移；曲线 `[透明@0, 透明@0.10, 实心@0.70]`（屏底 ~180pt 起淡、~60pt 淡尽，过渡带 ~120pt，对齐参照）。z 序：列表内容 < 本层 < `safeAreaInset` 底部栏（栏不被蒙）。

**NEWCHAT-HEIGHT（2026-09-20，pp「为什么我这个胶囊看着那么胖呢」+「你看别人的」）**：逐像素实测——实机 **125.7×47.0pt（比 2.67）** vs 参照 **126.0×44.7pt（比 2.82）**：宽度已完全对齐（NEWCHAT-WIDTH 生效），**多出的是高度 2.3pt**（观感即"胖"）。修：`AppGlassButton` 加 additive `heightTightening`（每边 pt，默认 0 零回归；玻璃胶囊跟随 label 测量高度，负 padding 收缩），`newChatPill` 传 **1.15** → 高度 ≈ 44.7pt，宽高比 2.82 与参照一致。已知残留：中文「新会话」内容 73pt vs 参照「+ New chat」90pt（文案长度差异），内容占比低是视觉"空"的来源，如需更满可后续放大图标。

**NEWCHAT-ICON（2026-09-20，pp「把图标换成➕号吧」）**：底部「新会话」胶囊图标 `square.and.pencil` → `plus`（与参照 `+ New chat` 一致）。只动 `newChatPill` 一处；菜单项（Rename Group / Edit Title）与聊天页同名图标各处不动。

**FADE-POS-FIX（2026-09-20，pp「渐隐有问题 位置完全不对」）**：实机逐像素定位——淡化带落在**距屏底 199–399pt**（列表中部），正好比"贴底"高出一个自身高度（200pt）。根因：`bottomFade` 的 `.ignoresSafeArea(edges: .bottom)` 在 overlay 中把整层上移了一个高度。**移除该 modifier**（底部安全区若露出 ~34pt 空白区，该区无列表内容，可接受）。

**SEARCHBAR-HEIGHT（2026-09-20，pp「搜索栏也太肥了啊 你只调了开启会话胶囊？」——确实漏了）**：逐像素对照——实机栏高 **56pt** vs 参照 **46.7pt**（栏顶 74.7 / 栏底 28 / 文字中心 51.3pt 均已对齐）。改 `.frame(height: 56)` → **47**；同时 `bottomBar` 的 `.padding(.bottom, 20)` → **24** 补回 4pt，使栏底距屏底保持 ~28pt、栏内文字中心保持 ~51.5pt（参照 51.3）。

**BOTTOM-FADE-3（2026-09-20，pp「渐隐位置还是有问题啊」+ 04:43 实机图）**：FADE-POS-FIX（去 ignoresSafeArea）后症状不变——淡化带仍固定在距屏底 199–299pt（两图同滚动位置、同位置）。**反推**：v1（bar 的 background）的淡化带位置与 bar frame（[屏底-180, 屏底-34]）完全吻合 = **该挂载点位置是准的**；v2 的 List-overlay 淡化带底边恒在距屏底 ~199pt = List frame 底异常上移 199pt（根因未明，本地无法复现）。**决策：弃用 List-overlay，改回已验证可靠的 bar-background 挂载点**，并给渐变**显式高度 260pt**（v1 无显式高度只填了 bar 自身 143pt，所以只盖到栏区）+ `alignment: .bottom` 向上溢出；stops 重算（相对渐变层）：[透明@0.40, 全白@0.90] → 淡化带 = 屏底-190 起淡、屏底-60 淡尽（对齐参照）。z 序不变（列表 < 渐变 < bar 内容）。

**CLICKFIX + FADE-MATERIAL（2026-09-20，pp「列表会话点不进去了 点了没反应」+「渐隐用顶部的那种模糊效果吧」）**：
1. **点击回归修复**：SEARCH-DISMISS 批次的列表 `.simultaneousGesture(TapGesture())`（点列表收键盘）实测**干扰行点击** → 移除（两处）。收起出口保留：滚动（`scrollDismissesKeyboard`）/ 键盘「搜索」键 / 有文字时 X。
2. **渐隐材质化**：`bottomFade` 从纯色 `LinearGradient` 改为 **`.ultraThinMaterial` + mask 渐隐**——同 `folderMiniBar` 的材质语言（pp：「用顶部的那种模糊效果」）；位置/曲线参数不变（0.40 前不模糊、0.90 后全模糊，260pt、底对齐 bar frame 底）。

**FADE-GAP-FIX（2026-09-20，pp「注意位置。上一版的这个底部有缺口」）**：bar frame 底 = 屏底-34（安全区底），渐隐只盖到那里 → 屏幕最底一截（安全区内）内容露出 = 缺口。修：`height 294`（260+34）+ `offset(y: 34)` → 渐变 = [屏底-294, 屏底] 覆盖到屏幕物理底；stops 重算 `[0.35, 0.80]` 保持淡出带原位（屏底-190 起淡、屏底-60 淡尽）。

**补充（2026-09-20，pp「要高亮 你做吧」）**：命中消息**高亮脉冲**——`SearchJumpHighlightModifier`（`ChatColors.accent` 12% 圆角背景，跟随既有「复制后高亮」视觉语言）挂在 `BridgedWholeMessageV3` 上；coordinator 在定位成功后设 `searchJumpHighlightId` 并重建该 cell（亮起），2s 后释放并重建（灭）；cell 内 0.6s 后开始 0.9s 淡出（显式 `withAnimation` —— cell 宿主吞隐式动画/B16 判例）。找不到目标时不设高亮。回归项追加：⑨ 跳转后命中消息亮起并在约 1.5s 内淡出 ⑩ 非搜索路径消息无高亮。

## REMOTE-LIST-LAYOUT — 远端会话列表排版修复：行内边距/平色背景 + 删重复项目头 + 底栏复用本机配方 + 假数据诚实标识（Qoder, 2026-09-20，pp 装机截图「这页面排版严重有问题」+ 确认六项方案「可以」）

- **Files**: `Views/ContentView.swift`（三处 additive 提取：`SearchBarSurface` private→internal；新增 file-scope `BottomBarRecipe`（newChatTint/LabelMinWidth/HeightTightening，原 private static 三常量上移，本机调用点改别名）；`bottomFade` 计算属性提取为 internal `BottomBarFadeView`，本机挂载点改 `{ BottomBarFadeView() }`）；`Views/RemoteSessions/RemoteSessionListView.swift`（六项修复主体）；`Views/RemoteSessions/RemoteSessionComponents.swift`（删 `RemoteRowCardBackground`/`RemoteCardSurface`，唯一消费点切换后成死代码，按纪律删除）。
- **缘起**：pp 实机截图——远端列表行距稀疏、连接器行默认内边距与卡片错位、"项目"标题在 Section header 与 projectHeader 行重复出现、底栏是手搓变体（regularMaterial 硬边、假搜索栏 `Text("搜索对话")` 不可输入、胶囊无逐像素配方）、圆角描边卡片背景与本机平色列表不符。pp 确认方案：#1/#2 行内边距归零+背景对齐本机；#3/#4 删重复"项目"头与 … 死按钮（showsListOptions 死开关一并清）；#5/#6 底栏直接复用本机同一套组件参数；假数据顶部加诚实标识。
- **修复**：
  - A 行对齐本机：sessionRow 左右 padding 16（原只有 leading 12）、`listRowBackground` 平色 `Color(.systemBackground)`（inset 行保持 clear）；connectorRow/projectHeader 补 `.listRowInsets(EdgeInsets())` + 同款平色背景（连接器行 padding 10→16、minHeight 42→56；项目头 10→16、补 minHeight 48）；删 `.scrollContentBackground(.hidden)`（本机不 hide）；sectionLabel 加 `.textCase(nil)`。
  - B 项目头去重：项目 Section 不再套 header（projectHeader 行自带「项目」标题，改 subheadline.semibold + secondary 与 sectionLabel 同款）；删 projectHeader 内 … 按钮（其开关 `showsListOptions` 无任何消费弹窗 = 死状态，连声明一起删；右上角 listOptionsButton 菜单保留——归档/断开唯一入口）。
  - C 底栏复用：`bottomBar` 几何逐位对齐本机（padding 22/8/24、spacing 12、`background(alignment:.bottom){BottomBarFadeView()}` 毛玻璃渐隐、`offset(y: searchFocused ? 0 : 30)`，删 `.regularMaterial` 硬底）；`newChatPill` 走 `AppLocalized("New chat")` + `BottomBarRecipe` 三参数（tint #111111/labelMinWidth 87/heightTightening 1.15）；`searchBar` → `searchBarCapsule`：真 `TextField("Search chats")`（复用本机 xcstrings key）+ magnifier `ChatColors.inputIconFg` + 有文字才显 X + `SearchBarSurface()` 液态玻璃 + height 47 + submitLabel/onSubmit。
  - D 真搜索：`@State searchText` + `@FocusState searchFocused`；`filteredSessions` 标题本地过滤（大小写不敏感），三个派生 getter 改走过滤后集合；`scrollDismissesKeyboard(.immediately)` 保留（滚动收键盘）。
  - E 诚实标识：连接器 Section 内 connectorRow 下新增 `previewBanner`「预览数据 · 真实会话接通中」（sparkles + secondary 小字）——当前列表全为 previewItems 假数据，不许静默装真；数据面接通后删除。
- **死隔离**：ContentView 侧全部为行为不变的可见性提取（private→internal + 值上移别名，本机渲染路径逐位同：同 tint/同 87/同 1.15/同 294+34 渐隐几何/同挂载点）；远端侧不新增文件（零 pbxproj 改动）；远端不读 ChatStore、不碰本机列表逻辑，只消费本机主动暴露的共享配方（方向合法：本机暴露→远端消费）。注释新增不含 RemoteKit 符号名（import-scan 门禁约束）。
- **回归项**：① 本机列表底栏与改前逐像素一致（胶囊/搜索栏/渐隐/键盘避让）② 远端行贴边平色、与本机同款密度 ③ 远端"项目"只出现一次、… 按钮消失、右上角菜单归档/断开可用 ④ 远端搜索可输入、即时过滤标题、X/回车/滚动三出口收起 ⑤ 远端胶囊 126×44.7 外观（浅色 #111 tint）⑥ 远端渐隐位置同本机（屏底-190 起淡）⑦ 预览横幅显示、深色模式可读 ⑧ 空态（真数据为空）仍显配对引导 + 底栏。
- **验证**：本机（Linux）无 Swift/Xcode 工具链、无法编译；静态三轮（括号/花脚平衡=0、删侧 diff 审计、全库 grep 零悬空引用：showsListOptions/RemoteRowCardBackground/RemoteCardSurface/bottomFade 仅剩说明性注释）+ 对抗复核（AppGlassButton 新参数签名逐位核对、AppLocalized/ChatColors/SearchBarSurface 可见性与签名、Section 无 header 合法性）；**编译与回归 ①–⑧ 需 CI + 装机验证**。

## REMOTE-LIST-TWOMODULE — 远端列表板块重构：照官方两大模块（设备/项目）+ 列表 UI 全复用本机（Qoder, 2026-09-20，pp 官方侧栏截图「排版是不是按照两大板块做的」→ 定稿「列表排版就复用本地的列表ui，不要再另外造一套；按官方分两个模块，点击按钮进入的 ui 才完全用 aa」）

- **Files**: 仅 `Views/RemoteSessions/RemoteSessionListView.swift`（板块重构 + 文件头定稿注释）。
- **缘起**：pp 对照官方 AA 侧栏截图确认板块语义——官方 = 设备板块（设备行 + 「+ 配对设备」整行）+ 项目板块（「项目 ▾ … +」头 + 空态「还没有项目。」）。原实现为四段（连接器/置顶/项目/全部会话）且配对入口是行尾小按钮、项目头无折叠无菜单。
- **修复**：
  - A 设备板块：Section 标题「连接器」→「设备」；connectorRow → deviceRow（去行尾配对小按钮，等宽字体 subheadline→body）；新增 `pairDeviceRow`「+ 配对设备」整行（本机行同款 minHeight 56 / padding 16 / 平色背景）→ 弹 PairDeviceSheet（AA 视觉不动，符合「进按钮的 UI 才用 AA」）。
  - B 项目板块：projectHeader 升级官方三件套——标题+`chevron` 折叠（`projectsCollapsed`，`withAnimation(.snappy)`）、`…` Menu（复用 `listOptionsMenuContent`：归档会话/断开连接）、`+` 新建；空态行「还没有项目。」，搜索无结果时分文案「没有匹配的会话。」（诚实区分）。
  - C 删多余板块与右上角菜单：置顶/全部会话 Section 删除（`pinnedItems`/`recentItems` 派生删除；`projectItems` = 过滤后全部、置顶排前）；toolbar `listOptionsButton` 删除（含死 Picker「列表显示」constant 开关），选项入口移至项目头 …（官方位置）。
  - D previewBanner 挪入项目板块（projectHeader 之下、会话行之上）——它标的是会话数据，不占设备板块。
- **死隔离**：只动远端列表文件；本机 ContentView / RemoteKit / AA 弹窗（PairDeviceSheet/ProjectEditor/详情/归档）零改动；不新增文件（零 pbxproj）。
- **回归项**：① 列表只剩设备/项目两大板块，行视觉与本机一致 ② 「+ 配对设备」整行弹 AA 配对页 ③ 项目头 ▾ 折叠/展开会话区 ④ 项目头 … 弹归档/断开菜单、+ 弹项目编辑 ⑤ 搜索过滤与两态空文案 ⑥ 置顶左滑仍生效（排序置顶项在前）⑦ 长按菜单/左滑动作不回归 ⑧ 深色模式。
- **验证**：本机无 Swift 工具链；静态三轮（括号平衡 0、grep 零悬空：connectorRow/listOptionsButton/pinnedItems/recentItems 全库无引用）；**编译与回归 ①–⑧ 需 CI + 装机**。

## NEW-SESSION-DRAWER — 远端新会话抽屉：照官方 设备→项目→运行时→任务 流程 + RemoteKit Glue 扩 inventory 三面（Qoder 双子代理并行, 2026-09-20，pp：「点击页面进去的逻辑要跟官方一样」→「一起做 可以让子代理一起 做完必须审查」）

- **Files**: `Packages/RemoteKit/Sources/Glue/RemoteSessionBackend.swift`（+3 thin pass-through：listConnectors/listProjects→`requireAPI().projects.list()`/runtimeTypes(connectorId:)）；`Glue/PublicRemoteService.swift`（+3 public 镜像 `RemoteConnector`/`RemoteProject`/`RemoteRuntimeType` + 3 public 方法，全走 `attempt{}`，字段 verbatim、presence rawValue 原样；文件头 Staging 注释更新）；`src/ios/Views/RemoteSessions/RemoteSheets.swift`（+`RemoteNewSessionSheet` ~400 行，既有三 sheet 零改动）；`RemoteSessionListView.swift`（startNewSession 改开新抽屉 + sheet 接线；项目头 + 仍开 RemoteProjectEditorSheet）。
- **缘起**：「新会话」按钮此前错误地弹创建项目 sheet（骨架期占位）。官方语义 = 新会话抽屉（选目标设备/项目/运行时 + 任务输入 + 真提交）。数据面缺口：Glue 只有 startSession 活路，无 inventory 列表面——引擎内部 V2ConnectorAPI/V2ProjectAPI 全部已编译，只欠 public 映射（薄封装成例在 PublicRemoteService 已有）。
- **修复**：
  - A Glue 扩面（契约先冻结、双子代理并行实现、UI 逐字引用）：connectors/projects/runtimeTypes 三面 public 化，String-id + verbatim 字段镜像，无 stub 无假返回（Glue 铁律）。AAV2 冻结区零改动 → 不动 AA-ATTRIBUTION。
  - B 抽屉（AA 视觉，结构照 PairDeviceSheet：NavigationStack+Form+SheetCloseToolbar+appSheetPresentation(.compact)+提交锁全页）：官方键文案「把任务发送到合适的设备。/开始一个专注会话。」；设备行 = 在线绿点/离线灰点（点样式同列表 deviceRow），离线可选可填禁提交 +「设备离线，等待重新连接。」；项目按 connectorId 本地过滤、空列表引导走项目头 +；运行时只列 available、默认 recommended、离线设备不发请求（refreshRuntimes 门）；工作目录手输 = 选中项目 workspacePath 自动填、可改（官方目录浏览器 listWorkspaceFiles 未接通 → 诚实降级，注释标明）；任务输入多行；提交 gate = state.ready ∧ 设备在线 ∧ 项目 ∧ 运行时 ∧ 非空白 ∧ !isSubmitting，真调 `startSession`（clientMessageId=UUID），成功 dismiss（列表刷新等数据面批，不注入假条目）、失败页面内红字。
  - C 审查轮修补（对抗审 0 BLOCKER + 3 RISK 顺手修）：RISK-1 切设备时悬空 selectedProjectId 一律清（含项目已删情形）；RISK-2 loadData 设备/项目 withTaskGroup 并行拉（串行会被长超时拖住）；RISK-3 离线设备不发 runtimeTypes（红字噪音）。竞态：runtimeLoadToken 代际令牌丢弃过期响应。
- **死隔离**：RemoteKit 改动全部在 Glue（自有层），AAV2 冻结区未触碰；UI 只消费 public facade；不新建文件（零 pbxproj）；既有三 sheet 一字未动（diff 删侧仅文件头注释）。
- **回归项**：① 列表点「新会话」开抽屉而非创建项目 ② 设备/项目/运行时三级真实加载与联动（切设备清项目/目录归属）③ 离线设备可选可填、提交灰 ④ 空项目引导文案 ⑤ 真提交成功 → 服务端出现新会话（startSession 活路，装机验）⑥ 失败错误上屏不吞 ⑦ 提交中全页锁 + 关窗按钮禁用 ⑧ 项目头 + 仍开创建项目（不受影响）⑨ 配对/归档/详情三 sheet 零回归 ⑩ CI import-scan/pbxproj-audit/freeze-check 全绿。
- **验证**：本机无 Swift 工具链；双子代理交付后主代理逐行审 + **对抗审查子代理全量复核**（契约 8 项逐字对、编译风险对定义文件逐个核：pbxproj -default-isolation MainActor 覆盖、SheetCloseToolbar/AppGlassButton/appSheetPresentation 签名、deployment target 26.2 下 API 可用性、Hashable 合成、同模块编译无 import 问题；结论 0 BLOCKER）+ 3 RISK 当场修 + 括号平衡 4 文件全 0；**编译与回归 ①–⑩ 需 CI + 装机**。

## REMOTE-REDESIGN-1 — 远端页大厂风重排：设备/项目板块重设计 + 会话行换本机 SessionRow 完整结构（2026-09-20，pp 三点拍板）

- **pp 指令**：①设备板块按大厂 UI 重新设计排版 ②聊天卡片用本机 UI、只替换头像（头像=无底裸 lucide）③「项目 >」分组头 + …/+ 按钮也要设计 ④「预览数据 · 真实会话接通中」删除。冻结：顶栏 / 新会话胶囊 / 搜索栏零改动。
- **Files**: `src/ios/Views/RemoteSessions/RemoteSessionListView.swift`、`RemoteSessionComponents.swift`、`PATCHES.md`。
- **修复**：
  - A 设备板块：板块头内联（「设备」16 semibold 主色，与项目头同语言，删 sectionLabel）；deviceRow 重排 = 44 圆底 server.rack 图标（在线绿/离线灰 tinted 底）+ host 名 16 semibold / 完整地址 12 mono 两行（新增 hostLabel 取 URL host）+ 右侧「已连接/未连接」淡底胶囊徽章；配对入口 = 淡色 28 圆底 + 号 + 「配对新设备」+ chevron；「需要你处理 ×N」组件化 pendingNoticesRow（bell 淡色圆底 + 橙色数字胶囊）。
  - B 项目板块头：标题 16 semibold 主色 + 会话计数 + chevron 折叠（rotationEffect 90° 旋转动画，语义同原 ▾）+ 右侧 … / + 淡色 28 圆钮（菜单项与新建行为不变）。
  - C 会话行：单行简版 → 本机 ContentView.SessionRow 完整结构（44 头像槽 + 标题 scaledApp(16) semibold + 摘要行 scaledApp(14) + 时间 scaledApp(13) tertiary + 置顶 pin 角标；spacing 8 / V12 padding 与本机一致）；头像 = 无底裸 RemoteSessionIcon 24pt 居中（pp 定稿）；状态映射：运行中→RemoteSpinningRing（ContentView.SpinningRing 逐字复制，不改本机文件可见性）、未读→头像右上 8pt 红点、等待批准→头像右下 mint bell 角标（offset ±2 同本机）；RemoteSessionItem 新增 previewText（预览数据补假摘要）。
  - D 删除 previewBanner（pp：去掉）；搜索过滤扩到摘要行（卡片可见内容可搜）；RemoteStatusIndicator 视图删除，四态语义保留为 RemoteSessionIndicator 枚举；空态按钮文案随「配对新设备」。
- **死隔离**：只动 RemoteSessions 两文件 + PATCHES；ContentView / RemoteKit / AA 弹窗（PairDevice/ProjectEditor/详情/归档/新会话抽屉）零改动（转圈用复制件不改共享可见性）；不新增文件（零 pbxproj）；冻结区（顶栏/新会话胶囊/搜索栏）零改动。
- **回归项**：① 设备行在线/离线两态视觉与徽章文案 ② 配对入口弹 PairDeviceSheet（AA 视觉不变）③ 待处理计数行出现条件与计数正确 ④ 项目头折叠/…菜单/+新建行为不变 ⑤ 会话行三状态渲染位正确（转圈/红点/mint 角标）⑥ 搜索命中标题与摘要 ⑦ 长按菜单/左滑三动作不回归 ⑧ 深色模式全套 ⑨ 字号档位跟随 App Base ⑩ CI 门禁（import-scan/pbxproj-audit/freeze）全绿。
- **补（同日 10:4x 装机反馈）**：删会话行 36pt 左缩进（inset 参数整体移除，签名/调用/行背景三处闭合）——pp：「会话卡片左边怎么空这么大一截」；与本机卡同款对称 horizontal 16pt。
- **验证**：本机无 Swift 工具链；静态（括号平衡 + 删除符号全库无引用 + 新增符号引用闭合）；**编译与回归 ①–⑩ 需 CI + 装机**。

## REMOTE-REDESIGN-3 — 顶栏右上角选项按钮回归（2026-09-20，pp：「顶栏右边是不是少了个按钮」）

- **缘起**：TWOMODULE 批把远端列表右上角 … 整个删掉（当时内容 = 死的「列表显示」Picker + 归档会话，归档挪进项目头 …），结果顶栏左 ☰ 右空不对称；本机同位置有 … 工具菜单（Shell Terminal/Rootfs/Browser 等）。
- **修复**：RemoteSessionListView 顶栏补右上角 … 玻璃圆（44pt，GlassEffectContainer + .regular.interactive() Circle——与 RootModeTabsView 固定栏 ☰ 同一 AA composer 配方，对齐 gearDiameter）；菜单 = 归档会话 + 断开连接（listOptionsMenuContent 原内容）；项目头 … 菜单移除（避免双入口），项目头只留 ▾ 折叠 + ＋ 新建。
- **死隔离**：只动 RemoteSessionListView.swift；RemoteRootView（principal ModeTabPicker）/本机 ContentView toolbar 零改动。
- **回归项**：① Remote 列表顶栏右上角出现玻璃 … 且菜单两项可用 ② 项目头折叠与＋新建不回归 ③ 本机 tab 顶栏零变化 ④ 玻璃按压回弹（interactive）⑤ 深色模式。
- **验证**：静态（括号平衡 + 断言式替换 + Menu 单实例核对）；**编译与回归 ①–⑤ 需 CI + 装机**。

## REMOTE-REDESIGN-4 — 方案 B「Claude 设计语言」全量落地（2026-09-20，pp 拍板「照你修改过后的方案二做」）

- **依据**：设计稿 `shared/moonveil/remote-redesign/v2-claude.html`（pp 逐项打磨定稿：液态玻璃 CTA / 13pt tertiary 项目头 / 无计数 / 深色终端卡 / 暖卡堆）。
- **Files**: `src/ios/Views/RemoteSessions/RemoteSessionListView.swift`、`RemoteSessionComponents.swift`（+RemotePalette 调色板 +RemoteSpikeMark）、`PATCHES.md`。
- **改动**：
  - A 画布：整页暖奶油 `#FAF9F5`（深色暖黑 `#181715`）——body 级 background + List `.scrollContentBackground(.hidden)`；调色板全 dynamic（深浅双值）。
  - B 设备 = 深色终端窗卡：mac 三色点（#FF5F57/#FEBC2E/#28C840）+ mono host + teal 点 + CONNECTED/OFFLINE 标 + 副行「地址 — N sessions」（真实计数）；16pt 连续圆角。
  - C 操作 = 液态玻璃胶囊「配对新设备」（GlassEffectContainer + .regular.interactive() Capsule；coral 加号 + ink 文字）；「需要你处理」行改琥珀胶囊。
  - D 项目头：`✳`（RemoteSpikeMark 四芒星）+「项目」13pt semibold tertiary（对齐本机时间字级）；**无计数、无 chevron**（整行点击折叠保留）；＋ 新建 = 28pt 暖卡圆钮。
  - E 会话 = 暖卡堆：`#EFE9DE` 12pt 连续圆角卡 + 白圆头像（裸 lucide）；状态语义化——等待批准=琥珀胶囊「待批准」/ 运行中=teal 转圈+mono「running」/ 未读=卡角珊瑚点（offset 4,-4）/ 置顶=pin；字级 scaledApp(15.5/13/12)。删 RemoteBadgeCircle（不再引用）。
  - F 冻结区（顶栏/新会话胶囊/搜索栏）零改动；topBarOptionsButton（R3）保留。
- **死隔离**：只动 RemoteSessions 两文件 + PATCHES；ContentView / RemoteKit / AA 弹窗零改动；不新增文件（零 pbxproj）；bottomBar 渐隐/搜索栏复用现有共享件（材质自适应，无需改共享文件）。
- **回归项**：① 终端卡在/离线两态与 CONNECTED/OFFLINE 标 ② 玻璃按钮弹 PairDeviceSheet 且按压回弹 ③ 项目头整行折叠 + ＋新建 ④ 卡堆三状态渲染位（琥珀胶囊/teal 转圈+mono/珊瑚卡角点）⑤ 长按菜单与左滑三动作 ⑥ 搜索（标题+摘要）⑦ 深色模式（暖黑画布）⑧ 字号档位跟随 ⑨ 顶栏 … 菜单仍可用 ⑩ CI 门禁全绿。
- **GLASS-GUARD-FIX（同批）**：`GlassEffectContainer`/`glassEffect` 补 `#available(iOS 26.0, *)` 守卫 + 低版本回退（淡灰圆/胶囊）——**R3 的 iOS Build 挂因**（本仓 deployment < 26，裸用 glass API = 编译错；仓库既有约定见 gear/SearchBarSurface 守卫）。
- **验证**：静态（括号平衡 + 断言式整段替换 + 悬空符号核对：RemoteBadgeCircle 全库无引用）；**编译与回归 ①–⑩ 需 CI + 装机**。

## TOPBAR-BTN-NATIVE — 顶栏右上角改原生工具栏样式（2026-09-20，pp：「右上角的按钮怎么回事？没用苹果原生？」）

- **缘起**：R3 的 … 按钮 = 手搓玻璃圆底（GlassEffectContainer + glassEffect，对齐固定栏 ☰ 配方）；pp 装机后指出应为苹果原生样式。本机 tab 同位置的既有惯例 = **裸图标**（ContentView toolbar：TerminalCircle 24×24、alarm 15pt，均无自定义圆底，系统提供热区/按压）。
- **修复**：topBarOptionsButton 改裸 `ellipsis` 字形（17pt medium，Color.primary），删除自定义圆底、GlassEffectContainer 分支与低版本回退（不再需要守卫）；菜单内容不变（归档会话/断开连接）。
- **死隔离**：只动 RemoteSessionListView.swift 一个属性；配对玻璃 CTA（pp 指定保留）与本机 tab 零改动。
- **回归项**：① 右上角为原生裸字形，系统按压反馈正常 ② 菜单两项可用 ③ 与 ☰/胶囊布局不冲突 ④ 深色模式。
- **验证**：静态（断言式替换 + glass 残留计数 1 = 仅配对按钮）；**编译与回归需 CI + 装机**。
