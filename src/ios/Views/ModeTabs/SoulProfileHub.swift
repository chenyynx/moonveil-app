// SoulProfileHub.swift — Q2 资料页（身份胶囊点开的整页）。
// Zoom 转场：壳层（RootModeTabsView）给胶囊头像挂 matchedTransitionSource，
// sheet 内容挂 .navigationTransition(.zoom(sourceID:in:)) —— 打开从胶囊头像放大
// 长出、关闭缩回，严禁默认底部上弹。ID 常量挂在本类型上，壳层引同一个即可。
// 呈现选型：sheet（Apple 文档即以 .sheet + matchedTransitionSource 为 zoom 的
// 标准配对；fullScreenCover 也支持但会吃掉下滑关闭语义，本页有 X 钮，sheet 更贴）。

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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color(UIColor.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        editLink
                        cards
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 52)   // 给左上 X 让位
                    .padding(.bottom, 24)
                }

                closeButton
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            // 与 RemoteRootView 同源：SOUL.md 变了立刻刷名字与卡片日期。
            soulName = SoulProfileHub.displayName()
            soulDate = SoulProfileHub.mtime(of: SoulStore.fileURL)
        }
    }

    // MARK: - 头部（头像 + 名字 + 铅笔徽标）

    private var header: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image("CaduGhost")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                    .accessibilityHidden(true)
            }
            Text(verbatim: soulName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .padding(.top, 12)
        .accessibilityLabel(Text("Close"))
    }

    // MARK: - 「✏️ 编辑」全宽浅灰按钮 → SoulSettingsView

    private var editLink: some View {
        NavigationLink {
            SoulSettingsView()
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: "✏️")
                Text("Edit")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双卡 grid（SOUL / 记忆）

    private var cards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            NavigationLink {
                SoulSettingsView()
            } label: {
                card(title: "SOUL",
                     gradient: [Color(hex: 0xA89484), Color(hex: 0x7E6E60)],
                     date: soulDate,
                     cornerSymbol: AnyView(Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .semibold))))
            }
            .buttonStyle(.plain)

            NavigationLink {
                MemoryManagementView()
            } label: {
                card(title: String(localized: "Memory"),
                     gradient: [Color(hex: 0x6B3FA0), Color(hex: 0xB44FD0)],
                     date: memoryDate,
                     cornerSymbol: AnyView(Image("aa-MessagesSquare")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)))
            }
            .buttonStyle(.plain)
        }
    }

    private func card(title: String, gradient: [Color], date: Date, cornerSymbol: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text("Handle with care")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.82))
            Text(Self.cardDateFormatter.string(from: date))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 26)
            HStack {
                Spacer()
                cornerSymbol
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 148)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 日期 / 名字 helpers

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

    /// MM.dd.yy（资料卡右上角日期，与 Muse 参照一致）。
    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM.dd.yy"
        return f
    }()
}

// MARK: - Color(hex:) — 卡片渐变的定值色书写糖（渐变本身双模式通用）。

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
