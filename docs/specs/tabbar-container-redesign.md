# 容器化重构 · 对齐 TG 的栏架构（2026-09-30）

> pp 拍板：「如果架构导致，就制定对齐 TG 的实现调整到正确架构，而不是打补丁」。
> 本文件是该批次的**行为合同 + 设计冻结**：实现与验收均以此为准。
> 病根一句话：TG 的栏是**单实例、容器持有、被 push 盖**；我们做成了
> **三棵树各一份栏副本 + 瞬切 + 人工交接缝合**——所有跨树切页的诡异症状
> （滑动两次 / 发亮快 / 太快 / 高度跳）都长在「跨实例状态同步」这条 TG 里
> 不存在的环节上。本批把结构换回 TG 的真形。

## 0. 状态

- 分支：`feature/tabbar-container`（自 feature/tg-lens @ 1611efc 起）
- 审计输入：B-1（local 线路由矩阵）⟨待补⟩、B-2（remote/works 线）⟨待补⟩、
  B-3（栏挂点/壳层）⟨待补⟩、B-4（TG 对照核验）⟨待补⟩
- 落码前须过：本文件 §4/§5 清单评审 → 开工

## 1. 根因（实锤链）

### 1.1 TG 的真形（~/tg-ref/ 源码实锤）

| 事实 | 出处 |
|---|---|
| **栏单实例**：唯一链 1×TabBarControllerImpl → 1×TabBarContollerNode → 1×`ComponentView<Empty>`（反复 update 非重建）→ 1×TabBarComponent.View → 1×LiquidLensView（LiquidLensView(kind: .externalContainer) 全目录唯一创建点）。子页只提供 tabBarItem 数据，全目录无"每页建栏"结构 | TabBarContollerNode.swift:58/232、TabBarComponent.swift:433、TabBarController.swift:157/453 |
| **选中动画由该单实例自跑**：`isChangingSelectedIndex → spring(0.4)` 更新同一个栏——不存在跨实例交接 | TabBarContollerNode.swift:218-229 |
| **push 覆盖靠容器**：TelegramRootController 自身是 NavigationController（:73，全摘录唯一导航栈）；TabBarControllerImpl 是普通 ViewController（TabBarController.swift:47，无栈），被 `pushViewController` 成根栈 index 0（:249），其余页面插入其上（:309/:655 均视容器为 index 0）→ 容器内页面要 push 只能落在根栈、盖在容器之上 | TelegramRootController.swift:73/202-249 |
| 内容切换动画（非栏）：旧页 scale 1→0.998·0.12s；新页 scale 0.998→1·0.15s delay 0.1 + alpha 0→1·0.1s，alpha 完成即 commit 移除旧 node | TabBarController.swift:274-330 |
| 栏另有隐藏通道：`tabBarHidden`（滑出底边、0.4s slide、隐藏时不给子页留 inset；toolbar 非空时栏 alpha=0）；**触发场景在摘录外查不到**——诚实记录，不作为设计依据 | TabBarContollerNode.swift:171-177/291/298、TabBarController.swift:149-154 |

### 1.2 我方的偏离形

三棵树（local/remote/works）ZStack 保活，**每棵树 root 页各挂一份 ModeTabBar**
（ContentView 两分支 / RemoteRootView / WorksListView 四处调用点），跨树切页靠
`CommitHandoff`（岛路径）把「松手瞬间可见位 + 图标缩放」从出发岛人工递给目标岛，
legacy 路径无交接；光晕（二值私有态）用 `iconScale > 1.08` 阈值近似。

### 1.3 症状 → 结构映射（装机 1611efc 仍复现）

| 症状 | 机理 |
|---|---|
| 灰底/透镜"滑动两次" | 旧树栏在 120ms 溶解窗口内继续动画 + 新树栏从旧槽重滑（交接条件不满足时）；两实例并存 |
| 切页"发亮快" | 光晕二值态无法跨实例传递——快按瞬熄 / 慢按瞬满，阈值近似无连续解 |
| 切页"太快/卡" | 旧栏动画被瞬切截断 + 切换窗口内两套 UIKit 透镜动画叠加 |
| 配置页"先下后上" | safeAreaInset(栏) 求值链在切页帧两段跳（64↔98，差 34pt=Home 区）→ overlay 居中内容位移 ~17pt（v2 病史 0→98·214ms + 启动帧 64→98 日志实锤；欢迎页无探针=观测盲区） |

### 1.4 不属本批的独立病灶

- 新会话 push 掉帧（草稿 VM 每次新建 +30MB、InputBar 四阶段校正窗 1.1-1.4s、
  键盘 0→34→336 跳变）——**包 A `feature/chat-open-perf` 独立修**，与本批并行。

## 2. 目标结构（对齐 TG 的等价形）

```
外层 NavigationStack（"容器栈"，path=[ContainerRoute]）   ← 新增：TG 的根栈等价物
 └─ root: 容器视图（RootContainer）
     ├─ ZStack 三树保活（各树的内层 NavigationStack 保留——只作 root 壳 + toolbar 家）
     │    └─ 各树 root 底部 = 静态高度占位（复刻现状 inset 总量，无 UIKit/测量件）
     └─ ModeTabBar ×1（容器顶层唯一实例，几何/视觉原样）
 └─ destination: 全部深页——聊天（local/remote）· 设备详情 · works 详情（如有）
```

- 切 tab = 容器内内容切换（现行 TG 数字化转场保留：新页 alpha 0.1 / scale 0.15·delay 0.1，
  旧页 scale 0.12，溶解窗口 120ms）——**栏在容器顶层不动**，透镜弹簧天然连续。
- push 深页 = 容器栈 push → 整页盖住容器（含栏）✓；pop 手势 → 容器（含栏）原位
  揭示、纹丝不动 ✓——验收判据 2/3 由结构本身兑现，零 hack。
- **CommitHandoff / keepGlow 阈值 / 跨树交接整段退役**（单实例无跨树可跨）。

### 核心设计决策（D1-D8）

| # | 决策 | 理由 |
|---|---|---|
| D1 | 深页统一迁往外层容器栈；**树内 NavigationStack 保留**（root 壳+toolbar 家） | toolbar 体系（≡齿轮/身份胶囊/搜索）零改动；避免条件 toolbar 的 SwiftUI 怪癖 |
| D2 | 栏几何原样搬运（ModeTabBar 视图本体不改），仅换挂载点到容器顶层 | 尺寸对账成果（§7 表）全保留；视觉零变化 |
| D3 | 三树 root 的 safeAreaInset(栏) → **静态占位**（高度=现状对账值，探针 98 基线） | 求值链零活件 → "先下后上"竞态源消失 |
| D4 | 切页动画（treeSwitchZoom / 溶解窗口）**本轮挂点不动** | 少动少错；结构换完后另批简化 |
| D5 | `route(to:)`（切 tab）语义：**清空容器栈**（各线切走弹根） | 栏可见 ⇔ 容器栈为空（TG 语义）；程序化通道一致性 ⟨B-1 审计后定稿细节⟩ |
| D6 | iPad 宽屏（B-1：isWideLayout = isIPad && width≥700，**iPhone 恒窄屏**）：窄屏走容器栈单实例栏；**iPad 宽窗档维持现状**（splitLayout 自己的条件栏挂点 :2232 保留、selectedSessionId 通道与 20 个点不动；容器栏在宽窗档不渲染） | 宽屏无 push 覆盖模型；pp 验收主场景 iPhone=全覆盖；**诚实标注残留：iPad 切 tab 的栏仍是三实例形态（下批评估）** |
| D7 | 壳层（登录盖/settings sheet/资料 zoom/task）挂点：容器栈**之外**（现 RootModeTabsView 位） | presenter 恒活，语义不变 |
| D8 | 岛/legacy 判定日志埋点随包 A 先行（诊断用） | 单实例化后两路径自动归一，但装机验收需要知道走了哪条 |
| D9 | remote 线的 isPresented 式导航（showsChat/showsDeviceDetail）**统一改 value 式**容器栈路由；"当前树是否在 root"由容器层从 path 推导（remoteAtRoot 等 flag 消费点上收/退役，⟨B-3 消费点清单后定稿⟩） | 单一路由数据源（path）才能支撑 D5"清空栈"与系统回写同步；两套状态（path+isPresented）会让清栈永远漏一半 |
| D10 | 占位形态定稿：三树 root 底部改 `Color.clear.frame(height: ModeTabBar.barHeight /*64*/)` 作 `safeAreaInset(edge:.bottom,spacing:0)`——**不硬编码 98**：inset 传播 64 + 系统 home 区（34/0 自适应）= 现状 98 的自动等价；无 UIKit、无测量、无动画 | B-3 实锤：现状栏布局高即 64（.offset(y:14) 是视觉位移不占布局），98=64+34 全链对账 |
| D11 | 外层栈 root（容器）隐藏自己的导航栏（`.toolbar(.hidden, for:.navigationBar)` 或等价），导航栏归各树内层栈 | 防双层导航栏；内层栈保留 D1 |

### 已知社区风险与 C2 空壳验证点（嵌套栈）

社区对"NavigationStack 嵌 NavigationStack"有警告（toolbar 裁剪 FB14898777、toolbar 持久化/标题丢失等——
症状场景多为"内层还会 push/多栈互动"）：本设计中**内层栈只作 root 容器、永不 push**，风险面不同，
但不能假设安全。**C2（容器空壳，深页暂留树内）的装机验收必须包含**：
① 无双层导航栏；② 各树 toolbar（身份胶囊/齿轮/搜索）push/pop 后完整不裁剪；
③ 切页转场中两树导航栏交叉淡入正常（toolbar diff 不闪叠）；④ 键盘/栏/布局探针值同现状（98 恒定）；
⑤ 外层栈 push（C3 起才有）穿透盖住容器含栏。任一不达标 → 停线回头改设计（备选：b2 单栈化，toolbar 体系整体上收，
或退回打补丁路线并如实汇报）。

## 3. 导航路由设计

- 新增 `ContainerRoute`（或扩展 ChatRoute——⟨B-1/B-2 审计后定稿：含现有 `.local/.remote`
  聊天 case + 设备详情 + works 详情（如有）⟩）。
- local 线（B-1 实锤）：唯一路径通道 `[ChatRoute]`（ContentView:1269 定义 / :2240 绑定 /
  :2261 目的地；写点 :3810/:3879/:3882）；唯一程序化漏斗 `pushChat`(:3861，后台门
  :3863 + currentStackSessionId :3869)、`flushPendingChatRoute`(:3890)、
  `openSession`(:3913)/`switchToSession`(:3898)（两者先判 isWideLayout）；上游入口
  14 处（.newChatRequested :1326 / quickAction :1342/:1355/:1347 / moveInput :1442 /
  openSessionFromIntent :1464（六路发帖合流）/ 通知缓冲 :1782 / 冷启分享 :1797 /
  热态分享 :2040 / 空态 Step3 :4244 / 分组 New Chat :4775 / flush :1388/:2145）。
  **改道 = 把整套 path 机制（含伴随状态 pendingChatRoute/currentStackSessionId/
  previousStackSessionId/syncFixedBarFlags）迁到容器共享路由**；14 处上游入口不动
  （汇入漏斗）；窄屏内层栈去 path/destination 绑定、只留 root 壳。
  声明式唯一活口 :3057（会话行 NavigationLink）。
- remote 线（B-2 实锤）：push 目的地仅两个——设备详情 `RemoteDeviceDetailView`
  （RemoteSessionListView:387，写入点 :740/:764/:777/:783，删除后出栈 :408）与
  聊天 `SessionChatView`（:430，写入点 :194/:267/:890；切走弹根 :213/:214）。
  均为 isPresented 式 → 统一改 value 式容器栈路由（见 D9）；`remoteAtRoot` 的
  维护点（:426/:437 onChange）上收容器层。
- works 线（B-2 实锤）：**零 push、零二级页**——构件行不可点，影音瓦片→全屏相册
  （fullScreenCover :112），搜索/资料页均 sheet/cover。**works 线零迁移**（仅栏
  挂点改占位）。
- 深链/通知/分享/QuickAction 入口全部汇入现有单通道后再去容器栈——**路由解析层
  （ChatRoute/URL 解析）不动，只换承载栈**。

## 4. 逐文件改动清单（施工用——⟨B-1/B-2/B-3 审计后补全行号⟩）

1. **新增** `src/ios/Views/ModeTabs/RootContainerView.swift`：容器栈 + 容器视图 +
   单实例栏（pbxproj 4 处登记 + audit-swift-registration.py 校验）。
2. `RootModeTabsView.swift`：演进为 RootContainer（三树 ZStack 迁入；壳层修饰符原位保留）。
3. `ContentView.swift`：NavigationStack(path:) 的深页职责移交容器栈（pushChat 等写入点改道）；
   两处 safeAreaInset(ModeTabBar) 改静态占位。
4. `RemoteRootView.swift`：同上（:37 栏 → 占位）。
5. `Works/WorksListView.swift`：**仅栏挂点改占位**（B-2：零 push 零迁移）。
6. `RemoteSessions/RemoteSessionListView.swift`：showsChat/showsDeviceDetail → 容器栈路由。
7. `TGLens/TGLensHost.swift`：CommitHandoff / keepGlow / 交接相关整段删除。
8. 注释墓碑更新（各树 root 的"栏在栈内"说明改"栏在容器层"）。
9. 占位高度对账：探针（debugSafeBottom 基线 98）复核。

## 5. 施工序列（一个包，多 commit）

- C1：本 spec 落档（设计冻结）。
- C2：容器栈 + RootContainer 空壳（三树+栏迁入；深页暂留树内——视觉与现状一致）。
- C3：local 线深页外迁（path 机制整体迁容器共享路由；14 上游入口不动；宽屏通道不动；
  内层栈去 path/destination）+ 装机验证锚点。
- C4：remote/works 线外迁 + 栏单实例化（三处 inset → 占位）+ 交接退役。
- C5：清理（墓碑注释、死码、探针盲区补 welcome overlay 探针）。
- 门禁：swift-parse-check --changed / audit-swift-registration / import-scan /
  freeze-check（每 commit 前跑）；push → dispatch → 出包（全链）。

## 6. 验收判据（装机）

1. 切 tab：选中胶囊/透镜**单次连续滑动**（无二次滑动）；快按慢按节奏一致（无"发亮瞬熄/瞬满"）；
   无卡顿感。
2. push 聊天/设备详情：标准右滑入、整页盖住栏。
3. 交互式 pop 中途：一级页（含栏）原位平移揭示，栏纹丝不动、无"隐藏→出现"。
4. 切到本机配置欢迎页：中间内容**不再先下后上**（静态占位；顺带补 welcome overlay 探针）。
5. 深链 / 分享 / 通知 / QuickAction 进入聊天全链回归不退化；气泡/键盘/输入栏行为不变。
6. 登录盖 / settings sheet / 资料页 zoom 不受容器化影响。
7. iPad 宽屏：按现状行为验收（D6 保守）。

## 7. 风险与回归面

- 导航层是历史重灾区（墓碑注释多）：每条深链入口（分享/通知/widget/quick action）
  都要过回归；C3/C4 分两步就是为了出错时可二分。
- 占位高度如与现状有 1-2pt 偏差 → 用探针 98 基线对账。
- 磁盘→pbxproj 方向（新文件漏登记）由 audit-swift-registration.py 兜底。
- 若装机发现残余：探针体系（NavTrace/SAFE/PathProbe）已有，先定位再动。

## 附录 · 审计输入摘要（2026-09-30，B-1~B-4 子代理产出）

### A. 栏与壳层（B-3）
- ModeTabBar 4 调用点：ContentView :2232（宽屏条件挂）/ :2253（窄屏常驻）、WorksListView :76、RemoteRootView :37。
- 窄屏链序：NavStack(:2240) → sessionList(useNavigationLinks:true) → Group{stackList.treeSwitchZoom(.local) :2925} → debugSafeBottom("root-list") :2930 → … → safeAreaInset(栏) :2253 → ignoresSafeArea.keyboard :2260 → navigationDestination :2261。
- treeSwitchZoom 7 挂点：ContentView:2925；RemoteRootView:108/:128；WorksListView:156/:164/:169/:188。
- 探针 2 枚：root-list(ContentView:2930，缩放外/栏 inset 内)；chat(AIChatView:2825)。
- 壳层修饰符（RootModeTabsView）：soulProfile cover :92（死 presenter）/ soulMdChanged :99（write-only）/ settings sheet :108 / task restore :113 / login gate :118 / QR :138 / manual :144。
- 全局状态位消费：mode 活；previousMode 仅 :181；seenRemote 仅 :215；showSettings 活（含 ContentView:2108 读-改-写守卫）；localAtRoot/localSelecting 死；remoteAtRoot 死（零读取）。
- 入口：MinisApp.onOpenURL :287-299（锁屏缓冲 :207-216）→ DeepLinkRouter / Share / BackupOpenRouter；AppDelegate :98-130 → QuickActionRouter → .newChatRequested；⌘N MinisApp:438-444。

### B. 审计遗留说明
- B-1 的完整行号矩阵（21 path 点 / 6 漏斗 / 14 入口 / 宽屏 20 点）以本文档 §3 精化段 + 会话记录为准，施工时以当时代码复核行号。
- B-4 诚实记录：TG `tabBarHidden` 触发场景在摘录外查不到；聊天 push 具体语句摘录外——结构证据（唯一根栈 + 容器 index 0）已足。

## 8. 退役清单（随本批删除）

- `TGLensHost.CommitHandoff` 全结构 + 消费逻辑 + `currentSelectedIconScale`
  采集；"交接续实数 v3"注释墓碑。
- `keepGlow` 阈值逻辑。
- 三树 root 的 `safeAreaInset(ModeTabBar)` 调用（→静态占位）。
- **死 flag 实锤（B-3）**：`localAtRoot`/`localSelecting`（仅 :1501/:1502 日志消费）、
  `remoteAtRoot`（全仓零读取，注释所指 gearVisible 不存在）——C5 全仓双查后删。
- **死残留（B-1）**：`pendingNewChatAfterPop`(:1307)/`pendingNewChatTargetId`(:1311)
  无消费者；`deepLink.pendingSessionId`(:2118-2126) 无写入者——C5 处理。
- 外壳卫生（可另批）：RootModeTabsView `showsSoulProfile` 死 presenter(:36/:92)、
  `soulName` write-only(:38-41)。

## 9. 审查记录与修订（2026-09-30 · R1-R5 五路并行对抗审）

> 流程：五个独立子代理（语义逐点 / 逐字保真 / 全仓遗漏 / 门禁工程 / 场景对抗），
> 互不共享结论；全部缺陷在提交前修复并复验（parse 绿）。
> ⚠️ 行号说明：本文档 §3 等处的旧行号引用（pushChat :3861 / destination :2261-2320
> 等）为 C3 迁移前坐标；C3 后这些符号已迁入 ContainerNav / RootModeTabsView，以代码为准。

### 9.1 五路结论
| 路 | 范围 | 结论 |
|---|---|---|
| R1 语义逐点 | ContentView 全部替换点 | 2/3/4/6 类观察者/注入块逐场景等价（前提=path 仅承载 local 深页，已验证）；出栈锁步/动画纪律/分享目标/环境继承无回归 |
| R2 逐字保真 | destination 块 60 行 | 行行对应，14 处 token 编辑全部在声明集合内，**零未声明漂移** |
| R3 全仓遗漏 | 符号外引/新文件/pbxproj | 旧符号全仓 0 代码残留；pbxproj 4 处登记双 parser 复核通过；发现行点击命中区缺陷 |
| R4 门禁工程 | 7 脚本 + 独立复核 | 6 绿；唯一红=authaa allowlist 旧 sha 遗留（与本批无关，见 9.4）；staged 无意外文件 |
| R5 场景对抗 | 10 场景走查 | 3 个"最怀疑点"：P1 导航栏泄漏 / P2 划回写回 / P3 手势仲裁——P1 已修，P2/P3 列装机首查 |

### 9.2 修订动作（均已落码并 parse 复验）
1. **行点击命中链（高）**：Button label 从 EmptyView（零命中区）改为
   `Color.clear.contentShape(Rectangle())` + `.buttonStyle(.plain)`。
2. **导航栏泄漏保险（中高）**：容器 destination 两分支显式
   `.toolbar(.visible, for: .navigationBar)`（仓内先例 RemoteChatPageToolbar:36）。
3. **单例跨重建（中）**：新增 `ContainerNav.resetForRootRebuild()`，挂语言切换点
   （ContentView 设置页 :7220 后，唯一整树重建源）——复刻"重建回列表"旧行为。
4. **搜索镜像初值（中低）**：ContentView onAppear 补同步（幂等）。
5. **D5 切 tab 清栈（中）**：推演确认"直接实现在 mode onChange 处会误杀同帧 push
   的新会话"且当前不可达——改为不变量注释（RootModeTabsView mode onChange 内），
   C4 按注释挂点处理。
6. 日志 category 跟随原文（ContainerNav 双 logger）；ContentView 改 @ObservedObject；
   死入口补 `.buttonStyle(.plain)`；注释修正（脚本误替换旧名、死残留标注）。

### 9.3 行为变化记录（有意/已复刻）
- `.id(appLanguage)` 重建已由 9.2-3 复刻旧行为（回列表）。
- **宽窗档（iPad>700pt）深页不再随布局档消失**（容器栈与宽度无关；旧行为栈随
  stackLayout 换出而消失）——接受并记录（R1-F2/P6）。
- PATH-PROBE 语义：日志栈深=全局容器栈（C4 后混入远端/works——排障知悉）。
- 多窗口（若未来开多 scene）：共享单例将跨窗口同栈（现状未开，记录）。

### 9.4 C4 前置必改清单（R1-F3 实锤，勿遗忘）
C4 把 remote/works 深页搬进容器栈时，"全局栈=本机会话"的隐式契约必须显式处理：
① 分享注入 foreground 判定（ContentView ~:2048）；② 出栈清理块（~:1977-2017，
清 currentStackSessionId/activeSessionId/全表刷新——远端出栈会误触）；③
`localAtRoot`/searchFocused 守卫（~:1485/:2142）；④ 搜索镜像多写者（D9 时给
owner 或随树切换清理）。
**门禁遗留**：`scripts/authaa-skin-allowlist.txt` 的 AppGlassButton.swift 旧 sha
（R4 实锤为 1b77917 遗留、与本批零关系）需 pp 点头重登记，否则该门禁持续红。
本批冻结面零触碰已核。

### 9.5 装机首查项（按序）
① 点会话行打开聊天（命中链）+ 长按菜单/拖拽不劣化（失效退路=onTapGesture，
仓内先例 ContentView:4489）；② 聊天页返回键/边缘划回存在（导航栏不泄漏）；
③ 划回后 PATH-PROBE count 归零（写回存活）；④ 宿主被外层 push 期间内层 onChange
仍触发（destDISAPPEAR 后 vm 挂起日志）；⑤ push 滑入动画在（Button 事务）；
⑥ 搜索/宽屏/登录盖/设置不受影响。

### 9.6 首装机判例（2026-09-30 包 B 第一版 · 顶栏环境传播）

**实锤**：容器 root 的 `.toolbar(.hidden, for: .navigationBar)` **写进 SwiftUI
环境**、顺视图树把**三棵内层栈的导航栏一并隐藏**（装机症状：顶部所有按钮消失、
只剩底栏）——作用域超出审查预判的「同栈 destination 泄漏」（R3-F2/R5-P1 方向）。
**修复（C3.1）**：内层四处就近显式 `.toolbar(.visible, for: .navigationBar)`
对冲（ContentView stack/split + RemoteRootView + WorksListView；就近覆盖语义）。
🔴 **判例**：嵌套栈的 toolbar 可见性偏好按**环境**传播、作用域 ≥ 整棵子树——
此后**新增任何内层栈/子树**（C4 works/remote 改造、未来页面）**必须显式钉
visible**，禁止依赖「外层 hidden 只作用于外层」的假设。
**同包遗留（待崩溃日志定性）**：① 新会话闪退（行点击开会话正常——机制通、
命中链修复生效；疑点=嵌套栈×draft 专属链）；② 切页残影/套层（疑点=溶解窗口
在嵌套结构下的渲染）。

## 10. C4 施工单（草案 · 待 C3 装机验证通过后启动）

> 目标：remote 线深页上收容器栈（D9）+ 栏单实例化（D2/D3/D10 落地）+
> 跨树交接机制退役。本单是施工前的设计冻结，落码前按 §9.4 清单复核。

### 10.1 remote 深页迁移（B-2 审计地图）
- **路由类型**：扩展 `ChatRoute` 加 `case deviceDetail(connectorId: String)`
  （H45/48 现有 `.local/.remote` 不变；logTag/sessionId 兼容分支补全）。
- **两个目的地的写入点**改 value 容器路由（isPresented 退役）：
  `RemoteSessionListView` showsChat 写入 4 处（:194/:267/:890 + 切走弹根 :213）→
  `containerNav.pushChat(.remote(...))` / 退出 `dismiss` 语义换 `containerNav.path` 清；
  showsDeviceDetail 写入 5 处（:740/:764/:777/:783 + :408 出栈）→ `.deviceDetail`。
- **destination 渲染**：两分支整体迁 RootModeTabsView destination
  （SessionChatView 的 `service.chat` 依赖守卫/RemoteDeviceDetailView 的
  connector 解析 :392-417 逐字搬迁+防白屏 pending 分支）。
- **remoteAtRoot 维护点上收**（:426/:437 onChange → 容器层 path 推导；R5-P4 的
  “纯程序化切换”清栈挂点同批定稿）。

### 10.2 栏单实例化（4 挂点 → 1 + 3 占位）
- 容器栏 = RootModeTabsView 的 ZStack 顶层 `ModeTabBar`（**本体零改动**，
  D2 几何原样；仅挂点变化）。
- **各档各树归位公式（防回退关键）**：
  `showContainerBar = (horizontalSizeClass != .regular) || (router.mode != .local)`
  —— iPad 宽窗档 local 树的栏仍由 `ContentView.splitLayout` 自带
  （selectedSessionId==nil 条件保留，:2232 不动）；其余全部尺寸/树由容器栏
  承担（含 iPad 宽窗的 remote/works——现状它们树内自带栏，若直接占位化会丢栏
  =功能倒退，本公式即对策）。
- 三树 root 的 `safeAreaInset(ModeTabBar)` → `safeAreaInset { Color.clear
  .frame(height: ModeTabBar.barHeight) }`（D10；三处：ContentView 窄屏分支
  :2253、RemoteRootView :37、WorksListView :76）。
- 占位高度对账：`[SAFE] root-list bottom=98` 恒定（64+34 自动）。

### 10.3 交接退役（TGLens 域）
- `TGLensBarView.CommitHandoff` 结构体（:114-122）、消费块（apply 内
  :277-310）、寄存块（.ended 内 :378-384）、`currentSelectedIconScale`
  （:417-434）整段删除；相关 v3 注释墓碑同删。
- `keepGlow` 阈值逻辑随消费块一并消失。
- **删除后自检**：单实例栏下 lens.update 的 transition 调用点只剩
  began/changed/ended 三态（TG 原件语义），grep `CommitHandoff` 全仓归零。

### 10.4 C4 验收（装机）
- 复跑 §9.5 ①②③⑤（现在涵盖 remote 线）；新增：
  ① remote 会话行→SessionChatView（push 盖住含栏容器）；② 设备详情进出；
  ③ **切页判据全量**（§6 1-3：单次连续滑动/无二次/发亮连续——栏单实例后首次
  真正可验）；④ iPad 宽窗档四态矩阵（local 有栏收栏规则/remote 有栏/works 有栏）；
  ⑤ 跨树交接相关代码删除后：快按/慢按/拖动三节奏不回归。
