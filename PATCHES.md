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
