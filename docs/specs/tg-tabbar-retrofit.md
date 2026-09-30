# TG 式自绘 tab 栏 · 行为合同（2026-09-30）

> pp 拍板「用tg的自绘」（复刻 Telegram，含覆盖式导航包含关系）。
> 本文件是该批次的**行为合同**：实现与验收均以此为准。
> 规格数值出处：TG-iOS 源码实读（`~/tg-ref/TabBarComponent.swift` 1351 行 +
> `TabBarContollerNode.swift` + `TabBarController.swift` + `TelegramRootController.swift`）。

## 1. 行为判据（装机验收）

1. 一级页（本机/远端/构件）底部**常驻自绘栏**——是页面的一部分，不隐藏不出现。
   （宽窗 iPad 例外：聊天在 detail 列、无"push 覆盖"模型，按系统栏时代现行行为
   收栏——选中会话时收、回列表即回；见 §2 注。）
2. 进聊天页 / 设备详情页 = **标准 iOS push**（右滑入，整页覆盖，含栏）。
3. 划回（交互式 pop）中途：一级页（含栏）整体随手势平移揭示，栏相对页面纹丝不动。
4. 新会话圆钮 → 草稿页 = 标准 push（无硬切/无底部空档）。
5. tab 切换瞬切（无 crossfade）；各 tab 保留各自页面历史；远端线保持"切走弹根"。
   （时态注：2026-09-30 起按 pp 装机要求改为 TG 缩放淡入转场——「瞬切」表述作废，
   现行行为见 §6「切页转场 v2」。）
6. 深色/浅色双模式正常；登录盖 / 设置 sheet / 资料页 zoom 不受影响。

## 2. 架构（治根点）

```
ZStack 三树保活（瞬切：当前树 opacity 1 + 可命中，其余保活不可见）
  ⤷ 时态注（2026-09-30）：切 tab 已改为 TG 缩放淡入转场（§1.5 注 / §6「切页转场 v2」），
    「瞬切」仅存于此行历史叙述
 ├─ 树1 ContentView.stackLayout: NavigationStack { 列表+safeAreaInset(ModeTabBar)
 │      → push AIChatView（整页盖，含栏） }
 ├─ 树2 RemoteRootView:          NavigationStack { 列表+safeAreaInset(ModeTabBar)
 │      → push SessionChatView / RemoteDeviceDetailView（整页盖） }
 └─ 树3 WorksListView:            NavigationStack { 列表+safeAreaInset(ModeTabBar) }
壳层（登录盖/settings/soulProfile zoom/task）挂 ZStack 外，未动。
```

注：宽窗（iPad，`splitLayout`）栏挂在整个 NavigationSplitView 底边，`selectedSessionId == nil`
时显示（聊天打开收栏）。宽窗无 push 盖栏模型，此为对系统栏时代行为的近似复刻——
等价性以装机为准（对抗复审 R1 备案）。

**栏在栈内 root 页**（不是栈外/不是壳层浮层）——push 从栈内部盖上来，栏自然被留在身后；
划回时 root 页（含栏）整体平移。无任何藏/显机制。

⚠️ 与 #420 证伪的「外层栈包 TabView」**方向相反**：那是跨层包裹（TabView 内容不向
外层栈注册 toolbar/destination）；本条是**栈内包含**，零跨层。

## 3. 自绘栏规格（TG 实测数值 → 实现位置 ModeTabBar.swift）

| 项 | 数值 | TG 出处 |
|---|---|---|
| 胶囊高 | 64 = item 56 + innerInset 4×2 | TabBarComponent:664/727 |
| 两侧边距 | 12（TG 在"无底部安全区"时切 20，本仓固定 12——iPhone 恒有 home 指示条，取常见值的取舍记录）；底缘 = 安全区底 | ContollerNode:213-216/291 |
| item | 等宽平分（除圆钮位） | :666-708 |
| 圆钮 | 64×64 独立圆，间距 8 | :899-901 |
| 选中透镜 | 槽宽 + 8、高 56；按下弹簧滑到指尖槽位、按住拖动**连续跟手**（x = 起点+指尖位移，钳制栏内）、松手提交落位 | :868-887/:540-599 |
| 透镜本体 | 系统 Liquid Glass 实玻璃层（"透明的流体"观感；拖动中 1.05 微抬升） | LiquidLens 私有件 → 规格级近似 |
| 按压 | 按住放大 1.15（lifted），横拖扫过换项 | :835/:542-551 |
| 材质 | iOS 26 glassEffect（<26 regularMaterial 回退） | TG 私有玻璃件的规格级复刻 |

不复刻（记录在案）：TG search 展开态（本仓圆钮是"新建"动作位）、Lottie 选中微动效
（无对应资产）、双击回顶（v1 不做，pp 拍板）。

## 4. 退役清单（同批清理）

- 系统 `TabView` 壳（RootModeTabsView）→ ZStack 三树保活。
- 三处 `.toolbar(.hidden, for: .tabBar)`：AIChatView / RemoteSessionListView（聊天 + 设备详情）。
- `RootTabRouter.remoteChatPushed`（藏栏标志）。
- `UITabBar.appearance()` 配置、tabSelection binding / tabLabel（迁入 ModeTabBar）。
- 遗留待清（下批）：`localAtRoot` / `localSelecting` / `remoteAtRoot` 已实证为**无视图读取**
  （仅日志 guard 读取，死 flag），因涉及 ContentView 热路径注释群，另行微批处理。

## 5. 验收前提：编译与门禁

- CI（iOS Build，feature 分支手动 dispatch）为唯一编译权威；本批首跑预计 1-2 轮。
- 门禁：swift-parse 全量 0 fail；audit-swift-registration orphans=0；audit-project-inputs missing=0；
  aav2-freeze OK；import-scan OK；authaa-freeze 的 AppGlassButton 哈希红为**预存项**
  （非本批引入，独立处理）。
- 对抗性复审（2026-09-30，独立审查员）：无阻断级缺陷；3 项已随批修复——
  ①键盘豁免（栏不随键盘上浮，生效性装机核验）；②跨树兜底（按住期间本树被外部
  route 切走则丢弃提交，`ModeTabBar.tabMode` 注入）；③注释失真两处（RootModeTabsView /
  RootTabRouter 的 TabRole / toolbar(.hidden) 时态叙述改墓碑）。
- 装机核验待测项：safeAreaInset 的栏底距（胶囊与 Home 指示条之间）、键盘豁免挂法、
  iPad 列表收栏动画、双层玻璃（栏+透镜）观感。

## 6. 装机回归修正（2026-09-30 pp 实机）

- **键盘豁免·重新挂点**：原实现把 `.ignoresSafeArea(.keyboard, edges: .bottom)` 挂在
  `ModeTabBar.body`（栏内部）——pp 实测**无效**：键盘开启、从聊天页划回时，栏随
  输入框一起上浮（TG 行为 = 栏钉死屏幕底、需要时被键盘覆盖）。根因：safeAreaInset
  插槽的落位由**被修饰整链**的安全区决定，子树内部的 ignore 改不了插槽位置。
  修复 = 豁免上移到三处挂点 safeAreaInset 的**外侧**（ContentView.stackLayout /
  RemoteRootView / WorksListView），栏内部原行保留作双保险（有防回归注释）。
  有意副效果：root 页列表内容随之下穿键盘（搜索聚焦时内容滚到键盘下，iOS 惯例）。
- iPad（NavigationSplitView 分支）**不动**：豁免若包在整链会连带 detail 列聊天
  输入框失去键盘避让（详情列与栏同树），待单独评估。
- **4 格占位·尺寸对齐 TG**：TG 栏为 4 tab 布局，本方 3 格平分 → 每格（含透镜宽
  = 槽宽+8）整体偏大（pp 2026-09-30 装机要求「加一个图标占位保持和tg一致大小」）。
  修复 = 槽位数 4（3 实 tab + 第 4 格 = TG「设置」位），两处渲染路径
  （透镜岛 TGLensHost + 回退胶囊 legacyItemsCapsule）分母统一 `slotCount = 4`
  （= (宽−8)/4）；交互（按下/提交/钳制）仍只在 0–2 实项内。
- **第 4 格 = 设置齿轮（2026-09-30 同日，pp「把那个空白占位的 tab 加一个图标」）**：
  第 4 格从空占位补为设置入口。语义 = TG 第 4 tab（设置）；本仓设置是全局 sheet
  （B16 单通道 `router.showSettings`，≡ 齿轮同款），故为**动作位**（同 compose
  圆钮）：点按开设置、透镜永不驻留/提交该格（拖过钳回 works）。资产
  `aa-Tabler-Settings`、文案 "Settings"（zh-Hans=设置）与 ≡ 齿轮同源。两条手势
  （岛 TGLensHost 的 raw 守卫 + legacy selectionGesture 的 raw 守卫）语义一字对齐：
  起点在第 4 格 → 按压态（放大 1.15）+ 松手仍在第 4 格才开设置；移回 tab 区 =
  撤销且不重新武装；按住拖过不触发。
- **尺寸对账·四笔联动修正（2026-09-30 同日，源码 + 实机反演双证）**：pp 报「栏比
  TG 大 / 选中灰体触边」→ 对 TG 源码逐项核账（行号见 §7 表）：①`barHeight` 68→64
  （TabBarComponent:664 = 56+4×2，实机圆钮 192px=64.0pt 双证）；②左右边距
  `sideInset` 12→20（TabBarContollerNode:213-215「底距≤28 档」，实机反演四列中心距
  68.0 落此档）——格宽随之 (屏宽−40−圆钮64−间距8−innerInset×2)/4 = 68.25 ≈ TG 实测
  68；③栏底距 `offset` 12→14（实机圆钮下缘 ≈19.7pt ⇒ 34−14=20）；④legacy 选中
  透镜视觉改为「item 槽位本身」——TG 私有透镜渲染内收 4（26 路径 LiquidLensView
  :464/:376；legacy blob 分支 :471 同义）：视觉 = item 矩形（宽=槽宽、距胶囊边
  4pt）；旧式 +8 宽、x 不加 4 → 首格左缘顶边。
- **松手落位/动画·对 TG 单跳语义（2026-09-30 同日，pp 报「滑动 tab 落点和动画
  有问题」）**：根因两半——①旧 `.ended` 先朝**旧** `selectionIndex` 推一段弹簧，
  再靠 SwiftUI 回推新槽：两段弹簧竞速，且第二推在 `LiquidLensView.updateLens`
  else 分支的 `removeAllAnimations()` 处把透镜瞬打回旧槽模型位再重滑（Transition
  `setPosition` 中断续位机制被清动画截断）；②三树 ZStack 瞬切、每树一栏：跨树
  提交后可见栏换成目标树的岛，而该岛从旧槽位**整段重滑**（非从松手位置落位）。
  修复 = 岛 `.ended` 按 TG :555-604 单跳语义（同步预置 `selectionIndex` 直达提交
  槽、同值短路消除二次推）+ 跨树**提交交接** `TGLensHost.commitHandoff`（松手瞬间
  寄存透镜可见位，目标树的岛在紧随 apply 里先瞬时落位再续簧）；同期把拖动中图标
  放大改为即时（对齐 TG :550 的 immediate 帧过渡）。档 = docs/tg-lens-port.md §2 ⑬。
- **切页转场·对齐 TG 缩放淡入（2026-09-30 同日，pp「tg 不是瞬切，有个切页的轻微
  放大动画」）**：原 ZStack 三树瞬切（pp 2026-09-16 旧拍板）改为 TG 数字化转场
  （TabBarController.swift:279-330）：新页 zIndex 置顶 → alpha 0→1（0.1s）+
  从 (视图高−3)/视图高（≈0.9965，缩 3pt）弹簧到 1.0（0.15s、延迟 0.1s）；旧页
  1→同起点缩放（TG :297，0.12s 弹簧）并在 ~0.28s 溶解窗口内留于下层（TG :314-330
  新页盖旧页淡入的语义）；宽屏 regular 不播（TG :283-285）。实现 =
  RootModeTabsView.tabTree 的 scale/opacity/zIndex + previousMode 窗口。
  **已知偏差（tg-parity 记录）**：TG 的栏是 TabBarControllerNode 的独立层、不参与
  缩放；本仓栏挂树内（safeAreaInset 架构所限）会随树缩放——幅度 0.35%（≈0.2pt
  栏高）+溶解期与旧栏约 1px 重影 0.1s，肉眼不可辨，若日后可察再评估反缩放。
  （时态注：本条为 v1 记录；该偏差已由下方 v2 条目消除——栏不再随缩放。）
- **切页转场 v2·缩放迁入栈内（2026-09-30 第三轮装机修正，pp「整个页面都在抖
  根本不是切页动画 / 切页时 tab 栏被截一半」）**：v1 把 `.scaleEffect` 挂在树容器
  （NavigationStack 外层）——装机实锤打坏栈内 safeAreaInset 求值：root-list 底安全
  区切页后从 98（栏 64 + Home 34）掉到 64、且 64↔98 瞬跳（build 430 日志；旧瞬切
  版同类操作恒 98）→ 整页内容上下跳 34pt + 栏底被裁出屏。修复 = 缩放迁入**各树
  NavigationStack 的 root 内容、safeAreaInset 内侧**（新 `TreeSwitchZoom`，挂点 =
  ContentView.stackLayout / RemoteRootView / WorksListView 三处；社区同款结论：
  缩放/位移必须作用在栈内内容，挂栈外包裹层会丢 safe area）。树容器只保留 v1
  装机中除缩放外未见异常的部分（opacity/zIndex/溶解窗口——注意 zIndex 与溶解
  窗口系 v1 同批引入、瞬切版未跑过；若装机仍异常，下一手候选 = 拆溶解窗口 /
  geometryGroup）。**栏不再随缩放**——上一条「已知偏差」随之
  消除。装机判据：切页期间 `[SAFE] root-list bottom=98.0` 恒定（再见 64.0 = 复现）。
  已知取舍：缩放只覆盖 root 内容——树停在 push 页面时切页不播（待装机观感再评估）。

## 7. TG 数值对照表（2026-09-30 立表——源码 + pp 实机像素反演双据）

> 维护规则：栏相关每个数值以本表为对账底稿；改动栏几何必须同步本表并复跑反演。
> 「实机反演」= 对 pp 的 TG 截图 16-bit 解码/剖线测量（数据在会话记录内可重跑）。

| # | 项 | TG 真值 | 出处 | 本仓实现 | 状态 |
|---|---|---|---|---|---|
| 1 | 槽位数 | 4 | TabBarComponent:666/:711 | 4（3 实 + 1 设置齿轮） | ✅ |
| 2 | 水平边距 | 20（底距≤28 档） | TabBarContollerNode:213-215 + 反演 | 20 | ✅ 本批 |
| 3 | 格宽 | 68.25（⌊68.25⌋ = 68） | :666/:711 + 反演 68.0 | 68.25（不取整——复审裁定 0.25pt 不可辨） | ✅ 本批 |
| 4 | 栏高 | 64 = 56+4×2 | :664 + 反演圆钮 192px | 64 | ✅ 本批 |
| 5 | 栏底距 | ≈20（19.7） | 反演 | 20（安全区 34 − offset 14） | ✅ 本批 |
| 6 | 圆钮 | 64×64 | :899-903 | 64×64 | ✅ |
| 7 | 胶囊↔圆钮间距 | 8 | :666 | 8 | ✅ |
| 8 | innerInset | 4 | :655/:870-872 | 4 | ✅ |
| 9 | 选中矩形 | item 外扩 4（宽 +8） | :872 | 同（岛直传私有件） | ✅ |
| 10 | 透镜视觉 | = item 槽位（内收 4） | LiquidLensView 26 路径 :464/:376（legacy 分支 :471 同义） | 岛=私有件自渲染；legacy=槽宽宽 + 4pt 内缩 | ✅ 本批 |
| 11 | 按下放大 | 1.15 | :835 | 1.15（两路径） | ✅ |
| 12 | 弹簧 | spring 0.4；26 实参 m=1/555.027/47.118 | :540/:587/:599 + UIKitUtils.m:68-84 | 岛=同机制；legacy=SwiftUI 近似（已注） | ✅ |
| 13 | 拖动模型/clamp | start+Δ；clamp(size−lensW) | :423/:538-545/:885 | 同 | ✅ |
| 14 | 图标竖位 | 偏上（下留标签区） | :1181 + 反演 | 居中 | 有意差异（纯图标无标签，pp 拍板） |
| 15 | 图标尺寸 | ~25 | :1171-1181 + 反演笔画 | 27 栅格 | 接近，装机观感再定 |
| 16 | 文字标签 | 有（≈13pt） | ItemComponent | 无 | 有意差异（pp 拍板） |
| 17 | 栏宽上限 min(500,w) | 有 | :658 | 无 | 有意差异（iPhone 不可达） |
| 18 | 等分取整 floorToScreenPixels | 有 | :711 | 精确分数 | 有意差异（<1pt） |
| 19 | 窄格加宽（<56 → 67.2） | 有 | :789-795 | 无 | N/A（格宽 68 > 56） |
