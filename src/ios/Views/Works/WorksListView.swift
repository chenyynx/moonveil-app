// WorksListView.swift — Q2 第三 tab「构件 | 影音内容」.
// 顶部大分段胶囊（构件 / 影音内容）；构件 = AI 生成产物文件列表；影音内容 =
// 三列九宫格缩略图，点开走仓库现成的 MessageImageGallery 全屏浏览。
// 顶栏不放标题（身份胶囊在壳层，页切/顶栏归并行任务管）。
//
// 数据源说明（偏离「优先复用 FileMentionIndex」的定案记录）：FileMentionIndex 的
// workspace 根需要当前 sessionId（session-scoped 扫描 + 预算 + @ mention 语义），
// 本页面是跨 session 全局列表，没有 session 上下文 → 按任务书退化为自扫：
// 持久层根目录（Library/MinisChat/minis/<sid>/workspace + App Group shared），
// 路径 API 与 FileMentionIndex 用的是同一批 nonisolated static。

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Models

private struct WorkFile: Identifiable {
    let url: URL
    let name: String
    let ext: String
    let modified: Date
    var id: String { url.path }
}

private struct MediaItem: Identifiable {
    let url: URL
    let isVideo: Bool
    let modified: Date
    var id: String { url.path }
}

private enum WorksSection: Hashable {
    case components
    case media
}

// MARK: - View

struct WorksListView: View {
    /// zoom 转场 namespace（壳层注入；nil 时胶囊不挂转场源，sheet 降级普通）。
    var soulProfileNS: Namespace.ID? = nil
    @State private var section: WorksSection = .components
    @State private var files: [WorkFile] = []
    @State private var media: [MediaItem] = []
    /// 重扫令牌：切走再切回时旧扫描结果作废，不盖新结果。
    @State private var scanToken = UUID()
    /// 复用 MessageImageGallery 的呈现载荷（同文件已定义，memberwise init 可用）。
    @State private var gallery: GalleryPresentation?
    /// 右上角 🔍（pp 2026-09-26「搜索放右上角」）：sheet 出搜索占位页。
    @State private var showsSearch = false
    /// 身份胶囊 → 资料页。
    @State private var showsSoulProfile = false
    @State private var soulName: String = SoulStore.cachedMetadata.name.isEmpty
        ? "Kite" : SoulStore.cachedMetadata.name

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                segmentBar
                    .padding(.horizontal, 16)
                    // [CAPSULE-PRINCIPAL] 跟本机列表同值：导航栏超高胶囊
                    // （~71.5pt）撑高原生 bar，内容顶部补 34pt 让分段 tab
                    // 躲开胶囊（pp 2026-09-27「tab 往下移一点」，后又要求再下移）。
                    .padding(.top, 34)
                content
            }
            // [切页转场 v3 2026-09-30 · cc] 缩放已从本行（v2 位：栈内、但仍在
            // safeAreaInset 求值链上）下沉到 VStack 内的内容分支本体（content 的
            // 四个叶子，见下半）。v2 残留在本行仍打坏安全区记账：装机日志
            // （build 431）实锤离场树底安全区窗口收尾塌到 0.0、进场树保持 0 直到
            // 切页后 ~214ms 才弹回 98 = 用户可见「画面高度在掉」。求值链必须零
            // 动画变换，勿挂回本层。详见 RootModeTabsView 末尾 TreeSwitchZoom
            // 「挂点纪律」。
            // [TG-TABBAR 2026-09-30] 自绘栏挂栈内 root 页底边（push 整页覆盖含栏）。
            .safeAreaInset(edge: .bottom, spacing: 0) { ModeTabBar(tabMode: .works) }
            // [TG-TABBAR-FIX 2026-09-30] 键盘豁免·权威挂点（原理与勿动理由见
            // ContentView.stackLayout 同款注释）：豁免须包在 inset 外侧。
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // 原生标题留空：导航栏 principal 位放身份胶囊（跟本机页同位置）。
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SoulProfileCapsule(
                        soulName: soulName,
                        namespace: soulProfileNS,
                        onOpen: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showsSoulProfile = true
                        }
                    )
                }
                // [SEARCH-TOPRIGHT] pp 2026-09-26「搜索放右上角」。
                ToolbarItem(placement: .topBarTrailing) {
                    SearchToolbarButton(showsSearch: $showsSearch)
                }
            }
            // [MUSE-GLASS-BG 2026-09-27] 跟本机页同理：导航栏底用简单半透明
            // tint 替代系统 blur，胶囊玻璃可折射内容，深浅色自适应。
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.45), for: .navigationBar)
            // [TG-TABBAR 2026-09-30] 底栏 = 自绘 ModeTabBar（本页 root 页
            // safeAreaInset，见上）；系统栏时代的 BottomDock/TAB-RESTORE 沿革
            // 一并退役（系统栏已不存在）。
            .sheet(isPresented: $showsSearch) { SearchPlaceholderView() }
            .fullScreenCover(isPresented: $showsSoulProfile) { soulProfileSheet() }
        }
        .task { rescan() }
        // [PP-2026-09-27] 切分段也重扫：.task 只在 view appear 跑一次，
        // 构件↔影音内容是同 view 的 @State 切换，不触发重扫。
        .onChange(of: section) { _, _ in rescan() }
        .fullScreenCover(item: $gallery) { presentation in
            MessageImageGallery(items: presentation.items, startIndex: presentation.startIndex)
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Kite" : n
        }
    }

    /// 胶囊 → 资料页 sheet（跟 ContentView 同逻辑：有 namespace 走 zoom 转场）。
    @ViewBuilder
    private func soulProfileSheet() -> some View {
        if let ns = soulProfileNS {
            SoulProfileHub()
                .navigationTransition(.zoom(sourceID: SoulProfileHub.zoomSourceID, in: ns))
        } else {
            SoulProfileHub()
        }
    }

    // MARK: 分段控件（[NATIVE-TABS] 原生 segmented Picker，替代自绘胶囊）

    private var segmentBar: some View {
        Picker("", selection: $section) {
            Text("Components").tag(WorksSection.components)
            Text("Media").tag(WorksSection.media)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    // MARK: 内容两段

    // [切页转场 v3 2026-09-30 · cc] 缩放挂点：四个分支叶子本体（v3 最内层）。
    // 纪律 = 缩放必须落在下方 safeAreaInset（body）求值链的最里侧，链上零变换；
    // v2 挂在 VStack 外层（body 原位）仍带动画变换 → 装机实锤离场树底安全区
    // 98→0.0 塌陷、进场树 ~214ms 迟恢复 98（build 431 日志）。分段条
    // segmentBar 不再随缩放（3pt 级，差异 <0.5px，TG 栏本就不缩）。
    @ViewBuilder
    private var content: some View {
        switch section {
        case .components:
            if files.isEmpty {
                emptyView("No components yet")
                    .treeSwitchZoom(.works)
            } else {
                List {
                    ForEach(files) { file in
                        componentRow(file)
                    }
                }
                .listStyle(.plain)
                .treeSwitchZoom(.works)
            }
        case .media:
            if media.isEmpty {
                emptyView("No media yet")
                    .treeSwitchZoom(.works)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(Array(media.enumerated()), id: \.element.id) { idx, item in
                            MediaTile(item: item) {
                                gallery = GalleryPresentation(
                                    items: galleryItems(),
                                    startIndex: idx
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .treeSwitchZoom(.works)
            }
        }
    }

    private func emptyView(_ key: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func componentRow(_ file: WorkFile) -> some View {
        HStack(spacing: 12) {
            AppSymbol(AppFileSymbol.name(for: file.name), size: 22)
                .foregroundStyle(Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(verbatim: file.ext.uppercased())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(file.modified, style: .date)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: 全屏预览（复用 MessageImageGallery）

    private func galleryItems() -> [GalleryItem] {
        media.map { item in
            GalleryItem(
                id: item.url.path,
                title: item.url.lastPathComponent,
                load: { await WorksListView.fullImage(for: item) }
            )
        }
    }

    private static nonisolated func fullImage(for item: MediaItem) async -> UIImage? {
        if item.isVideo {
            return await thumbnail(forVideoAt: item.url, maxPixelSize: 2048)
        }
        guard let data = try? Data(contentsOf: item.url) else { return nil }
        return downsampleImage(data: data, maxPixelSize: 2048)
    }

    // MARK: 扫描

    private func rescan() {
        let token = UUID()
        scanToken = token
        DispatchQueue.global(qos: .userInitiated).async {
            let files = WorksListView.scanComponents()
            let media = WorksListView.scanMedia()
            DispatchQueue.main.async {
                guard token == scanToken else { return }
                self.files = files
                self.media = media
            }
        }
    }

    /// 构件 = AI 产出文档类型；命中即列。
    private static let componentExts: Set<String> = [
        "html", "md", "txt", "json", "swift", "py",
        "js", "ts", "css", "sh", "yml", "yaml", "csv", "log",
    ]
    private static let mediaImageExts: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "webp", "bmp",
    ]
    private static let mediaVideoExts: Set<String> = ["mp4", "mov", "m4v"]
    private static let componentLimit = 100

    /// 工作区 = 各 session 的持久 workspace 目录 + shared（/var/minis 下
    /// workspace/shared 的宿主持久层，见 FileMentionIndex 头注释的同步语义）。
    fileprivate nonisolated static func scanComponents() -> [WorkFile] {
        var roots: [URL] = [AIChatViewModel.minisSharedPersistentDir]
        let fm = FileManager.default
        let base = AIChatViewModel.minisPersistentBase
        if let sids = try? fm.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for sid in sids {
                let ws = sid.appendingPathComponent("workspace", isDirectory: true)
                if fm.fileExists(atPath: ws.path) { roots.append(ws) }
            }
        }

        var results: [WorkFile] = []
        for root in roots {
            guard let walker = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name.hasPrefix(".") || name == "node_modules" { continue }
                let ext = url.pathExtension.lowercased()
                guard componentExts.contains(ext),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                results.append(WorkFile(url: url, name: name, ext: ext, modified: modified))
            }
        }
        results.sort { $0.modified > $1.modified }
        return Array(results.prefix(componentLimit))
    }

    /// 影音源两处：/var/minis/attachments/uploads 的宿主换算目录（resolveHostPath
    /// 同款拼接：rootfs data + dropFirst('/')）+ Caches/InputAttachments。
    /// [PP-2026-09-27] 改递归：照片可能存在子目录里，顶层 contentsOfDirectory 会漏。
    fileprivate nonisolated static func scanMedia() -> [MediaItem] {
        let dirs = [
            RootfsManager.shared.dataPath
                .appendingPathComponent("var/minis/attachments/uploads", isDirectory: true),
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("InputAttachments", isDirectory: true),
        ]
        let fm = FileManager.default
        var results: [MediaItem] = []
        for dir in dirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                let isVideo = mediaVideoExts.contains(ext)
                guard isVideo || mediaImageExts.contains(ext),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                results.append(MediaItem(url: url, isVideo: isVideo, modified: modified))
            }
        }
        results.sort { $0.modified > $1.modified }
        return results
    }

    // MARK: 视频抽帧（缩略图与全屏共用）

    nonisolated static func thumbnail(forVideoAt url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cg = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 九宫格瓦片

private struct MediaTile: View {
    let item: MediaItem
    let onTap: () -> Void

    @State private var thumb: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(UIColor.secondarySystemBackground)
                    ProgressView()
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(Text(verbatim: item.url.lastPathComponent))
        }
        .buttonStyle(.plain)
        .task { await loadThumb() }
    }

    private func loadThumb() async {
        let key = "works:\(item.url.path)"
        if let cached = MinisMediaCache.shared.thumbnail(for: key) {
            thumb = cached
            return
        }
        let image: UIImage?
        if item.isVideo {
            image = await WorksListView.thumbnail(forVideoAt: item.url, maxPixelSize: 512)
        } else if let data = try? Data(contentsOf: item.url) {
            image = downsampleImage(data: data, maxPixelSize: 512)
        } else {
            image = nil
        }
        if let image {
            MinisMediaCache.shared.setThumbnail(image, for: key)
            thumb = image
        }
    }
}
