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
    @State private var section: WorksSection = .components
    @State private var files: [WorkFile] = []
    @State private var media: [MediaItem] = []
    /// 重扫令牌：切走再切回时旧扫描结果作废，不盖新结果。
    @State private var scanToken = UUID()
    /// 复用 MessageImageGallery 的呈现载荷（同文件已定义，memberwise init 可用）。
    @State private var gallery: GalleryPresentation?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                segmentBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                content
            }
            // 原生标题留空：壳层顶部是身份胶囊（pp 终稿），此页不占标题位。
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { rescan() }
        .fullScreenCover(item: $gallery) { presentation in
            MessageImageGallery(items: presentation.items, startIndex: presentation.startIndex)
        }
    }

    // MARK: 分段胶囊

    private var segmentBar: some View {
        HStack(spacing: 4) {
            segmentButton(.components, "Components")
            segmentButton(.media, "Media")
        }
        .padding(3)
        .frame(height: 44)
        .background(Capsule().fill(Self.trackColor))
    }

    private func segmentButton(_ target: WorksSection, _ key: LocalizedStringKey) -> some View {
        let selected = section == target
        return Button {
            guard !selected else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                section = target
            }
        } label: {
            Text(key)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Self.selectedTextColor : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selected ? Self.selectedColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 内容两段

    @ViewBuilder
    private var content: some View {
        switch section {
        case .components:
            if files.isEmpty {
                emptyView("No components yet")
            } else {
                List {
                    ForEach(files) { file in
                        componentRow(file)
                    }
                }
                .listStyle(.plain)
            }
        case .media:
            if media.isEmpty {
                emptyView("No media yet")
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
    nonisolated static func scanComponents() -> [WorkFile] {
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
    nonisolated static func scanMedia() -> [MediaItem] {
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
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items {
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

    // MARK: 动态色

    /// 分段轨道：light #F2F2F2 / dark #1C1C1E。
    private static let trackColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            : UIColor(white: 0xF2 / 255, alpha: 1)
    })
    /// 选中段：light 白 / dark #3A3833。
    private static let selectedColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x3A / 255, green: 0x38 / 255, blue: 0x33 / 255, alpha: 1)
            : .white
    })
    /// 选中段文字（亮字/深字随底反相）。
    private static let selectedTextColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(white: 0x11 / 255, alpha: 1)
    })

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
