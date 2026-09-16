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
- Semantics: 零删减。深色态故意保留 `systemOrange` + 抬亮的 `#3A3A3C` pill：`#EA6F30` 在该底上只有约 4.4:1，而 `[T-inline-code-dark-bg-ios]` 那条案底说明深色为什么不能没有底。点击复制、hair-space 内边距、圆角绘制路径（浅色画透明，仍一条代码路径）全部不变。
- EXIT: pp 若要连 Grok 深色那套（白字 `#E7E9EA` + `#16181C` 底 + `#2F3336` 0.5pt 描边）一起照抄，改的是同两个属性，届时本条改写不留双份。
