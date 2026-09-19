import SwiftUI

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
                direction: lastDirection.isEmpty ? direction : lastDirection
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

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("场景")
                .searchable(text: $vm.query, prompt: "搜索场景标题 / 简介")
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.scenes.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.scenes.isEmpty {
            EmptyStateView(title: "没有场景", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                if viewMode == "grid" {
                    // 紧凑网格：一排 3 个（iPhone），iPad 随宽度 5~7 列
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
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
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(urlString: scene.paths?.webp ?? scene.paths?.screenshot)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(scene.title ?? "（无标题）")
                .font(.subheadline.weight(.semibold))
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
            RemoteImageView(urlString: scene.paths?.webp ?? scene.paths?.screenshot)
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
        .navigationTitle(scene?.title ?? "场景")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sceneID) { await load() }
        .errorAlert($error)
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

    // 宽屏（iPad 横屏）左右双栏，窄屏上下堆叠 —— 响应式适配
    @ViewBuilder
    private func detail(_ s: Scene) -> some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        imageColumn(s)
                            .frame(width: geo.size.width * 0.42)
                        infoColumn(s)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        imageColumn(s)
                        infoColumn(s)
                    }
                    .padding()
                }
            }
        }
    }

    private func imageColumn(_ s: Scene) -> some View {
        RemoteImageView(urlString: s.paths?.webp ?? s.paths?.screenshot)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoColumn(_ s: Scene) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(s.title ?? "（无标题）")
                .font(.title2.weight(.bold))
            if let st = s.studio {
                Label(st.name, systemImage: "building.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let d = s.date {
                    Label(d, systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let r = s.rating100 {
                    Label(String(format: "%.1f", Double(r) / 20.0), systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.yellow)
                }
                if let o = s.oCounter, o > 0 {
                    Label("\(o)", systemImage: "eye")
                        .font(.subheadline).foregroundStyle(.secondary)
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
                        ForEach(ts) { t in Chip(text: t.name) }
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
