import SwiftUI

// MARK: - 工作室列表（浏览全部工作室）

@MainActor
final class StudioListViewModel: ObservableObject {
    @Published var studios: [Studio] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    /// 加载卡住（网络层未按期返回）：显示重试入口，避免页面永久转圈
    @Published var timedOut = false

    private var page = 1
    private var lastQuery = ""
    /// 请求代号：reload 时自增，迟到的旧响应据此丢弃，不覆盖新结果
    private var generation = 0
    /// 看门狗秒数：超过即认为网络层卡死（API 硬超时 25s + 解析余量）
    static let watchdogSeconds: Double = 30

    var canLoadMore: Bool { studios.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        studios = []
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
        // 只有「当前代号」的请求结束才复位 loading
        defer { if gen == generation { loading = false } }

        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timedOut = true
        }
        defer { watchdog.cancel() }

        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findStudios(client, query: lastQuery, page: page)
            guard gen == generation else { return }   // 过期响应：丢弃
            timedOut = false
            total = p.count
            if page == 1 { studios = p.studios } else { studios += p.studios }
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

/// 收集各工作室卡片在滚动容器内的纵坐标，用于推算顶部可见项
/// （锚点与恢复逻辑见 Views/ScrollRestore.swift 的 ScrollMemory）
private struct StudioVisibleOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct StudiosView: View {
    @StateObject private var vm = StudioListViewModel()
    @EnvironmentObject private var settings: AppSettings
    var refreshTick: Int = 0
    /// 显式导航路径：用于感知「从详情返回列表根」，从而恢复滚动位置
    @State private var path = NavigationPath()
    @State private var anchor = ScrollMemory()
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// 滚动容器坐标空间名（用于取各卡片相对滚动内容的纵坐标）
    private static let scrollSpace = "studios.scroll"

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
                    .navigationTitle("工作室")
                    .searchable(text: $vm.query, prompt: "搜索工作室名称")
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
                            anchor.restore(proxy) { id in vm.studios.contains { $0.id == id } }
                        }
                    }
                    .onDisappear { anchor.freeze() }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            anchor.restore(proxy) { id in vm.studios.contains { $0.id == id } }
                        }
                    }
                    // 分页「加载更多」：请求期间冻结锚点、数据落地后守住位置 ——
                    // 追加数据会让 SwiftUI 重置偏移（表现：点一下「加载更多」就跳回最上面）
                    .onChange(of: vm.loading) { loading in
                        if loading {
                            anchor.freeze()
                        } else {
                            anchor.restore(proxy, holdSeconds: 0.6) { id in vm.studios.contains { $0.id == id } }
                        }
                    }
            }
            // 导航目的地统一注册在栈根，勿下移到条件分支里（否则列表数据刷新时可能短暂失效）
            .navigationDestination(for: StudioNavID.self) { st in
                StudioDetailView(studioID: st.id, studioName: st.name)
            }
            .navigationDestination(for: String.self) { id in
                SceneDetailView(sceneID: id)
            }
            .navigationDestination(for: TagNavID.self) { t in
                TagDetailView(tagID: t.id, tagName: t.name)
            }
            .navigationDestination(for: PerformerNavID.self) { pv in
                PerformerDetailView(performerID: pv.id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.studios.isEmpty {
            if vm.timedOut {
                LoadRetryView(
                    title: "加载超时",
                    hint: "请求超过 \(Int(StudioListViewModel.watchdogSeconds)) 秒仍未返回，可能是网络切换或连接卡住。\n可重试，或到 设置 → 网络 查看网络日志。"
                ) {
                    Task { await vm.reload() }
                }
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if vm.studios.isEmpty {
            EmptyStateView(title: "没有工作室", hint: "下拉刷新，或换个关键词试试",
                           retryTitle: "重试") { Task { await vm.reload() } }
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(vm.studios) { st in
                        NavigationLink(value: StudioNavID(id: st.id, name: st.name)) {
                            StudioCard(studio: st)
                        }
                        .buttonStyle(.plain)
                        .id(st.id)
                        .background(scrollProbe(st.id))
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
            .onPreferenceChange(StudioVisibleOffsetKey.self) { dict in
                anchor.accept(dict)
            }
        }
    }

    /// 卡片背面的零尺寸探针：上报该工作室卡片相对滚动内容的纵坐标
    private func scrollProbe(_ id: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(
                key: StudioVisibleOffsetKey.self,
                value: [id: g.frame(in: .named(Self.scrollSpace)).minY]
            )
        }
    }
}

/// 工作室卡片：正方形 Logo + 名称 + 短片数（沿用短片页的文字左对齐风格）
struct StudioCard: View {
    let studio: Studio

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(urlString: studio.imagePath,
                            placeholderIcon: "building.2",
                            smartCropAspect: 1.0)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if let r = studio.rating100 {
                        Text(String(format: "%.1f", Double(r) / 20.0))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
                }
            Text(studio.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            if let c = studio.sceneCount, c > 0 {
                Text("\(c) 部短片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
