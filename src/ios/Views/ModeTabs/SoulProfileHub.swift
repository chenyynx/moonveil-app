// SoulProfileHub.swift — 资料页（身份胶囊点开的整页），Muse 参照逐像素实测规格。
// Zoom 转场：壳层/本机页给胶囊头像挂 matchedTransitionSource，本页 sheet 内容挂
// .navigationTransition(.zoom(sourceID:in:)) —— 打开从胶囊头像放大长出、关闭缩回。
//
// [MUSE-SPEC 2026-09-26] 参照 1f6f84af（1179×2556@3x）逐区块实测（pt=px/3）：
//   纯内容页（无导航栏/tab 栏）、systemBackground；
//   X/分享 44pt 圆钮（y 中心~85，leading/trailing ~16）；头像 78pt 白圈底屏中 +
//   右下 32pt 白圆铅笔徽标；名字 20pt semibold 屏中；状态行（26pt 绿闪电徽标 +
//   15pt 文案「已连接」）屏中；四图标工具条：全宽白胶囊 高46 圆角23，四图标
//   均分（步长 ~87.5），选中段=36pt 高 #F3F3F5 胶囊（指纹段默认选中）；
//   区块标题 18pt semibold 左对齐 16；「编辑」全宽灰条 高35 圆角17.5
//   （#F5F5F5）；双卡 各172×150 圆角24 gap16：左上 28pt 白粗标题 +
//   「请谨慎访问」13pt 白70%，左下 MM.dd.yy 日期 13pt 白65%，右下 36pt
//   半透明白心形/气泡；SOUL=暖棕渐变、记忆=紫渐变，两卡都有胶片噪点。

import SwiftUI
import UIKit

struct SoulProfileHub: View {
    /// matchedTransitionSource / zoom sourceID 共用的固定 ID（壳层引用同一常量）。
    static let zoomSourceID = "soulProfileAvatar"

    @Environment(\.dismiss) private var dismiss

    @State private var soulName: String = SoulProfileHub.displayName()
    /// SOUL.md 的 mtime，读不到显示今天（打开时拍一次，soulMdChanged 时重拍）。
    @State private var soulDate: Date = SoulProfileHub.mtime(of: SoulStore.fileURL)
    /// 记忆目录（含子项）最近 mtime，兜底今天。
    @State private var memoryDate: Date = SoulProfileHub.latestMemoryDate()
    /// 四图标工具条选中段（Muse 同构：选中=36pt 高 #F3F3F5 胶囊）。第一期段功能后续批次，
    /// 先做选中态与图标（Muse 四段：会话列表/权限/历史/隐私 → 暂映射 0-3）。
    @State private var toolbarSelection: Int = 3
    /// 双卡 push（用 item 驱动，避免 NavigationStack 内多级 sheet 语义）。
    @State private var showSoulEditor = false
    @State private var showMemoryEditor = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 20)
                    toolbar
                        .padding(.top, 24)
                    sectionTitle
                        .padding(.top, 30)
                    editButton
                        .padding(.top, 30)
                    cards
                        .padding(.top, 22)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }

            topButtons
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            soulName = SoulProfileHub.displayName()
            soulDate = SoulProfileHub.mtime(of: SoulStore.fileURL)
        }
        .sheet(isPresented: $showSoulEditor) {
            NavigationStack { SoulSettingsView() }
        }
        .sheet(isPresented: $showMemoryEditor) {
            NavigationStack { MemoryManagementView() }
        }
    }

    // MARK: - 顶部左右圆钮（X 关闭 / 分享）

    private var topButtons: some View {
        HStack {
            circleButton(system: "xmark", action: { dismiss() })
                .accessibilityLabel(Text("Close"))
            Spacer()
            circleButton(system: "square.and.arrow.up", action: {
                let text = "\(soulName) — Moonveil"
                UIPasteboard.general.string = text
            })
                .accessibilityLabel(Text("Share"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Self.chromeSurface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 头像 + 名字 + 状态行

    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image("SoulPlush")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 78, height: 78)
                    .clipShape(Circle())
                    .modifier(PlushIdleMotion())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                // 铅笔徽标：32pt 白圆（点=换形象，走 SoulSettingsView 的 icon 编辑）。
                Button {
                    showSoulEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                        .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: 2)
            }
            .frame(width: 78, height: 78)
            .padding(.top, 12)

            Text(verbatim: soulName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 28)

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Self.statusGreen))
                Text(AppLocalized("Connected"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 四图标工具条（Muse：高46 全宽白胶囊，选中=36pt #F3F3F5 胶囊）

    private let toolbarIcons = ["list.bullet", "checkmark.shield", "clock", "touchid"]

    private var toolbar: some View {
        HStack(spacing: 0) {
            ForEach(toolbarIcons.indices, id: \.self) { idx in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        toolbarSelection = idx
                    }
                } label: {
                    Image(systemName: toolbarIcons[idx])
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(toolbarSelection == idx ? Color.primary : Color.primary.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Group {
                                if toolbarSelection == idx {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Self.toolbarSelected)
                                        .padding(.vertical, 2)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(Self.toolbarTrack)
        )
    }

    // MARK: - 区块标题 + 编辑按钮

    private var sectionTitle: some View {
        Text(verbatim: soulName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editButton: some View {
        Button {
            showSoulEditor = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                Text(AppLocalized("Edit"))
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 35)
            .background(
                RoundedRectangle(cornerRadius: 17.5, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 17.5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双卡（SOUL / 记忆，Muse 实测 172×150 圆角24 gap16，带胶片噪点）

    private var cards: some View {
        HStack(spacing: 16) {
            profileCard(
                title: "SOUL",
                subtitle: AppLocalized("Handle with care"),
                gradient: Self.soulCardGradient,
                symbol: "heart.fill",
                date: soulDate
            ) {
                showSoulEditor = true
            }
            profileCard(
                title: AppLocalized("Memory"),
                subtitle: AppLocalized("Handle with care"),
                gradient: Self.memoryCardGradient,
                symbol: "bubble.fill",
                date: memoryDate
            ) {
                showMemoryEditor = true
            }
        }
    }

    private func profileCard(title: String, subtitle: String,
                             gradient: LinearGradient, symbol: String, date: Date,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                gradient
                // 胶片噪点：中性灰随机颗粒，overlay 混合 10% 透明度。
                Image("NoiseTile")
                    .resizable()
                    .opacity(0.10)
                    .blendMode(.overlay)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Text(Self.cardDateFormatter.string(from: date))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(14)
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(14)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 卡片左下日期：Muse 格式 MM.dd.yy（如 09.24.26）。
    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM.dd.yy"
        return f
    }()

    // MARK: - helpers

    /// 与 RemoteRootView 同源的回退链：SOUL.md name → "Moonveil"。
    static func displayName() -> String {
        let n = SoulStore.cachedMetadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Moonveil" : n
    }

    static func mtime(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date()
    }

    /// 记忆目录 + 一层子项的最近 mtime；全读不到兜底今天。
    static func latestMemoryDate() -> Date {
        let dir = AIChatViewModel.minisMemoryPersistentDir
        var latest = mtime(of: dir)
        let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls ?? [] {
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let m, m > latest { latest = m }
        }
        return latest
    }

    // MARK: - 色板（Muse 采色；全动态双模式）

    private static let chromeSurface = Color(UIColor.secondarySystemBackground)
    /// 工具条轨道：Muse 参照浅色=纯白。
    private static let toolbarTrack = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
            : UIColor(white: 1.0, alpha: 1)
    })
    /// 工具条选中段：Muse 浅色=#F3F3F5（不是纯白）。
    private static let toolbarSelected = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
            : UIColor(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF5 / 255, alpha: 1)
    })
    private static let statusGreen = Color(red: 0.30, green: 0.85, blue: 0.40)
    /// SOUL 卡：暖棕渐变（Muse 采色 (133,111,100)→(124,102,88)→(114,86,72)）。
    private static let soulCardGradient = LinearGradient(
        colors: [Color(red: 0.52, green: 0.44, blue: 0.39),
                 Color(red: 0.49, green: 0.40, blue: 0.35),
                 Color(red: 0.45, green: 0.34, blue: 0.28)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// 记忆卡：紫渐变（Muse 采色 (97,32,134)→(79,16,120)→(60,26,86)）。
    private static let memoryCardGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.13, blue: 0.53),
                 Color(red: 0.31, green: 0.06, blue: 0.47),
                 Color(red: 0.24, green: 0.10, blue: 0.34)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
