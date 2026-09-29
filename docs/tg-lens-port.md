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
  取不到时优雅空转）。其余逐字。
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
  线程触达；TG 原件为 ObjC 无隔离假设）；②交互按 TG 原样放回岛内——岛保持可交互
  （玻璃 `UIGlassEffect.isInteractive` 的触摸响应需要真实命中），岛内挂 0 延迟
  UILongPressGestureRecognizer（cancelsTouchesInView=false，与玻璃响应并行），
  提交经 onCommit 回调；③透镜跟手 = TG 精确模型（起点 = 被按槽位透镜 minX，其后
  按指尖位移增量，保留抓取偏移）；④`generateImage` 手动翻回 y-up 上下文（对齐 TG
  的 `withContext` 朝向；仅 <26 遗留路径可达）。

## 3. ⚠️ 私有 API 清单（与 TG 同款用法）

- `_UILiquidLensView`（iOS 26，运行时 NSClassFromString + 选择器反射）
- `CASpringAnimation._solveForInput:`（动态取实现直调）
- `CAFilter`（filterWithName: 反射）
- `CALayer.add(_:forKey:)` **全局 swizzle**（仅覆盖栈非空时改变行为；TG 原样）
- 单色化私有字段（`_setAllows/Enable/MonochromaticTreatment:`，字符串分段拼接）
- `highFrameRateReason` KVC（1048619）

风险与 TG App Store 版同款：iOS 大版本可能改私有实现。**回退设计**：透镜岛
`TGLensBar.isSupported` = 私有类存在 **且** TG 运行路径用到的全部选择器探针通过
（类级 2 个 + 实例级 8 个；任一缺失即整栏回退 ModeTabBar.legacyItemsCapsule，
杜绝 unrecognized-selector 崩溃）。残余风险（与 TG 同款、探针无法覆盖）：类与
选择器都在但**行为**被改（如 setLifted 语义变化）——只能靠装机回归发现。

## 4. 验收项（装机）

1. 透镜在选中项下呈**系统液态玻璃**（非旧版平铺灰块）；拖动时透镜跟指尖、抬起有
   弹跳（SharedDisplayLinkDriver 驱动）。
2. 按住 tab / 圆钮：拉缩（TouchEffect 方向拉伸）+ 发光（径向高亮）。
3. 切换 tab：透镜弹簧滑位（spring 0.4，含 SpringParametersOverride→贝塞尔重定时）。
4. 几何：栏高 68、底距 ≈23pt（下移 12pt 后）。
5. 深/浅双模式、登录盖/设置 sheet/资料页 zoom 不受影响。
