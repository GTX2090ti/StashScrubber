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
// 与 ScenesView / PerformersView / StudiosView 同一套范式（实现见 Views/ScrollRestore.swift）：
//   ① 卡片 `.id(...)` + 背面零尺寸 GeometryReader 上报纵坐标（PreferenceKey 字典 merge）
//   ② ScrollView 声明 `.coordinateSpace(name:)`（标签页 / 工作室页各用独立空间名 + 独立 Key）
//   ③ onPreferenceChange 里算「顶部可见项」，写进 ScrollMemory（引用类型，高频写入但不进
//      @Published，否则每帧重绘整个网格）
//   ④ 从短片详情返回时 `restore(_:exists:)`
//
// 与列表页的唯一差别：详情页网格上方还有标题 / 简介区，页面停在顶部时网格整体位于屏幕下方。
// 这种情形**不记录**锚点（requiresTopCrossed: true → 保持 nil → 返回时不干预），否则会把
// 「停在标题区」误恢复成「网格第一项贴顶」，反而多跳一次。

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
    @State private var anchor = ScrollMemory(requiresTopCrossed: true)
    @State private var currentPage = 1
    /// 当前在飞的列表请求（快速翻页时取消旧请求）
    @State private var fetchTask: Task<Void, Never>?
    private let perPage = 24

    private static let scrollSpace = "tag.scenes.scroll"

    private var totalPages: Int { max(1, Int(ceil(Double(sceneCount) / Double(perPage)))) }
    private var canPrev: Bool { currentPage > 1 }
    private var canNext: Bool { currentPage < totalPages }

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

                            // 翻页栏
                            HStack {
                                Button { Task { await goToPage(currentPage - 1) } } label: {
                                    Label("上一页", systemImage: "chevron.left")
                                }
                                .disabled(!canPrev || loading)
                                Spacer()
                                Text("第 \(currentPage) / \(totalPages) 页")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { Task { await goToPage(currentPage + 1) } } label: {
                                    Label("下一页", systemImage: "chevron.right")
                                }
                                .disabled(!canNext || loading)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(TagSceneOffsetKey.self) { anchor.accept($0) }
                    .onDisappear { anchor.freeze() }
                    .onAppear {
                        anchor.restore(proxy) { id in scenes.contains { $0.id == id } }
                    }
                    // 分页「加载更多」：请求期间冻结锚点、数据落地后守住位置 ——
                    // 追加数据会让 SwiftUI 重置偏移（表现：点一下「加载更多」就跳回最上面）
                    .onChange(of: loading) { busy in
                        if busy {
                            anchor.freeze()
                        } else {
                            anchor.restore(proxy, holdSeconds: 0.6) { id in scenes.contains { $0.id == id } }
                        }
                    }
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

    private func reload() async {
        await goToPage(1)
    }

    private func goToPage(_ page: Int) async {
        guard page >= 1 && page <= totalPages else { return }
        currentPage = page
        anchor.clear()
        // 快速翻页时取消旧请求，避免旧页结果晚到覆盖新页数据
        fetchTask?.cancel()
        let t = Task {
            loading = true
            defer { loading = false }
            do {
                let client = try settings.makeClient()
                let p = try await StashAPI.findScenesByTag(client, tagId: tagID, page: page, perPage: perPage)
                sceneCount = p.count
                scenes = p.scenes
            } catch let err {
                if !NetError.isCancellation(err) {
                    error = NetError.friendly(err)
                }
            }
        }
        fetchTask = t
        await t.value
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
    @State private var anchor = ScrollMemory(requiresTopCrossed: true)
    @State private var currentPage = 1
    /// 当前在飞的列表请求（快速翻页时取消旧请求）
    @State private var fetchTask: Task<Void, Never>?
    private let perPage = 24

    private static let scrollSpace = "studio.scenes.scroll"

    private var totalPages: Int { max(1, Int(ceil(Double(sceneCount) / Double(perPage)))) }
    private var canPrev: Bool { currentPage > 1 }
    private var canNext: Bool { currentPage < totalPages }

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

                            // 翻页栏
                            HStack {
                                Button { Task { await goToPage(currentPage - 1) } } label: {
                                    Label("上一页", systemImage: "chevron.left")
                                }
                                .disabled(!canPrev || loading)
                                Spacer()
                                Text("第 \(currentPage) / \(totalPages) 页")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { Task { await goToPage(currentPage + 1) } } label: {
                                    Label("下一页", systemImage: "chevron.right")
                                }
                                .disabled(!canNext || loading)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(StudioSceneOffsetKey.self) { anchor.accept($0) }
                    .onDisappear { anchor.freeze() }
                    .onAppear {
                        anchor.restore(proxy) { id in scenes.contains { $0.id == id } }
                    }
                    // 分页「加载更多」：请求期间冻结锚点、数据落地后守住位置 ——
                    // 追加数据会让 SwiftUI 重置偏移（表现：点一下「加载更多」就跳回最上面）
                    .onChange(of: loading) { busy in
                        if busy {
                            anchor.freeze()
                        } else {
                            anchor.restore(proxy, holdSeconds: 0.6) { id in scenes.contains { $0.id == id } }
                        }
                    }
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

    private func reload() async {
        currentPage = 1
        await goToPage(1)
    }

    private func goToPage(_ page: Int) async {
        guard page >= 1 && page <= totalPages else { return }
        currentPage = page
        anchor.clear()
        // 快速翻页时取消旧请求，避免旧页结果晚到覆盖新页数据
        fetchTask?.cancel()
        let t = Task {
            loading = true
            defer { loading = false }
            do {
                let client = try settings.makeClient()
                if studio == nil {
                    studio = try await StashAPI.findStudioByID(client, id: studioID)
                }
                let p = try await StashAPI.findScenesByStudio(client, studioId: studioID, page: page, perPage: perPage)
                sceneCount = p.count
                scenes = p.scenes
            } catch let err {
                if !NetError.isCancellation(err) {
                    error = NetError.friendly(err)
                }
            }
        }
        fetchTask = t
        await t.value
    }
}
