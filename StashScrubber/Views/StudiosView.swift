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

/// 记录列表「顶部可见工作室」：从详情页返回时据此恢复原位（与短片 / 演员页同策略）
final class StudioScrollAnchor {
    var topID: String?
}

/// 收集各工作室卡片在滚动容器内的纵坐标，用于推算顶部可见项
private struct StudioVisibleOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct StudiosView: View {
    @StateObject private var vm = StudioListViewModel()
    @EnvironmentObject private var settings: AppSettings
    /// 显式导航路径：用于感知「从详情返回列表根」，从而恢复滚动位置
    @State private var path = NavigationPath()
    @State private var anchor = StudioScrollAnchor()
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
                content
                    .navigationTitle("工作室")
                    .searchable(text: $vm.query, prompt: "搜索工作室名称")
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
                updateTopVisible(dict)
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

    /// 从详情返回时滚回进入前的顶部工作室（关掉动画，避免「先回顶部再滑下来」的闪动）
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let id = anchor.topID,
              vm.studios.contains(where: { $0.id == id }) else { return }
        // 等一拍：返回后的布局尚未落定，立刻 scrollTo 会被忽略
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(id, anchor: .top) }
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
