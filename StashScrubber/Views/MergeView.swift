import SwiftUI

// MARK: - 短片合并（服务端原生 sceneMerge）

struct MergeSceneSheet: View {
    let target: Scene
    var onMerged: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scenes: [Scene] = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var merging = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索短片标题", text: $query)
                        .onSubmit { Task { await search() } }
                    if !selected.isEmpty {
                        Text("已选 \(selected.count) 个源短片")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("选择要并入「\(target.title ?? "当前短片")」的短片（可多选）。合并后演员/标签/文件等取并集，源短片条目删除（视频文件挂到本片），播放与 O 记录一并合并。")
                }

                if loading {
                    Section { ProgressView() }
                } else {
                    Section {
                        ForEach(scenes) { s in
                            Button {
                                if selected.contains(s.id) { selected.remove(s.id) }
                                else { selected.insert(s.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImageView(urlString: s.paths?.screenshot ?? s.paths?.webp)
                                        .frame(width: 64, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title ?? "（无标题）")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let d = s.date {
                                            Text(d).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(s.id) ? Color.accentColor : Color.secondary)
                                }
                            }
                        }
                        if scenes.isEmpty {
                            Text("没有匹配的短片")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("合并短片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if merging {
                        ProgressView()
                    } else {
                        Button("合并（\(selected.count)）") { Task { await merge() } }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .task { await search() }
            .errorAlert($error)
        }
        .presentationDetents([.large])
    }

    private func search() async {
        loading = true
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            let p = try await StashAPI.findScenes(client, query: query, sort: "title", direction: "ASC")
            scenes = p.scenes.filter { $0.id != target.id }
        } catch {
            self.error = NetError.friendly(error)
        }
    }

    private func merge() async {
        merging = true
        defer { merging = false }
        do {
            let client = try settings.makeClient()
            try await StashAPI.mergeScenes(client, sourceIds: Array(selected), destinationId: target.id)
            onMerged()
            dismiss()
        } catch {
            self.error = NetError.friendly(error)
        }
    }
}
