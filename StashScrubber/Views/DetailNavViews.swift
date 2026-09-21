import SwiftUI

/// 与 ScenesView 主列表一致的网格列：iPhone（compact）固定 3 列；iPad（regular）自适应列宽约 140pt
func detailSceneGridColumns(_ hSizeClass: UserInterfaceSizeClass?) -> [GridItem] {
    if hSizeClass == .regular {
        return [GridItem(.adaptive(minimum: 140), spacing: 12)]
    }
    return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
}

// MARK: - 详情页内「相关短片」网格的滚动位置记录
//
// 与 ScenesView / PerformersView / StudiosView 同一套范式：
//   ① 卡片 `.id(...)` + 背面零尺寸 GeometryReader 上报纵坐标（PreferenceKey 字典 merge）
//   ② ScrollView 声明 `.coordinateSpace(name:)`
//   ③ onPreferenceChange 里算「顶部可见项」，写进引用类型锚点（高频写入，但不进 @Published，
//      否则每帧重绘整个网格）
//   ④ 从短片详情返回（onAppear）时延迟一拍、关动画 scrollTo 回去
//
// 与列表页的唯一差别：详情页网格上方还有标题 / 简介区，页面停在顶部时网格整体位于屏幕下方。
// 这种情形**不记录**锚点（保持 nil → 返回时不干预），否则会把「停在标题区」误恢复成
// 「网格第一项贴顶」，反而多跳一次。

/// 网格滚动位置锚点（引用类型：滚动中每秒写几十次，进 @Published 会导致整格重绘）
final class DetailSceneAnchor {
    var topID: String?
}

/// 标签详情网格的纵坐标上报
private struct TagSceneOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 工作室详情网格的纵坐标上报（与标签页分开，避免同时驻留时互相覆盖）
private struct StudioSceneOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - 标签详情（短片详情点击标签跳转；进入前已校验标签存在）

struct TagDetailView: View {
    let tagID: String
    let tagName: String

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var scenes: [Scene] = []
    @State private var sceneCount = 0
    @State private var loading = false
    @State private var error: String?
    @State private var anchor = DetailSceneAnchor()

    private static let scrollSpace = "tag.scenes.scroll"

    var body: some View {
        Group {
            if loading && scenes.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, scenes.isEmpty {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "tag")
                                    .foregroundStyle(Color.appAccent)
                                Text(tagName)
                                    .font(.title2.weight(.bold))
                            }
                            .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("相关短片（\(sceneCount)）")
                                    .font(.subheadline.weight(.semibold))
                                if scenes.isEmpty {
                                    Text("没有关联短片")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    LazyVGrid(columns: detailSceneGridColumns(hSizeClass), spacing: 14) {
                                        ForEach(scenes) { sc in
                                            NavigationLink(value: sc.id) {
                                                SceneCard(scene: sc)
                                            }
                                            .buttonStyle(.plain)
                                            .id(sc.id)
                                            .background(sceneProbe(sc.id))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)

                            if sceneCount > scenes.count {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    if loading { ProgressView() }
                                    else { Label("加载更多", systemImage: "arrow.down.circle") }
                                }
                                .padding(.vertical, 16)
                            }
                        }
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(TagSceneOffsetKey.self) { updateTopVisible($0) }
                    .onAppear { restoreScroll(proxy) }
                }
            }
        }
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tagID) { await reload() }
        .errorAlert($error)
    }

    /// 卡片背面的零尺寸探针：上报该短片相对滚动容器的纵坐标
    private func sceneProbe(_ id: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: TagSceneOffsetKey.self,
                value: [id: g.frame(in: .named(Self.scrollSpace)).minY]
            )
        }
    }

    /// 顶部可见项 = 纵坐标 ≤ 0 且最接近 0 者；网格整体仍在屏幕下方（停在标题区）时不记录
    private func updateTopVisible(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        guard let top = offsets.filter({ $0.value <= 1 })
            .max(by: { $0.value < $1.value })?.key else { return }
        anchor.topID = top
    }

    /// 从短片详情返回时滚回进入前的顶部短片（等布局落定 + 关动画，避免先闪顶部再滑下来）
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let id = anchor.topID, scenes.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func reload() async {
        anchor.topID = nil
        scenes = []
        await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            let page = scenes.count / 24 + 1
            let p = try await StashAPI.findScenesByTag(client, tagId: tagID, page: page)
            sceneCount = p.count
            scenes += p.scenes
        } catch {
            self.error = NetError.friendly(error)
        }
    }
}

// MARK: - 工作室详情（短片详情点击工作室跳转；进入前已校验存在）

struct StudioDetailView: View {
    let studioID: String
    let studioName: String

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var studio: Studio?
    @State private var scenes: [Scene] = []
    @State private var sceneCount = 0
    @State private var loading = false
    @State private var error: String?
    @State private var anchor = DetailSceneAnchor()

    private static let scrollSpace = "studio.scenes.scroll"

    var body: some View {
        Group {
            if loading && scenes.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, scenes.isEmpty {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "building.2")
                                    .foregroundStyle(Color.appAccent)
                                Text(studio?.name ?? studioName)
                                    .font(.title2.weight(.bold))
                            }
                            .padding(.horizontal)

                            if let s = studio {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let r = s.rating100 {
                                        Label(String(format: "%.1f", Double(r) / 20.0), systemImage: "star.fill")
                                            .font(.subheadline).foregroundStyle(.yellow)
                                    }
                                    if let u = s.url, !u.isEmpty, let url = URL(string: u) {
                                        Link(u, destination: url)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    if let ds = s.details, !ds.isEmpty {
                                        Text(ds)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.horizontal)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("相关短片（\(sceneCount)）")
                                    .font(.subheadline.weight(.semibold))
                                if scenes.isEmpty {
                                    Text("没有关联短片")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    LazyVGrid(columns: detailSceneGridColumns(hSizeClass), spacing: 14) {
                                        ForEach(scenes) { sc in
                                            NavigationLink(value: sc.id) {
                                                SceneCard(scene: sc)
                                            }
                                            .buttonStyle(.plain)
                                            .id(sc.id)
                                            .background(sceneProbe(sc.id))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)

                            if sceneCount > scenes.count {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    if loading { ProgressView() }
                                    else { Label("加载更多", systemImage: "arrow.down.circle") }
                                }
                                .padding(.vertical, 16)
                            }
                        }
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(StudioSceneOffsetKey.self) { updateTopVisible($0) }
                    .onAppear { restoreScroll(proxy) }
                }
            }
        }
        .navigationTitle(studio?.name ?? studioName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: studioID) { await reload() }
        .errorAlert($error)
    }

    /// 卡片背面的零尺寸探针：上报该短片相对滚动容器的纵坐标
    private func sceneProbe(_ id: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: StudioSceneOffsetKey.self,
                value: [id: g.frame(in: .named(Self.scrollSpace)).minY]
            )
        }
    }

    /// 顶部可见项 = 纵坐标 ≤ 0 且最接近 0 者；网格整体仍在屏幕下方（停在标题/简介区）时不记录
    private func updateTopVisible(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        guard let top = offsets.filter({ $0.value <= 1 })
            .max(by: { $0.value < $1.value })?.key else { return }
        anchor.topID = top
    }

    /// 从短片详情返回时滚回进入前的顶部短片（等布局落定 + 关动画，避免先闪顶部再滑下来）
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let id = anchor.topID, scenes.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func reload() async {
        anchor.topID = nil
        scenes = []
        studio = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            if studio == nil {
                studio = try await StashAPI.findStudioByID(client, id: studioID)
            }
            let page = scenes.count / 24 + 1
            let p = try await StashAPI.findScenesByStudio(client, studioId: studioID, page: page)
            sceneCount = p.count
            scenes += p.scenes
        } catch {
            self.error = NetError.friendly(error)
        }
    }
}
