import SwiftUI

// MARK: - 演员列表

@MainActor
final class PerformerListViewModel: ObservableObject {
    @Published var performers: [Performer] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    /// 加载卡住（网络层未按期返回）：显示重试入口，避免页面永久转圈
    @Published var timedOut = false

    private var page = 1
    private var lastQuery = ""
    /// 请求代号：reload 时自增，迟到的旧响应据此丢弃
    private var generation = 0
    /// 看门狗秒数：超过即认为网络层卡死（API 硬超时 25s + 解析余量）
    static let watchdogSeconds: Double = 30

    var canLoadMore: Bool { performers.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        performers = []
        error = nil
        timedOut = false
        generation += 1
        await fetch(gen: generation)
    }

    /// 分页「加载更多」（同一代内防重入）
    func load() async {
        guard !loading else { return }
        await fetch(gen: generation)
    }

    /// 重试：清空并重新拉第一页
    func retry() async { await reload() }

    private func fetch(gen: Int) async {
        loading = true
        defer { if gen == generation { loading = false } }

        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timedOut = true
        }
        defer { watchdog.cancel() }

        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findPerformers(client, query: lastQuery, page: page)
            guard gen == generation else { return }   // 过期响应：丢弃
            timedOut = false
            total = p.count
            if page == 1 { performers = p.performers } else { performers += p.performers }
            page += 1
            error = nil
            AppSettings.shared.markSynced()
        } catch {
            guard gen == generation else { return }
            if !NetError.isCancellation(error) {
                self.error = NetError.friendly(error)
            }
        }
    }
}

/// 收集各演员卡片在滚动容器内的纵坐标，用于推算顶部可见项
/// （锚点与恢复逻辑见 Views/ScrollRestore.swift 的 ScrollMemory）
private struct PerformerVisibleOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct PerformersView: View {
    @StateObject private var vm = PerformerListViewModel()
    @EnvironmentObject private var settings: AppSettings
    /// 显式导航路径：用于感知「从详情返回列表根」，从而恢复滚动位置
    @State private var path = NavigationPath()
    @State private var anchor = ScrollMemory()

    /// 滚动容器坐标空间名（用于取各卡片相对滚动内容的纵坐标）
    private static let scrollSpace = "performers.scroll"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                // 用 ZStack 包一层稳定容器：content 是 if/else 条件分支，分支 identity
                // 变化会让挂在它上面的 onChange / onAppear 一并重建，从而丢掉「1 → 0」
                // 的回调（滚动位置恢复会彻底失效）。修饰符必须挂在分支外的稳定层上。
                ZStack { content }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("演员")
                    .searchable(text: $vm.query, prompt: "搜索演员名称")
                    .onSubmit(of: .search) {
                        anchor.clear()
                        Task { await vm.reload() }
                    }
                    .refreshable {
                        anchor.clear()
                        await vm.reload()
                    }
                    // 连接或生效地址（内网↔外网自动兜底）变化时重新拉数据
                    .task(id: settings.reloadKey) {
                        anchor.clear()
                        await vm.reload()
                    }
                    .errorAlert($vm.error)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { ServerSwitcherMenu() }
                    }
                    // 从详情页返回列表根：滚回进入前的位置。
                    // （proxy 只存在于 ScrollViewReader 闭包内，这些修饰符必须写在闭包内部）
                    //
                    // 两条恢复入口都要挂：根列表在返回时可能被重建，届时
                    // `onChange(of: path.count)` 的基准值会被重置而不再回调，
                    // 只能靠视图重新出现时的 `onAppear` 兜底。
                    .onChange(of: path.count) { count in
                        if count > 0 {
                            anchor.freeze()          // 进入详情页：先冻结锚点，停止接受上报
                        } else {
                            anchor.restore(proxy) { id in vm.performers.contains { $0.id == id } }
                        }
                    }
                    .onDisappear { anchor.freeze() }
                    .onAppear {
                        anchor.restore(proxy) { id in vm.performers.contains { $0.id == id } }
                    }
            }
            // 导航目的地统一注册在栈根，勿下移到条件分支里（否则列表数据刷新时可能短暂失效）
            .navigationDestination(for: String.self) { id in
                SceneDetailView(sceneID: id)
            }
            .navigationDestination(for: PerformerNavID.self) { pv in
                PerformerDetailView(performerID: pv.id)
            }
            .navigationDestination(for: TagNavID.self) { t in
                TagDetailView(tagID: t.id, tagName: t.name)
            }
            .navigationDestination(for: StudioNavID.self) { st in
                StudioDetailView(studioID: st.id, studioName: st.name)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.performers.isEmpty {
            if vm.timedOut {
                LoadRetryView(
                    title: "加载超时",
                    hint: "请求超过 \(Int(PerformerListViewModel.watchdogSeconds)) 秒仍未返回，可能是网络切换或连接卡住。\n可重试，或到 设置 → 网络 查看网络日志。"
                ) {
                    Task { await vm.reload() }
                }
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if vm.performers.isEmpty {
            EmptyStateView(title: "没有演员", hint: "下拉刷新，或检查服务器与过滤条件",
                           retryTitle: "重试") { Task { await vm.reload() } }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 18) {
                    ForEach(vm.performers) { p in
                        NavigationLink(value: PerformerNavID(id: p.id, name: p.name)) {
                            PerformerCard(performer: p)
                        }
                        .buttonStyle(.plain)
                        .id(p.id)
                        .background(scrollProbe(p.id))
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
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(PerformerVisibleOffsetKey.self) { dict in
                anchor.accept(dict)
            }
        }
    }

    /// 卡片背面的零尺寸探针：上报该演员卡片相对滚动内容的纵坐标
    private func scrollProbe(_ id: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: PerformerVisibleOffsetKey.self,
                value: [id: g.frame(in: .named(Self.scrollSpace)).minY]
            )
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
            self.error = NetError.friendly(error)
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
            self.error = NetError.friendly(error)
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
