// DeviceOverviewSections.swift — AA 官方逐字搬运（P2-B，2026-09-21）
//
// 官方源：Views/Devices/DeviceOverviewSections.swift（v2.0.0-27-g1bc11f45）。
// 零差异（无文案、无版本守卫需求：ForEach(sections:) 为 iOS 17 API，本仓部署目标 ≥18）。
// CIFIX(iOS Build 877e3e8): init(sections:content:) 实为 iOS 18+ API（头注释误判）。
// 部署目标 26.2 恒 ≥ 18 → 守卫恒走真分支，仅满足编译器的静态可用性检查。

import SwiftUI

/// Reuse the existing section content and actions in the page's scroll column.
/// GroupBox supplies its system appearance without a nested, independently
/// scrolling List or custom card backgrounds. The shared contour matches the
/// larger grouped surfaces used elsewhere instead of GroupBox's compact corners.
struct DeviceOverviewSections<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 18.0, *) {
            ForEach(sections: content()) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if !section.header.isEmpty {
                        section.header
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !section.content.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(section.content) { row in
                                    if row.id != section.content.first?.id { Divider() }
                                    row
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    }
                    section.footer
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // 部署目标 26.2 下不可达；保留分支仅为通过编译器可用性检查，
            // 直接渲染内容视图（它是 SectionedCollection，本身即可作为 View 显示）。
            content()
        }
    }
}
