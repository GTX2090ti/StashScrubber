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
    /// 加载卡住（网络层未按期返回）：显示重试入口，避免页面永久转圈
    @Published var timedOut = false

    private var page = 1
    private var lastQuery = ""
    private var lastSort = ""
    private var lastDirection = ""
    /// 请求代号：reload 时自增，迟到的旧响应据此丢弃，不覆盖新结果
    private var generation = 0
    /// 看门狗秒数：超过即认为网络层卡死（API 硬超时 25s + 解析余量）
    static let watchdogSeconds: Double = 30

    var canLoadMore: Bool { scenes.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        lastSort = sort
        lastDirection = direction
        scenes = []
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
        // 只有「当前代号」的请求结束才复位 loading：
        // 否则迟到的旧请求（或永不到达的旧请求）会把新请求的加载态弄丢 / 弄乱
        defer { if gen == generation { loading = false } }

        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timedOut = true
        }
        defer { watchdog.cancel() }

        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findScenes(
                client, query: lastQuery, page: page,
                sort: lastSort.isEmpty ? sort : lastSort,
                direction: lastDirection.isEmpty ? direction : lastDirection,
                sceneFilter: filter.toSceneFilter()
            )
            guard gen == generation else { return }   // 过期响应：丢弃
            timedOut = false
            total = p.count
            if page == 1 { scenes = p.scenes } else { scenes += p.scenes }
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

/// 收集各短片在滚动容器内的纵坐标，用于推算顶部可见项
/// （锚点与恢复逻辑见 Views/ScrollRestore.swift 的 ScrollMemory）
private struct SceneVisibleOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ScenesView: View {
    @StateObject private var vm = SceneListViewModel()
    @EnvironmentObject private var settings: AppSettings
    /// 父级切 tab 时的刷新信号：TabView 不销毁 View，需要靠这个触发重载
    var refreshTick: Int = 0
    @AppStorage("scenes.viewMode") private var viewMode: String = "grid"   // grid=一排3个 / list=列表
    @State private var showFilter = false
    /// 显式导航路径：用于感知「从详情返回列表根」，从而恢复滚动位置
    @State private var path = NavigationPath()
    @State private var anchor = ScrollMemory()
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 滚动容器坐标空间名（用于取各短片相对滚动内容的纵坐标）
    private static let scrollSpace = "scenes.scroll"

    /// iPhone（compact）固定 3 列；iPad（regular）自适应列宽约 140pt，自动排更多列
    private var gridColumns: [GridItem] {
        if hSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 140), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                // 用 ZStack 包一层稳定容器：content 是 if/else 条件分支，分支 identity
                // 变化会让挂在它上面的 onChange / onAppear 一并重建，从而丢掉「1 → 0」
                // 的回调（滚动位置恢复会彻底失效）。修饰符必须挂在分支外的稳定层上。
                ZStack { content }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("短片")
                    .searchable(text: $vm.query, prompt: "搜索短片标题 / 简介")
                    .onSubmit(of: .search) {
                        anchor.clear()
                        Task { await vm.reload() }
                    }
                    .refreshable {
                        anchor.clear()
                        await vm.reload()
                    }
                    // 连接 / 生效地址 / 切 tab 变化时重新拉数据
                    .task(id: settings.reloadKey + "|\(refreshTick)") {
                        anchor.clear()
                        await vm.reload()
                    }
                    .errorAlert($vm.error)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { ServerSwitcherMenu() }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                viewMode = (viewMode == "grid") ? "list" : "grid"
                                anchor.clear()
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
                    .onChange(of: vm.sort) { _ in
                        anchor.clear()
                        Task { await vm.reload() }
                    }
                    .onChange(of: vm.direction) { _ in
                        anchor.clear()
                        Task { await vm.reload() }
                    }
                    .sheet(isPresented: $showFilter) {
                        SceneFilterSheet(state: $vm.filter) {
                            anchor.clear()
                            Task { await vm.reload() }
                        }
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
                            anchor.restore(proxy) { id in vm.scenes.contains { $0.id == id } }
                        }
                    }
                    .onDisappear { anchor.freeze() }
                    .onAppear {
                        anchor.restore(proxy) { id in vm.scenes.contains { $0.id == id } }
                    }
                    // 分页「加载更多」：请求期间冻结锚点、数据落地后守住位置 ——
                    // 追加数据会让 SwiftUI 重置偏移（表现：点一下「加载更多」就跳回最上面）
                    .onChange(of: vm.loading) { loading in
                        if loading {
                            anchor.freeze()
                        } else {
                            anchor.restore(proxy, holdSeconds: 0.6) { id in vm.scenes.contains { $0.id == id } }
                        }
                    }
            }
            // 导航目的地统一注册在栈根，勿下移到条件分支里（否则列表数据刷新时可能短暂失效）
            .navigationDestination(for: String.self) { id in
                SceneDetailView(sceneID: id)
            }
            .navigationDestination(for: TagNavID.self) { t in
                TagDetailView(tagID: t.id, tagName: t.name)
            }
            .navigationDestination(for: StudioNavID.self) { st in
                StudioDetailView(studioID: st.id, studioName: st.name)
            }
            .navigationDestination(for: PerformerNavID.self) { pv in
                PerformerDetailView(performerID: pv.id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.scenes.isEmpty {
            if vm.timedOut {
                LoadRetryView(
                    title: "加载超时",
                    hint: "请求超过 \(Int(SceneListViewModel.watchdogSeconds)) 秒仍未返回，可能是网络切换或连接卡住。\n可重试，或到 设置 → 网络 查看网络日志。"
                ) {
                    Task { await vm.reload() }
                }
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if vm.scenes.isEmpty {
            EmptyStateView(title: "没有短片", hint: "下拉刷新，或检查服务器与过滤条件",
                           retryTitle: "重试") { Task { await vm.reload() } }
        } else {
            ScrollView {
                if viewMode == "grid" {
                    // 海报网格：一排固定 3 个竖版 2:3 海报卡片
                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(vm.scenes) { s in
                            NavigationLink(value: s.id) {
                                SceneCard(scene: s)
                            }
                            .buttonStyle(.plain)
                            .id(s.id)
                            .background(scrollProbe(s.id))
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
                            .id(s.id)
                            .background(scrollProbe(s.id))
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
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(SceneVisibleOffsetKey.self) { dict in
                anchor.accept(dict)
            }
        }
    }

    /// 卡片背面的零尺寸探针：上报该短片相对滚动内容的纵坐标
    private func scrollProbe(_ id: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: SceneVisibleOffsetKey.self,
                value: [id: g.frame(in: .named(Self.scrollSpace)).minY]
            )
        }
    }
}

struct SceneCard: View {
    let scene: Scene

    var body: some View {
        // SenPlayer 风格：文字左对齐，标题加粗一行，下方仅年份
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(urlString: scene.paths?.screenshot ?? scene.paths?.webp, placeholderIcon: "film", smartCropAspect: 2.0 / 3.0)
                .aspectRatio(2 / 3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    // 海报右下角评分角标（半透明黑底白字，如 8.2），无评分不显示
                    if let r = scene.rating100 {
                        Text(String(format: "%.1f", Double(r) / 20.0))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
                }
            Text(scene.title ?? "（无标题）")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            if let d = scene.date {
                Text(String(d.prefix(4)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        }
        .padding(.vertical, 12)
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
            self.error = NetError.friendly(error)
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
            self.error = NetError.friendly(error)
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
                    .padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        imageColumn(s)
                            .frame(maxWidth: 360)
                        infoColumn(s)
                    }
                    .padding(20)
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
        VStack(alignment: .leading, spacing: 16) {
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

            // 信息行：工作室（value 型链接直推，目的地统一注册在栈根）
            if let st = s.studio {
                NavigationLink(value: StudioNavID(id: st.id, name: st.name)) {
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

            if let ps = s.performers, !ps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("演员").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8) {
                        ForEach(ps) { p in
                            NavigationLink(value: PerformerNavID(id: p.id, name: p.name)) {
                                Chip(text: p.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let ts = s.tags, !ts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标签").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 8) {
                        ForEach(ts) { t in
                            NavigationLink(value: TagNavID(id: t.id, name: t.name)) {
                                Chip(text: t.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let us = s.urls, !us.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
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
            if let ds = s.details, !ds.isEmpty {
                Text(ds)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
