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

/// 记录列表「顶部可见演员」：从详情页返回时据此恢复原位（与短片页同策略）
final class PerformerScrollAnchor {
    var topID: String?
}

/// 收集各演员卡片在滚动容器内的纵坐标，用于推算顶部可见项
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
    @State private var anchor = PerformerScrollAnchor()

    /// 滚动容器坐标空间名（用于取各卡片相对滚动内容的纵坐标）
    private static let scrollSpace = "performers.scroll"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                content
                    .navigationTitle("演员")
                    .searchable(text: $vm.query, prompt: "搜索演员名称")
                    .onSubmit(of: .search) {
                        anchor.topID = nil
                        Task { await vm.reload() }
                    }
                    .refreshable {
                        anchor.topID = nil
                        await vm.reload()
                    }
                    // 连接或生效地址（内网↔外网自动兜底）变化时重新拉数据
                    .task(id: settings.reloadKey) {
                        anchor.topID = nil
                        await vm.reload()
                    }
                    .errorAlert($vm.error)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { ServerSwitcherMenu() }
                    }
            }
            // 从详情页返回列表根：滚回进入前的位置
            .onChange(of: path.count) { count in
                if count == 0 { restoreScroll(proxy) }
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
                updateTopVisible(dict)
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

    /// 顶部可见项 = 纵坐标 ≤ 0 且最接近 0 者；若全为正值（仍在列表顶端）则取最小者
    private func updateTopVisible(_ offsets: [String: CGFloat]) {
        guard !offsets.isEmpty else { return }
        let seen = offsets.filter { $0.value <= 1 }
        if let top = seen.max(by: { $0.value < $1.value })?.key {
            anchor.topID = top
        } else if let first = offsets.min(by: { $0.value < $1.value })?.key {
            anchor.topID = first
        }
    }

    /// 从详情返回时滚回进入前的顶部演员（关掉动画，避免闪动）
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let id = anchor.topID,
              vm.performers.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(id, anchor: .top) }
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
