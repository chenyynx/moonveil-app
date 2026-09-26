// SoulProfileHub.swift — 资料页（身份胶囊点开的整页），Muse 参照逐像素实测规格。
// Zoom 转场：壳层/本机页给胶囊头像挂 matchedTransitionSource，本页 sheet 内容挂
// .navigationTransition(.zoom(sourceID:in:)) —— 打开从胶囊头像放大长出、关闭缩回。
//
// [MUSE-SPEC 2026-09-26] 参照 photo_5C8CA174（1179×2556@3x）逐区块实测（pt=px/3）：
//   纯内容页（无导航栏/tab 栏）、systemBackground；
//   X/分享 44pt 圆钮（y~85，leading/trailing ~16）；头像 ~64pt 屏中（白圈底）+
//   右下 24pt 白圆铅笔徽标；名字 26pt semibold 屏中；状态行（绿点+文案）15pt 屏中；
//   四图标工具条：全宽胶囊 高66 圆角33，四图标均分（步长 87.5），选中段=白色全高
//   胶囊；区块标题 24pt bold 左对齐 16；「✏️ 编辑」全宽灰条 高35 圆角17.5；
//   双卡 各173×91 圆角24 gap15：左上 28pt 白粗标题 +「请谨慎访问」13pt 白70%，
//   右下 28pt 半透明 ❤/💬；SOUL=暖棕渐变、记忆=深蓝渐变。

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
    /// 四图标工具条选中段（Muse 同构：选中=白色全高胶囊）。第一期段功能后续批次，
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
                        .padding(.top, 8)
                    toolbar
                        .padding(.top, 24)
                    sectionTitle
                        .padding(.top, 30)
                    editButton
                        .padding(.top, 18)
                    cards
                        .padding(.top, 16)
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
                Image("CaduGhost")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                // 铅笔徽标：24pt 白圆（点=换形象，走 SoulSettingsView 的 icon 编辑）。
                Button {
                    showSoulEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                        .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: 2)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 12)

            Text(verbatim: soulName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 26)

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Self.statusGreen))
                Text("Connected")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 四图标工具条（Muse：高66 全宽胶囊，选中=白色全高胶囊）

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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(toolbarSelection == idx ? Color.primary : Color.primary.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Group {
                                if toolbarSelection == idx {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
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
            RoundedRectangle(cornerRadius: 33, style: .continuous)
                .fill(Self.toolbarTrack)
        )
    }

    // MARK: - 区块标题 + 编辑按钮

    private var sectionTitle: some View {
        Text(verbatim: soulName)
            .font(.system(size: 24, weight: .bold))
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
                Text("Edit")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 17.5, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 17.5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双卡（SOUL / 记忆，Muse 实测 173×91 圆角24 gap15）

    private var cards: some View {
        HStack(spacing: 15) {
            profileCard(
                title: "SOUL",
                subtitle: "Handle with care",
                gradient: Self.soulCardGradient,
                symbol: "heart.fill"
            ) {
                showSoulEditor = true
            }
            profileCard(
                title: String(localized: "Memory"),
                subtitle: "Handle with care",
                gradient: Self.memoryCardGradient,
                symbol: "bubble.fill"
            ) {
                showMemoryEditor = true
            }
        }
    }

    private func profileCard(title: String, subtitle: String,
                             gradient: LinearGradient, symbol: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: gradient.colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                }
                .padding(14)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(14)
            }
            .frame(height: 91 * 2)   // Muse 参照含噪点质感与更多留白；2x 卡高 ~182 贴近其视觉体量
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

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
    private static let toolbarTrack = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
            : UIColor(white: 0.958, alpha: 1)
    })
    private static let statusGreen = Color(red: 0.30, green: 0.85, blue: 0.40)
    /// SOUL 卡：暖棕噪点感渐变（Muse 采色 (135,114,98) 系）。
    private static let soulCardGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.47, blue: 0.38),
                 Color(red: 0.42, green: 0.35, blue: 0.28),
                 Color(red: 0.48, green: 0.42, blue: 0.33)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// 记忆卡：深蓝渐变（Muse 采色 (84,141,169) 系，压深保白字对比）。
    private static let memoryCardGradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.35, blue: 0.47),
                 Color(red: 0.10, green: 0.24, blue: 0.36),
                 Color(red: 0.20, green: 0.42, blue: 0.52)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
