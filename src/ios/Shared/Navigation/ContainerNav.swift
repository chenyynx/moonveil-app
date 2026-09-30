// ContainerNav.swift — 容器栈的共享路由状态（容器化重构 C3，2026-09-30）
//
// 设计见 docs/specs/tabbar-container-redesign.md（D5/D9）：窄屏深页（聊天）
// 的承载从「local 树内层栈」迁到「外层容器栈」（RootModeTabsView 的
// NavigationStack）——本类是该栈的唯一数据源与程序化入口，逐字迁移自
// ContentView 的窄屏导航通道（navigationPath/pendingChatRoute/
// currentStackSessionId/previousStackSessionId + pushChat/flush/探针）。
//
// 语义（迁移时逐点核对，勿轻改）：
// - path 是**全局单栈**（任何树 push 的深页都落这里）——原实现里
//   currentStackSessionId 只追踪 local 树；全局化是单栈结构的自然语义，
//   行为差异点已在 spec/commit 里列明，装机验证。
// - 系统回写（划回/pop）直接写 path（NavigationStack(path:) 绑定），
//   程序化写入整栈原子替换（NAV-TXN-FIX 2026-09-30 语义保留：根→单页
//   裸写继承按钮事务；栈顶替换 withAnimation(nil)）。
// - 后台门：BACKGROUND 时只记 pendingChatRoute，前台上前台 first-frame
//   flush（[T-ios-bg-nav-push-watchdog] 语义）。

import Foundation
import SwiftUI
import UIKit

@MainActor
final class ContainerNav: ObservableObject {
    static let shared = ContainerNav()
    private init() {}

    /// [R3 审查修订 F5] 日志 category 跟随原文（"Share"/"DraftSession"）——装机
    /// grep 脚本按 category 过滤日志，勿合并成新 category。
    private let navLog = AppLogger(category: "Share")
    private let draftLog = AppLogger(category: "DraftSession")

    /// 唯一路由数据源。外层 NavigationStack(path:) 绑定它；系统回写自动落此。
    @Published var path: [ChatRoute] = []

    /// 后台期间收到的程序化 push 意图（见头注；TTL 由消费时机天然兜住）。
    var pendingChatRoute: ChatRoute?

    /// 当前栈上会话 id（出栈 vm 挂起 + 目的地 APPEAR 锁步用）。
    @Published var currentStackSessionId: String?

    /// 上一次导航变更前的栈上会话 id：`.onChange` 在状态提交后才运行，而所有
    /// 导航助手都在同帧把 currentStackSessionId 写成 INCOMING id——观察者读它
    /// 会挂起错误的 vm。单独一份锁步记录（原 ContentView 注释逐字搬迁：
    /// [T-ios-stacknav-transition-attributegraph-race]）。
    var previousStackSessionId: String?

    /// 搜索上下文镜像（destination 闭包在容器层，需要 ContentView 的搜索态；
    /// ContentView 单向写，容器只读——见 noteSearchContext）。
    var searchActive: Bool = false
    var searchAnchors: [String: String] = [:]

    /// destination 用：从搜索进入时给聊天页的锚点消息 id（非搜索态恒 nil）。
    func searchAnchor(for id: String) -> String? {
        searchActive ? searchAnchors[id] : nil
    }

    /// ContentView 搜索逻辑单向同步（唯一写入口）。
    func noteSearchContext(active: Bool, anchors: [String: String]) {
        searchActive = active
        searchAnchors = anchors
    }

    // MARK: - 程序化入口（逐字迁自 ContentView.pushChat，:3861-3885）

    /// 后台门（[T-ios-bg-nav-push-watchdog] + [T-share-first-tap-no-response]
    /// 同款）：真正 BACKGROUNDED 时只记意图不 push，前台第一帧
    /// `flushPending()` 落地；`.inactive` 不拦（openURL 恰在该态送达）。
    ///
    /// 动画纪律（原 `commitNavigationPath` 逐字平移）：只有「根→单页 push」
    /// 带动画；栈顶替换走禁动画原子提交（moveto-transfer-race 防护）。
    func pushChat(_ route: ChatRoute) {
        // [C3.2→L3 崩溃修复 2026-09-30] 见 RootTabRouter.route(to:) 的 [C3.2] 注释：
        // 与「程序化切 tab（树切换）」同帧写 path 会触发 iOS 26 导航状态机断言
        // （EXC_BREAKPOINT in NavigationColumnState.boundPathChange；build 436/438
        // 两次 .ips 实锤；装机对照：本地列表点＋不崩、跨树点＋崩）。
        // ⚠️ [L3 修订] 438 装机实锤「延后一拍不够」：SwiftUI 在帧末
        // （NSRunLoop.flushObservers → Update.end）才把一批变更统一结算，一跳
        // 异步仍会赶进同一结算窗。**439 判例返修 2026-09-30 晚**：固定 0.25s 是
        // 按轻型转场标定的，works 挂载后的重转场下不够（.ips 与 436/438 同帧栈）。
        // 现改动态落点「窗剩余 + 0.25s 尾巴」——写成窗关闭之后，而不是赌固定时长
        // （机理与不变量见 RootTabRouter.consumeTreeSwipePendingDelay）。
        // 本网为**残余路径的公共兜底**：深链/通知/分享等「切树后随即 push」站点，
        // 以及同树迟到场景（tab 已落本机后再点＋：tab 点击自设窗、＋ 不再 route）
        // ——延迟只落在这类调用上。跨树热路径（＋）已改「归位先行」显式 route + 本网
        // 拆帧（见下）。
        // ⚠️ [收口包 2026-09-30 晚] ＋ 热路径改「归位先行」后，本网同时成为该热
        // 路径的**唯一拆帧机制**（route(.local) 先写 → push 随即撞窗被本网拆帧；
        // 动机与判据见 ContentView.handleNewChatRequest 的 [收口包·保险牌] 注释）。
        if let delay = RootTabRouter.shared.consumeTreeSwipePendingDelay() {
            // [审修 2026-09-30 晚 · N1] 拆帧会把下面 OPEN 打点推到落点（按压瞬间锚点
            // 见 QuickActionRouter 的 PUSHTRACE press；装机读时间线时须知本行）。
            // 字段与落点行同构（grep "OPEN route=" 两处锚点齐全）。
            NavTrace.log("OPEN route=\(route.logTag) deferred=\(String(format: "%.2f", delay))s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.pushChat(route) }
            }
            return
        }
        NavTrace.log("OPEN route=\(route.logTag) trig=\(NavTrace.trigger)+\(NavTrace.age)")
        if UIApplication.shared.applicationState == .background {
            pendingChatRoute = route
            navLog.info("🔄SESSION deferring push — app backgrounded (route=\(route.logTag))")
            return
        }
        draftLog.info("🔑DRAFT pushChat route=\(route.logTag)")
        currentStackSessionId = route.sessionId
        // [NAV-TXN-FIX 2026-09-30] 不用裸 Transaction() 包 path 写：Build 417
        // 真机实锤程序化写 path 后划回写回永久死亡，而声明式 NavigationLink
        // 的 push/pop 写回全正常。裸 Transaction 缺少 SwiftUI 内部导航
        // transaction 的载荷，桥的划回账本建不起来。根→单页用裸写（继承按
        // 钮自带的动画 transaction）；栈顶替换用 withAnimation(nil)（正经
        // transaction，仅动画为 nil）。
        if path.isEmpty {
            path = [route]
        } else {
            withAnimation(nil) {
                path = [route]
            }
        }
    }

    /// [去嵌套 2026-09-30] 程序化出栈（远端设备删除后退出详情页等）。裸写删除尾项
    /// ——NAV-TXN-FIX 验证过的安全形状（与 pushChat 的根→单页裸写同族）；系统回写
    /// （划回）与程序化路径共用同一 path 绑定，currentStackSessionId 锁步由既有观察者
    /// 按系统 pop 同路处理（ContentView 的 PATH 观察链）。
    /// [R2 审查观察项 2026-09-30] 退场转场形态装机盯：裸写预期继承调用事务（默认滑动
    /// 退场）；若实测为「闪回」，改 withAnimation(nil)（对齐 pushChat 栈顶替换纪律）
    /// 或补显式动画。
    func pop() {
        guard !path.isEmpty else { return }
        // [R4 审查修订 2026-09-30] 与 pushChat 同款兜底网：树切换转场内写 path 会触发
        // NavigationColumnState 断言（436/438 实锤，机理见 pushChat 注释）——pop 同属
        // path 写，同窗内同样延后拆帧（439 返修后为动态落点，见 pushChat 同段注释）。
        // 三个调用点（设备删除 / 聊天页 onMenu / 返回编辑）全在远端树深页。
        if let delay = RootTabRouter.shared.consumeTreeSwipePendingDelay() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.pop() }
            }
            return
        }
        path.removeLast()
    }

    /// 落地后台挂起的程序化 push 意图（见 pushChat 注释）。时机 = 前台第一帧
    /// （ContentView 的 onAppear / scenePhase==.active 兜底调用）。
    func flushPending() {
        guard let route = pendingChatRoute else { return }
        guard UIApplication.shared.applicationState != .background else { return }
        pendingChatRoute = nil
        navLog.info("🔄SESSION flushing deferred push (route=\(route.logTag))")
        pushChat(route)
    }

    /// [R1 审查修订 F2] 根重建复位（MinisApp `.id(appLanguage)` 语言切换整树重建）：
    /// 旧四态为 @State、随重建清零回列表；单例不随重建——必须显式复位，否则
    /// path 上的草稿 id 会在重建后开一个空白聊天（R1 反例）、持久会话莫名停留、
    /// pendingChatRoute 跨重建复活。调用点 = 唯一的语言写点（ContentView 设置页）。
    func resetForRootRebuild() {
        path = []
        pendingChatRoute = nil
        currentStackSessionId = nil
        previousStackSessionId = nil
        searchActive = false
        searchAnchors = [:]
    }

    // MARK: - 探针（逐字迁自 ContentView.pathProbe*；原 $navigationPath binding
    // hack 因改属性直读而退役——class 内无 @State 逃逸限制）

    /// 报告 path 的 count+栈顶，用于钉死「draft pop 后系统回写丢失」的确切机制。
    /// 设备日志中 grep PATH-PROBE 即可全量捞出。
    func pathProbe(_ tag: String) {
        AppLogger(category: "PathProbe").info("[PATH-PROBE] \(tag) count=\(path.count) isEmpty=\(path.isEmpty)")
    }

    /// 延迟 0.3s 再采样一次：抓「onDisappear 时刻 path 还没回写、稍后才回写」
    /// 与「回写彻底没发生」两种形态的差别。
    func pathProbeLater(_ tag: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            AppLogger(category: "PathProbe").info("[PATH-PROBE] \(tag) count=\(self.path.count) isEmpty=\(self.path.isEmpty)")
        }
    }
}
