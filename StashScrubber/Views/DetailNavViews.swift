import SwiftUI

/// 与 ScenesView 主列表一致的网格列：iPhone（compact）固定 3 列；iPad（regular）自适应列宽约 140pt
func detailSceneGridColumns(_ hSizeClass: UserInterfaceSizeClass?) -> [GridItem] {
    if hSizeClass == .regular {
        return [GridItem(.adaptive(minimum: 140), spacing: 12)]
    }
    return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
}

// MARK: - 标签详情（短片详情点击标签跳转；进入前已校验标签存在）

struct TagDetailView: View {
    let tagID: String
    let tagName: String

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSizeClass
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

                        VStack(alignment: .leading, spacing: 10) {
                            Text("相关短片（\(sceneCount)）")
                                .font(.subheadline.weight(.semibold))
                            if scenes.isEmpty {
                                Text("没有关联短片")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            } else {
                                LazyVGrid(columns: detailSceneGridColumns(hSizeClass), spacing: 14) {
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
        .errorAlert($error)    }

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

// MARK: - 工作室详情（短片详情点击工作室跳转；进入前已校验存在）

struct StudioDetailView: View {
    let studioID: String
    let studioName: String

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var studio: Studio?
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
                            Image(systemName: "building.2")
                                .foregroundStyle(Color.appAccent)
                            Text(studio?.name ?? studioName)
                                .font(.title2.weight(.bold))
                        }
                        .padding(.horizontal)

                        if let s = studio {
                            VStack(alignment: .leading, spacing: 10) {
                                if let r = s.rating100 {
                                    Label(String(format: "%.1f", Double(r) / 20.0), systemImage: "star.fill")
                                        .font(.subheadline).foregroundStyle(.yellow)
                                }
                                if let u = s.url, !u.isEmpty, let url = URL(string: u) {
                                    Link(u, destination: url)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                if let ds = s.details, !ds.isEmpty {
                                    Text(ds)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.horizontal)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("相关短片（\(sceneCount)）")
                                .font(.subheadline.weight(.semibold))
                            if scenes.isEmpty {
                                Text("没有关联短片")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            } else {
                                LazyVGrid(columns: detailSceneGridColumns(hSizeClass), spacing: 14) {
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
        .navigationTitle(studio?.name ?? studioName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: studioID) { await reload() }
        .errorAlert($error)    }

    private func reload() async {
        scenes = []
        studio = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            if studio == nil {
                studio = try await StashAPI.findStudioByID(client, id: studioID)
            }
            let page = scenes.count / 24 + 1
            let p = try await StashAPI.findScenesByStudio(client, studioId: studioID, page: page)
            sceneCount = p.count
            scenes += p.scenes
        } catch {
            self.error = error.localizedDescription
        }
    }
}
