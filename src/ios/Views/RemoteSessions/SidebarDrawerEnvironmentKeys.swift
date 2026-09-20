// SidebarDrawerEnvironmentKeys.swift — 官方 Views/Components/SidebarDrawer.swift 中
// 两个「详情页消费侧」环境键的本仓声明（键名/类型/默认值逐字，声明位置按铁律④
// 由 @Entry 改为传统 EnvironmentKey）。
//
// 为什么只声明键、不搬抽屉：本仓远端线导航为 NavigationStack + RemoteSessionListView，
// 无官方抽屉壳（SidebarDrawer 724 行 / NavigationSplitView 体系 → 差集表 A-2 记「不适用」）。
// 官方搬运件（ChatTimelineView / SessionChatView）里 `navigationIsSuspended` 一类判定
// 读的就是这两个键，用于「抽屉动画期间挂起滚动编排、不打断读者」——本仓无抽屉，
// 键恒为 false，官方那套分支保持逐字存在且自然短路（不是裁剪）。
// 若日后引入抽屉壳，在壳上 `.environment(\.sidebarDrawerIsTransitioning:)` 即可激活原逻辑。

import SwiftUI

private struct SidebarDrawerTransitionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SidebarDrawerObscuresDetailKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarDrawerObscuresDetail: Bool {
        get { self[SidebarDrawerObscuresDetailKey.self] }
        set { self[SidebarDrawerObscuresDetailKey.self] = newValue }
    }
    var sidebarDrawerIsTransitioning: Bool {
        get { self[SidebarDrawerTransitionKey.self] }
        set { self[SidebarDrawerTransitionKey.self] = newValue }
    }
}
