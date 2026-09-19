import SwiftUI

// MARK: - 标签列表

@MainActor
final class TagListViewModel: ObservableObject {
    @Published var tags: [Tag] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    private var page = 1
    private var lastQuery = ""

    var canLoadMore: Bool { tags.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        tags = []
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findTags(client, query: lastQuery, page: page)
            total = p.count
            if page == 1 { tags = p.tags } else { tags += p.tags }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TagsView: View {
    @StateObject private var vm = TagListViewModel()
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("标签")
                .searchable(text: $vm.query, prompt: "搜索标签名称")
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
        if vm.loading && vm.tags.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.tags.isEmpty {
            EmptyStateView(title: "没有标签", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 14) {
                    ForEach(vm.tags) { t in
                        NavigationLink(value: t.id) {
                            TagCard(tag: t)
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
                TagDetailView(tagID: id, tagName: tagName(from: id))
            }
        }
    }

    /// 导航需要名称，从已加载列表取；取不到时详情页会自行兜底
    private func tagName(from id: String) -> String {
        vm.tags.first { $0.id == id }?.name ?? "标签"
    }
}

struct TagCard: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            Text(tag.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - 标签详情（标签信息 + 带此标签的场景）

struct TagDetailView: View {
    let tagID: String
    let tagName: String

    @EnvironmentObject private var settings: AppSettings
    @State private var scenes: [Scene] = []
    @State private var sceneCount = 0
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if loading && scenes.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, scenes.isEmpty {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .foregroundStyle(Color.appAccent)
                            Text(tagName)
                                .font(.title2.weight(.bold))
                        }
                        .padding(.horizontal)

                        // 带此标签的场景：与场景列表一致的卡片网格
                        VStack(alignment: .leading, spacing: 10) {
                            Text("相关场景（\(sceneCount)）")
                                .font(.subheadline.weight(.semibold))
                            if scenes.isEmpty {
                                Text("没有关联场景")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 14) {
                                    ForEach(scenes) { sc in
                                        NavigationLink(value: sc.id) {
                                            SceneCard(scene: sc)
                                        }
                                        .buttonStyle(.plain)
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
            }
        }
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tagID) { await reload() }
        .errorAlert($error)
        .navigationDestination(for: String.self) { id in
            SceneDetailView(sceneID: id)
        }
    }

    private func reload() async {
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
            self.error = error.localizedDescription
        }
    }
}
