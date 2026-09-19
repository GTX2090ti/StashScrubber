import SwiftUI

// MARK: - 工作室列表

@MainActor
final class StudioListViewModel: ObservableObject {
    @Published var studios: [Studio] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    private var page = 1
    private var lastQuery = ""

    var canLoadMore: Bool { studios.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        studios = []
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findStudios(client, query: lastQuery, page: page)
            total = p.count
            if page == 1 { studios = p.studios } else { studios += p.studios }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StudiosView: View {
    @StateObject private var vm = StudioListViewModel()
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("工作室")
                .searchable(text: $vm.query, prompt: "搜索工作室名称")
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
        if vm.loading && vm.studios.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.studios.isEmpty {
            EmptyStateView(title: "没有工作室", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 14) {
                    ForEach(vm.studios) { st in
                        NavigationLink(value: st.id) {
                            StudioCard(studio: st)
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
                StudioDetailView(studioID: id)
            }
        }
    }
}

struct StudioCard: View {
    let studio: Studio

    var body: some View {
        VStack(spacing: 6) {
            RemoteImageView(urlString: studio.imagePath)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(studio.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 工作室详情（查看 / 削刮 / 编辑）

struct StudioDetailView: View {
    let studioID: String

    @EnvironmentObject private var settings: AppSettings
    @State private var studio: Studio?
    @State private var scenes: [Scene] = []
    @State private var sceneCount = 0
    @State private var error: String?
    @State private var showEdit = false
    @State private var showScrape = false

    var body: some View {
        Group {
            if let studio {
                detail(studio)
            } else if let error {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(studio?.name ?? "工作室")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: studioID) { await load() }
        .errorAlert($error)
        .sheet(isPresented: $showEdit) {
            if let studio {
                StudioEditView(studio: studio) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showScrape) {
            if let studio {
                ScrapeSheet(kind: .studio, targetID: studio.id, existing: ExistingMeta(studio: studio)) {
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
            studio = try await StashAPI.studio(client, id: studioID)
            let sp = try await StashAPI.findScenesByStudio(client, studioId: studioID)
            sceneCount = sp.count
            scenes = sp.scenes
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func detail(_ s: Studio) -> some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        imageColumn(s)
                            .frame(width: geo.size.width * 0.32)
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

    private func imageColumn(_ s: Studio) -> some View {
        RemoteImageView(urlString: s.imagePath)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoColumn(_ s: Studio) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(s.name)
                .font(.title2.weight(.bold))
            if let r = s.rating100 {
                Label(String(format: "%.1f", Double(r) / 20.0), systemImage: "star.fill")
                    .font(.subheadline).foregroundStyle(.yellow)
            }
            if let u = s.url, !u.isEmpty, let url = URL(string: u) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL").font(.subheadline.weight(.semibold))
                    Link(u, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let ds = s.details, !ds.isEmpty {
                Text(ds)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let ts = s.tags, !ts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标签").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(ts) { t in Chip(text: t.name) }
                    }
                }
            }
            // 相关场景：与场景详情一致的卡片网格
            VStack(alignment: .leading, spacing: 10) {
                Text("相关场景（\(sceneCount)）").font(.subheadline.weight(.semibold))
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
        }
        .navigationDestination(for: String.self) { id in
            SceneDetailView(sceneID: id)
        }
    }
}

// MARK: - 工作室元数据编辑

struct StudioEditView: View {
    let studio: Studio
    var onSaved: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taxonomy = TaxonomyStore()

    @State private var name = ""
    @State private var url = ""
    @State private var details = ""
    @State private var rating: Double = 0
    @State private var tagIds: Set<String> = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading) {
                        HStack {
                            Text("评分")
                            Spacer()
                            Text(rating > 0 ? String(format: "%.1f / 5.0", rating / 20) : "未评分")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $rating, in: 0...100, step: 5)
                    }
                }
                Section("简介") {
                    TextEditor(text: $details)
                        .frame(minHeight: 100)
                }
                Section {
                    MultiSelectPicker(title: "标签", options: taxonomy.tags, selection: $tagIds)
                }
            }
            .navigationTitle("编辑工作室")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
            .task {
                name = studio.name
                url = studio.url ?? ""
                details = studio.details ?? ""
                rating = Double(studio.rating100 ?? 0)
                tagIds = Set(studio.tags?.map(\.id) ?? [])
                if let client = try? settings.makeClient() {
                    await taxonomy.load(client: client)
                }
            }
            .errorAlert($error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let client = try settings.makeClient()
            let input = StudioUpdateInput(
                id: studio.id,
                name: name.isEmpty ? nil : name,
                url: url.isEmpty ? nil : url,
                details: details.isEmpty ? nil : details,
                rating100: rating > 0 ? Int(rating) : 0,
                tagIds: Array(tagIds)
            )
            try await StashAPI.updateStudio(client, input: input)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
