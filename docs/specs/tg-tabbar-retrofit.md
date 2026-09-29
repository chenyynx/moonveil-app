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
6. 深色/浅色双模式正常；登录盖 / 设置 sheet / 资料页 zoom 不受影响。

## 2. 架构（治根点）

```
ZStack 三树保活（瞬切：当前树 opacity 1 + 可命中，其余保活不可见）
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
