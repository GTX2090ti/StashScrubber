import SwiftUI

// MARK: - 图片列表

@MainActor
final class ImageListViewModel: ObservableObject {
    @Published var images: [StashImage] = []
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var total = 0
    private var page = 1
    private var lastQuery = ""

    var canLoadMore: Bool { images.count < total && total > 0 }

    func reload() async {
        page = 1
        lastQuery = query
        images = []
        await load()
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try AppSettings.shared.makeClient()
            let p = try await StashAPI.findImages(client, query: lastQuery, page: page)
            total = p.count
            if page == 1 { images = p.images } else { images += p.images }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImagesView: View {
    @StateObject private var vm = ImageListViewModel()
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("图片")
                .searchable(text: $vm.query, prompt: "搜索图片标题")
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
        if vm.loading && vm.images.isEmpty {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.images.isEmpty {
            EmptyStateView(title: "没有图片", hint: "下拉刷新，或检查服务器与过滤条件")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 12) {
                    ForEach(vm.images) { img in
                        NavigationLink(value: img.id) {
                            ImageCard(image: img)
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
                ImageDetailView(imageID: id)
            }
        }
    }
}

struct ImageCard: View {
    let image: StashImage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteImageView(urlString: image.paths?.thumbnail ?? image.paths?.image)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(image.title ?? "（无标题）")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 图片详情（查看 / 削刮 / 编辑）

struct ImageDetailView: View {
    let imageID: String

    @EnvironmentObject private var settings: AppSettings
    @State private var image: StashImage?
    @State private var error: String?
    @State private var showEdit = false
    @State private var showScrape = false

    var body: some View {
        Group {
            if let image {
                detail(image)
            } else if let error {
                EmptyStateView(title: "加载失败", hint: error)
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(image?.title ?? "图片")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: imageID) { await load() }
        .errorAlert($error)
        .sheet(isPresented: $showEdit) {
            if let image {
                ImageEditView(image: image) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showScrape) {
            if let image {
                ScrapeSheet(kind: .image, targetID: image.id, existing: ExistingMeta(image: image)) {
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
            image = try await StashAPI.image(client, id: imageID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func detail(_ i: StashImage) -> some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        RemoteImageView(urlString: i.paths?.image ?? i.paths?.thumbnail)
                            .frame(width: geo.size.width * 0.5)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        infoColumn(i)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        RemoteImageView(urlString: i.paths?.image ?? i.paths?.thumbnail)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        infoColumn(i)
                    }
                    .padding()
                }
            }
        }
    }

    private func infoColumn(_ i: StashImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(i.title ?? "（无标题）").font(.title2.weight(.bold))
            HStack(spacing: 14) {
                if let st = i.studio {
                    Label(st.name, systemImage: "building.2")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let d = i.date {
                    Label(d, systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let r = i.rating100 {
                    Label(String(format: "%.1f", Double(r) / 20.0), systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.yellow)
                }
            }
            if let ps = i.performers, !ps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("演员").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(ps) { p in Chip(text: p.name) }
                    }
                }
            }
            if let ts = i.tags, !ts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标签").font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(ts) { t in Chip(text: t.name) }
                    }
                }
            }
        }
    }
}
