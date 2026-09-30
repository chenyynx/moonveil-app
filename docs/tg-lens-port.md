# TG 液态透镜移植档案（TG-LENS-PORT, 2026-09-30）

> pp 拍板「B：真·移植 TG」的批次档案：出处、许可证、适配记录、私有 API 风险、
> 回退设计。行为与验收以真机为准；本文件随批次提交进仓。

## 1. 来源与许可证

全部搬运自 **Telegram-iOS**（github.com/TelegramMessenger/Telegram-iOS，master）：

| 本仓文件（src/ios/Views/ModeTabs/TGLens/） | 上游路径 |
|---|---|
| LiquidLensView.swift | submodules/TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift |
| GlassBackgroundComponent.swift | submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift |
| TouchEffect.swift | 同上 /Sources/TouchEffect.swift（+ GlassHighlightGestureRecognizer） |
| Transition.swift | submodules/ComponentFlow/Source/Base/Transition.swift |
| CAAnimationUtils.swift | submodules/Display/Source/CAAnimationUtils.swift |
| DisplayLinkAnimator.swift | submodules/Display/Source/DisplayLinkAnimator.swift |
| SimpleLayer.swift | submodules/Display/Source/SimpleLayer.swift |
| Spring.swift | submodules/Display/Source/Spring.swift |
| TGLensSupport.swift | UIKitUtils.m / UIViewController+Navigation.{h,m} / Display 包装层 / ListViewAnimation.swift 的 ObjC→Swift 语义转写 |
| TGLensHost.swift | 本仓自研桥接（非搬运） |

**许可证**：Telegram 官方声明 iOS 应用代码为 **GPL v2 or later**（telegram.org；
仓内无 LICENSE 文件为上游仓管问题，社区 issue #97 有讨论）。本仓 moonveil-app 为
GPLv3 开源工程，按「v2 or later」条款并入，许可证兼容路径成立；各文件头注已标明
出处与本仓许可证状态。

## 2. 适配记录（相对上游的每一处差异）

- **模块边界消失**：上游 Bazel 多模块（Display/ComponentFlow/…）→ 本仓单模块，
  所有 `import` 已收敛（逐文件头注列明删了哪个、并已全文件扫描确认无残留符号）。
- **LiquidLensView**：删 <26 遗留 blob-mask 分支（本集成 iOS 26+ 专用；私有类
  取不到时优雅空转）。其余逐字；2026-09-30 装机回归追加适配 ④
  `currentSelectionOriginXForHandoff` 读取口（跨树提交交接用，presentation 优先）。
- **GlassBackgroundComponent**：LegacyGlassView 类型引用改 UIView（同 <26 不可达域）；
  删组件系统包装类（ComponentFlow 依赖）与 GlassContextExtractableContainer（本集成
  不用）；其余逐字。
- **TGLensSupport**：ObjC→Swift 语义转写（弹簧三件套、_solveForInput 动态调用、
  CAFilter、单色化、EffectSettingsContainerView、SpringParametersOverride 族 +
  CALayer.addAnimation swizzle、generateImage 的 renderer 等价实现）。
- **未移植**：MeshTransform（仅 LegacyGlassView 使用）、luma 限制 swizzle（TG 全局
  性能件，与本品无关）、TG 组件系统（ComponentFlow）、ContainedViewLayoutTransition
  （旧引擎，被 Transition.swift 取代）。
- **[对抗复审 2026-09-30 修正四项]** ①TGLensSupport.swift 在 pbxproj 中**不加**
  `-default-isolation MainActor`（含进程级 swizzle 与覆盖栈，CoreAnimation 可在非主
  线程触达；TG 原件为 ObjC 无隔离假设）。〔CI 首跑复审补注〕实测 target 级已设
  `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`（SWIFT_VERSION=5 模式）⇒ 全 target
  文件（含本文件）事实上默认 MainActor，逐文件 flag 与该设置为冗余、Swift 5 模式无
  运行时强制；如后续真需非隔离，须显式 `nonisolated`；②交互按 TG 原样放回岛内——岛保持可交互
  （玻璃 `UIGlassEffect.isInteractive` 的触摸响应需要真实命中），岛内挂 0 延迟
  UILongPressGestureRecognizer（cancelsTouchesInView=false，与玻璃响应并行），
  提交经 onCommit 回调；③透镜跟手 = TG 精确模型（起点 = 被按槽位透镜 minX，其后
  按指尖位移增量，保留抓取偏移）；④`generateImage` 手动翻回 y-up 上下文（对齐 TG
  的 `withContext` 朝向；仅 <26 遗留路径可达）。
- **[CI 首跑 2026-09-30 修正三项]** ⑤`animationDurationFactor` 单模块形态统一：
  上游是跨模块双形态（Display 侧函数 `animationDurationFactor()` / ComponentFlow 侧
  静态 var），单模块合并须二选一——统一为**函数形态**（Display 逐字搬运件
  CAAnimationUtils.swift 16 处函数调用 vs var 形态零调用；Transition.swift 仅声明
  一行改动、计算体逐字未动）；⑥弹簧 Impl 族参数标签对齐 ObjC 原版**位置式**
  （`makeSpringAnimationImpl` / `make26SpringAnimationImpl` 去掉转写时多加的
  `duration:` 标签，与 CAAnimationUtils.swift:127 等位置调用一致；Swift 包装层
  `makeSpringAnimation(keyPath:duration:)` 保持标签式，同上游 Display 分层）；
  ⑦`UIAnimationDragCoefficient` 的 `@_silgen_name` 声明去重：上游同样双模块各一份
  （均 `#if simulator` 守卫，真机构建不编译、CI 无法暴露），单模块合并保留
  Transition.swift 逐字件、删 TGLensSupport 转写件的重复声明。
- **[CI 二轮 2026-09-30 修正两项]** ⑧补齐 DisplayUIKitUtils 三件按需摘录（编译器
  暴露的漏搬符号，均已进 TGLensSupport.swift 并注明上游行号）：`UIColor.mixedWith`
  （:308，逐字语义转写）/ `CALayer.layerTintColor`（:921，KVC contentsMultiplyColor；
  判型/取值逐字——Swift 6 禁止 Any→CF 条件降转（`is`/`as?` 报 "will always succeed"
  错误，CI 三轮实报），须 CFGetTypeID + 强桥接）/ `CALayer.blur`（:891 → UIKitUtils.m:265，
  = gaussianBlur 滤镜，与 luminanceToAlpha 同一 CAFilter 工厂）；⑨`_solveForInput:`
  实参类型判定由 NSMethodSignature（Swift 显式不可用：NSInvocation 家族被 SDK 屏蔽）
  改为 objc/runtime `method_getArgumentType`（读 index 2 类型字符，语义等价；该 API
  返回 void——越界时 dst 填空串，与 'f'/'d' 不匹配自然落 (nil, nil)）。
- **[装机回归 2026-09-30 修正]** ⑩`isSupported` 探针三重 bug（pp 装机实锤「透镜
  没出现、跟 TG 不一样」）：①幽灵选择器 `setRestingBackgroundColor:`（TG 全源码
  无此调用，凭空写进探针）；②把 TG 自带 `method(for:)` 守卫的可选项
  （setLiftedContentMode:/setStyle:/setWarpsContentBelow:/setLifted:animated:…）
  当硬要求；③`alloc` 用 class_respondsToSelector 判（查实例方法，类方法恒 false）
  ——三者叠加 = 探针恒失败、透镜岛永不渲染、整栏永远静默回退旧胶囊（表象 = "什么
  也没搬"）。修复 = 探针只保留 4 个「无守卫直调」选择器（TGLensHost.swift 行内注释
  列明纪律与出处行号）。
- **[装机回归·尺寸 2026-09-30]** ⑪槽位几何 3 格 → 4 格（TG 4 tab 布局对齐）：
  TG 栏是 4 tab 布局，本方按 3 格平分导致每格（含透镜宽 = 槽宽+8）整体偏大
  （pp 装机：「加一个图标占位保持和tg一致大小」）。修复 = 两处渲染路径分母统一
  `slotCount = 4`：TGLensHost（岛：槽宽=(宽-8)/4，图标占 0-2 格、第 3 格占位）+
  ModeTabBar.legacyItemsCapsule（4 等分 HStack 尾插占位格）；
  按下/提交/钳制仍只在 0-2 实项（`selectableTabs.count` 不动）。
- **[装机回归·第 4 格 2026-09-30]** ⑭第 4 格空占位 → 设置齿轮（pp：「把那个空白
  占位的 tab 加一个图标」）。语义 = TG 第 4 tab（设置）；本仓 = B16 单通道
  `router.showSettings`（≡ 齿轮同款）→ 动作位：点按开设置，透镜永不驻留/提交该格
  （拖过钳回 works）。两条手势同语义：岛 TGLensHost（rawSlotIndex 守卫：
  .began 按下态 / .changed 移回即撤销 / .ended 落点仍在第 4 格才开设置）+
  legacy selectionGesture（同守卫的 SwiftUI 化，gearDragActive 手势域标志）。
  资产 aa-Tabler-Settings、文案 "Settings"（zh-Hans=设置）与 ≡ 齿轮同源；
  岛侧双副本（常态/透镜下）防拖过镂空，legacy 单副本（透镜拖过期间着色差异不入
  近似）。
- **[装机回归·尺寸对账 2026-09-30]** ⑫与 TG 源码 + pp 实机像素反演逐项对账，四笔
  联动修正：①栏高 68→64（TabBarComponent.swift:664 = 56+4×2，实机圆钮 192px=64.0
  双证）；②左右边距 12→20（TabBarContollerNode.swift:213-215「底距≤28 档」，实机
  反演四列中心距 68.0 落此档）→ 格宽 72.25→68.25（= TG 实测 68）；③底距 offset
  12→14（实机圆钮下缘 ≈19.7pt）；④legacy 选中透镜视觉改为「item 槽位本身」（TG
  私有件渲染内收 4——26 路径 :464/:376、legacy blob 分支 :471 同义；视觉=item
  矩形：宽=槽宽、距胶囊边 4pt）——修 pp 装机报「首格灰体触边」。对账全表见
  docs/specs/tg-tabbar-retrofit.md §7。
- **[装机回归·落位 2026-09-30]** ⑬松手落点/动画对齐 TG 单跳语义（pp 报「滑动 tab
  落点和动画有问题」）：①岛 `.ended` 旧实现先推**旧**选中槽、再由 SwiftUI 回推提交
  槽——两段弹簧竞速，第二推在 LiquidLensView.updateLens else 分支的
  `removeAllAnimations()`（TG 原版 workaround，本桥不带 userData）处把透镜瞬打回
  旧槽模型位再重滑；修复 = 同步预置 `selectionIndex` 使本推直达提交槽（对齐 TG
  :555-604：先清手势态、再以提交 item 为目标单次 spring），紧随 apply 同值短路；
  ②三树 ZStack 瞬切 × 每树一栏：跨树提交换栏后目标树的岛从旧槽整段重滑（非从
  松手位落位）——加跨树**提交交接**（`TGLensHost.CommitHandoff`：出发岛 .ended 寄存
  透镜可见位（presentation 优先，LiquidLensView 适配 ④），目标树岛在紧随 apply()
  消费：先瞬时以**按压态**（拉缩/光晕/放大图标，与出发栏松手瞬间同像素）落到交接位、
  再走松手序列（setLifted(false) 收束 + 位置弹簧）——旧版只交接位置、换栏即熄发亮
  的问题同批消（pp 二轮「切 tab 弹簧/发亮都很快」）；消费门 = 目标树
  ownSlot==新选中位 + 来自别岛 fromSlot≠ownSlot + 槽位吻合 + ≤0.5s + 无在途手势）；
  ③同期对齐 TG :550：拖动
  （changed）中图标 1.15 放大改即时（began/:540、ended/:604 仍 spring）——旧实现
  恒 0.4s 弹簧致拖过槽位放大滞后。

## 3. ⚠️ 私有 API 清单（与 TG 同款用法）

- `_UILiquidLensView`（iOS 26，运行时 NSClassFromString + 选择器反射）
- `CASpringAnimation._solveForInput:`（动态取实现直调）
- `CAFilter`（filterWithName: 反射）
- `CALayer.add(_:forKey:)` **全局 swizzle**（仅覆盖栈非空时改变行为；TG 原样）
- 单色化私有字段（`_setAllows/Enable/MonochromaticTreatment:`，字符串分段拼接）
- `highFrameRateReason` KVC（1048619）

风险与 TG App Store 版同款：iOS 大版本可能改私有实现。**回退设计**：透镜岛
`TGLensBar.isSupported` = 私有类存在 **且** 4 个「TG 原件无守卫直调」的选择器
探针通过（initWithRestingBackground: / setLiftedContainerView: /
setLiftedContentView: / setOverridePunchoutView:；任一缺失即整栏回退
ModeTabBar.legacyItemsCapsule，杜绝 unrecognized-selector 崩溃）。⚠️ 探针清单
纪律（2026-09-30 装机判例，见 §2 ⑩）：只收无守卫直调的选择器——幽灵选择器、
TG 自身 method(for:) 守卫的可选项（setLiftedContentMode:/setStyle:/
setWarpsContentBelow:/setLifted:animated:…）、类方法（alloc 不能用实例侧 API 判），
放进探针即"永远回退、看起来什么也没搬"。残余风险（与 TG 同款、探针无法覆盖）：
类与选择器都在但**行为**被改（如 setLifted 语义变化）——只能靠装机回归发现。

## 4. 验收项（装机）

1. 透镜在选中项下呈**系统液态玻璃**（非旧版平铺灰块）；拖动时透镜跟指尖、抬起有
   弹跳（SharedDisplayLinkDriver 驱动）。
2. 按住 tab / 圆钮：拉缩（TouchEffect 方向拉伸）+ 发光（径向高亮）。
3. 切换 tab：透镜弹簧滑位（spring 0.4，含 SpringParametersOverride→贝塞尔重定时）。
4. 几何：栏高 64、底距 ≈20pt、左右边距 20、格宽 68.25（2026-09-30 对账修正，
   全表见 docs/specs/tg-tabbar-retrofit.md §7）。
5. 深/浅双模式、登录盖/设置 sheet/资料页 zoom 不受影响。
