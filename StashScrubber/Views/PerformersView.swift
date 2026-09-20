import SwiftUI

// MARK: - 演员列表

@MainActor
final class PerformerListViewModel: ObservableObject {
    @Published var performers: [Performer] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    private var page = 1
    private var lastQuery = ""

    var canLoadMore: Bool { performers.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        performers = []
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findPerformers(client, query: lastQuery, page: page)
            total = p.count
            if page == 1 { performers = p.performers } else { performers += p.performers }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PerformersView: View {
    @StateObject private var vm = PerformerListViewModel()
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("演员")
                .searchable(text: $vm.query, prompt: "搜索演员名称")
                .onSubmit(of: .search) { Task { await vm.reload() } }
                .refreshable { await vm.reload() }
                .task(id: settings.activeProfileID) { await vm.reload() }
                .errorAlert($vm.error)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { ServerSwitcherMenu() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.performers.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.performers.isEmpty {
            EmptyStateView(title: "没有演员", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 18) {
                    ForEach(vm.performers) { p in
                        NavigationLink(value: p.id) {
                            PerformerCard(performer: p)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if vm.canLoadMore {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        if vm.loading { ProgressView() }
                        else { Label("加载更多（共 \(vm.total)）", systemImage: "arrow.down.circle") }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationDestination(for: String.self) { id in
                PerformerDetailView(performerID: id)
            }
        }
    }
}

struct PerformerCard: View {
    let performer: Performer

    var body: some View {
        VStack(spacing: 8) {
            RemoteImageView(urlString: performer.imagePath)
                .frame(width: 120, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(performer.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            if let d = performer.birthdate {
                Text(d).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 演员详情（查看 / 削刮 / 编辑）

struct PerformerDetailView: View {
    let performerID: String

    @EnvironmentObject private var settings: AppSettings
    @State private var performer: Performer?
    @State private var error: String?
    @State private var showEdit = false
    @State private var showScrape = false
    // 出演作品（该演员关联的短片，SenPlayer 风格网格）
    @State private var scenes: [Scene] = []
    @State private var sceneCount = 0
    @State private var scenesLoading = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        Group {
            if let performer {
                detail(performer)
            } else if let error {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(performer?.name ?? "演员")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: performerID) {
            await load()
            await reloadScenes()
        }
        .errorAlert($error)
        .sheet(isPresented: $showEdit) {
            if let performer {
                PerformerEditView(performer: performer) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showScrape) {
            if let performer {
                ScrapeSheet(kind: .performer, targetID: performer.id, existing: ExistingMeta(performer: performer)) {
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
            performer = try await StashAPI.performer(client, id: performerID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 出演作品网格：iPhone 两列，iPad 自适应列宽约 160pt（与短片页同策略）
    private var sceneGridColumns: [GridItem] {
        if hSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 160), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    @ViewBuilder
    private func detail(_ p: Performer) -> some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView {
                if wide {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 24) {
                            RemoteImageView(urlString: p.imagePath)
                                .frame(width: min(300, geo.size.width * 0.3))
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            infoColumn(p)
                        }
                        scenesSection
                    }
                    .padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        RemoteImageView(urlString: p.imagePath)
                            .frame(maxWidth: 280)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        infoColumn(p)
                        scenesSection
                    }
                    .padding(20)
                }
            }
        }
    }

    /// 出演作品分区：SenPlayer 风格卡片网格 + 加载更多
    @ViewBuilder
    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("出演作品（\(sceneCount)）")
                .font(.subheadline.weight(.semibold))
            if scenes.isEmpty && scenesLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if scenes.isEmpty {
                Text("没有关联短片")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: sceneGridColumns, spacing: 18) {
                    ForEach(scenes) { sc in
                        NavigationLink(value: sc.id) {
                            SceneCard(scene: sc)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if sceneCount > scenes.count {
                    Button {
                        Task { await loadMoreScenes() }
                    } label: {
                        if scenesLoading { ProgressView() }
                        else { Label("加载更多", systemImage: "arrow.down.circle") }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func reloadScenes() async {
        scenes = []
        await loadMoreScenes()
    }

    private func loadMoreScenes() async {
        guard !scenesLoading else { return }
        scenesLoading = true
        defer { scenesLoading = false }
        do {
            let client = try settings.makeClient()
            let page = scenes.count / 24 + 1
            let p = try await StashAPI.findScenesByPerformer(client, performerId: performerID, page: page)
            sceneCount = p.count
            scenes += p.scenes
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func infoColumn(_ p: Performer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(p.name).font(.title2.weight(.bold))
            if let d = p.disambiguation {
                Text(d).font(.subheadline).foregroundStyle(.secondary)
            }
            InfoRow(label: "出生日期", value: p.birthdate)
            InfoRow(label: "国籍", value: p.country)
            InfoRow(label: "族裔", value: p.ethnicity)
            InfoRow(label: "三围", value: p.measurements)
            InfoRow(label: "从业年限", value: p.careerLength)
            if let r = p.rating100 {
                HStack {
                    Text("评分").font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f / 5.0", Double(r) / 20.0))
                        .font(.subheadline)
                }
            }
            if let ds = p.details, !ds.isEmpty {
                Text(ds).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let ts = p.tags, !ts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标签").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8) {
                        ForEach(ts) { t in Chip(text: t.name) }
                    }
                }
            }
        }
    }
}
