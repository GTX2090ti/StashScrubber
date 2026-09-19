import SwiftUI
import UIKit

// MARK: - 场景列表

@MainActor
final class SceneListViewModel: ObservableObject {
    @Published var scenes: [Scene] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    @Published var sort: String = "date"
    @Published var direction: String = "DESC"
    @Published var filter = SceneFilterState()

    private var page = 1
    private var lastQuery = ""
    private var lastSort = ""
    private var lastDirection = ""

    var canLoadMore: Bool { scenes.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        lastSort = sort
        lastDirection = direction
        scenes = []
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findScenes(
                client, query: lastQuery, page: page,
                sort: lastSort.isEmpty ? sort : lastSort,
                direction: lastDirection.isEmpty ? direction : lastDirection,
                sceneFilter: filter.toSceneFilter()
            )
            total = p.count
            if page == 1 { scenes = p.scenes } else { scenes += p.scenes }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ScenesView: View {
    @StateObject private var vm = SceneListViewModel()
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("scenes.viewMode") private var viewMode: String = "grid"   // grid=一排3个 / list=列表
    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("短片")
                .searchable(text: $vm.query, prompt: "搜索短片标题 / 简介")
                .onSubmit(of: .search) { Task { await vm.reload() } }
                .refreshable { await vm.reload() }
                .task(id: settings.activeProfileID) { await vm.reload() }
                .errorAlert($vm.error)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { ServerSwitcherMenu() }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            viewMode = (viewMode == "grid") ? "list" : "grid"
                        } label: {
                            Label(viewMode == "grid" ? "列表视图" : "网格视图",
                                  systemImage: viewMode == "grid" ? "list.bullet" : "square.grid.2x2")
                        }
                        Button {
                            showFilter = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if vm.filter.activeCount > 0 {
                                    Text("\(vm.filter.activeCount)")
                                        .font(.caption2.weight(.bold))
                                        .padding(3)
                                        .background(Circle().fill(Color.red))
                                        .foregroundStyle(.white)
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        Menu {
                            Picker("排序", selection: $vm.sort) {
                                Text("日期").tag("date")
                                Text("标题").tag("title")
                                Text("评分").tag("rating")
                                Text("O 计数").tag("o_counter")
                            }
                            Button {
                                vm.direction = vm.direction == "DESC" ? "ASC" : "DESC"
                            } label: {
                                Label(vm.direction == "DESC" ? "降序" : "升序",
                                      systemImage: vm.direction == "DESC" ? "arrow.down" : "arrow.up")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
                .onChange(of: vm.sort) { _ in Task { await vm.reload() } }
                .onChange(of: vm.direction) { _ in Task { await vm.reload() } }
                .sheet(isPresented: $showFilter) {
                    SceneFilterSheet(state: $vm.filter) {
                        Task { await vm.reload() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.scenes.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.scenes.isEmpty {
            EmptyStateView(title: "没有短片", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                if viewMode == "grid" {
                    // 海报网格：一排固定 3 个竖版 2:3 海报卡片
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                        ForEach(vm.scenes) { s in
                            NavigationLink(value: s.id) {
                                SceneCard(scene: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // 列表模式：左图右文整行卡片
                    LazyVStack(spacing: 0) {
                        ForEach(vm.scenes) { s in
                            NavigationLink(value: s.id) {
                                SceneRow(scene: s)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }

                if vm.canLoadMore {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        if vm.loading {
                            ProgressView()
                        } else {
                            Label("加载更多（共 \(vm.total)）", systemImage: "arrow.down.circle")
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationDestination(for: String.self) { id in
                SceneDetailView(sceneID: id)
            }
        }
    }
}

struct SceneCard: View {
    let scene: Scene

    var body: some View {
        VStack(spacing: 5) {
            RemoteImageView(urlString: scene.paths?.screenshot ?? scene.paths?.webp, placeholderIcon: "film")
                .aspectRatio(2 / 3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(scene.title ?? "（无标题）")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                if let st = scene.studio {
                    Text(st.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let d = scene.date {
                    Text(d).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// 列表模式整行卡片
struct SceneRow: View {
    let scene: Scene

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(urlString: scene.paths?.screenshot ?? scene.paths?.webp)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.title ?? "（无标题）")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let st = scene.studio {
                        Text(st.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let d = scene.date {
                        Text(d).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 场景详情（元数据查看 / 削刮 / 编辑）

struct SceneDetailView: View {
    let sceneID: String

    @EnvironmentObject private var settings: AppSettings
    @State private var scene: Scene?
    @State private var error: String?
    @State private var showEdit = false
    @State private var showScrape = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var savingTitle = false
    @State private var copiedPath = false
    @State private var tagNav: TagNavID?
    @State private var showTagDetail = false
    @State private var studioNav: StudioNavID?
    @State private var showStudioDetail = false
    @State private var showMerge = false

    var body: some View {
        Group {
            if let scene {
                detail(scene)
            } else if let error {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(scene?.title ?? "短片")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sceneID) { await load() }
        .errorAlert($error)
        .navigationDestination(isPresented: $showTagDetail) {
            if let t = tagNav { TagDetailView(tagID: t.id, tagName: t.name) }
        }
        .navigationDestination(isPresented: $showStudioDetail) {
            if let st = studioNav { StudioDetailView(studioID: st.id, studioName: st.name) }
        }
        .sheet(isPresented: $showMerge) {
            if let scene {
                MergeSceneSheet(target: scene) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let scene {
                SceneEditView(scene: scene) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showScrape) {
            if let scene {
                ScrapeSheet(kind: .scene, targetID: scene.id, existing: ExistingMeta(scene: scene)) {
                    Task { await load() }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showScrape = true
                    } label: {
                        Label("元数据削刮", systemImage: "sparkle.magnifyingglass")
                    }
                    Button {
                        showMerge = true
                    } label: {
                        Label("合并其他短片到本片", systemImage: "arrow.triangle.merge")
                    }
                } label: {
                    Label("削刮", systemImage: "sparkles")
                }
                Button {
                    showEdit = true
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
            }
        }
    }

    private func load() async {
        error = nil
        do {
            let client = try settings.makeClient()
            scene = try await StashAPI.scene(client, id: sceneID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveTitle() async {
        let newTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else {
            editingTitle = false
            return
        }
        savingTitle = true
        defer { savingTitle = false }
        do {
            let client = try settings.makeClient()
            var input = SceneUpdateInput(id: sceneID)
            input.title = newTitle
            try await StashAPI.updateScene(client, input: input)
            scene?.title = newTitle   // 实时更新
            editingTitle = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 点击标签：先校验 Stash 中是否仍存在，再跳转标签详情
    private func openTag(_ t: Tag) async {
        do {
            let client = try settings.makeClient()
            guard try await StashAPI.findTag(client, id: t.id) != nil else {
                error = "「\(t.name)」在 Stash 中已不存在（可能已被删除），无法打开标签详情"
                return
            }
            tagNav = TagNavID(id: t.id, name: t.name)
            showTagDetail = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 点击工作室：先校验是否仍存在，再跳转工作室详情
    private func openStudio(_ st: Studio) async {
        do {
            let client = try settings.makeClient()
            _ = try await StashAPI.findStudioByID(client, id: st.id)   // 不存在会抛 noData
            studioNav = StudioNavID(id: st.id, name: st.name)
            showStudioDetail = true
        } catch StashAPIError.noData {
            error = "「\(st.name)」在 Stash 中已不存在（可能已被删除），无法打开工作室详情"
        } catch {
            self.error = error.localizedDescription
        }
    }

    // 宽屏（iPad 横屏）左右双栏，窄屏上下堆叠 —— 布局与演员详情同构
    @ViewBuilder
    private func detail(_ s: Scene) -> some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        imageColumn(s)
                            .frame(width: min(420, geo.size.width * 0.45))
                        infoColumn(s)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        imageColumn(s)
                            .frame(maxWidth: 360)
                        infoColumn(s)
                    }
                    .padding()
                }
            }
        }
    }

    private func imageColumn(_ s: Scene) -> some View {
        RemoteImageView(urlString: s.paths?.screenshot ?? s.paths?.webp)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 与演员详情 infoColumn 同构：标题 + InfoRow 信息行（左标签 72pt + 右值）+ 详情文本 + Chip 分区
    private func infoColumn(_ s: Scene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题（点击编辑，保存后实时更新）
            if editingTitle {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("标题", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await saveTitle() } }
                    HStack {
                        Button("取消", role: .cancel) { editingTitle = false }
                        Spacer()
                        if savingTitle {
                            ProgressView()
                        } else {
                            Button("保存") { Task { await saveTitle() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                Button {
                    titleDraft = s.title ?? ""
                    editingTitle = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(s.title ?? "（无标题）")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Image(systemName: "pencil.circle")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            // 信息行：工作室（可点击跳转，存在性校验见 openStudio）
            if let st = s.studio {
                Button {
                    Task { await openStudio(st) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("工作室")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Label(st.name, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(Color.appAccent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            InfoRow(label: "日期", value: s.date)
            if let r = s.rating100 {
                HStack(alignment: .firstTextBaseline) {
                    Text("评分")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f / 5.0", Double(r) / 20.0))
                        .font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
            if let o = s.oCounter, o > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("O 计数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(o)")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
            // 文件路径（含一键复制，成功提示）
            if let path = s.files?.first?.path, !path.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("文件路径")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = path
                        copiedPath = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedPath = false
                        }
                    } label: {
                        Label(copiedPath ? "已复制" : "复制",
                              systemImage: copiedPath ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let ds = s.details, !ds.isEmpty {
                Text(ds)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let ps = s.performers, !ps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("演员").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(ps) { p in Chip(text: p.name) }
                    }
                }
            }
            if let ts = s.tags, !ts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标签").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(ts) { t in
                            Button {
                                Task { await openTag(t) }
                            } label: {
                                Chip(text: t.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let us = s.urls, !us.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL").font(.subheadline.weight(.semibold))
                    ForEach(us, id: \.self) { u in
                        if let url = URL(string: u) {
                            Link(u, destination: url)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }
}
