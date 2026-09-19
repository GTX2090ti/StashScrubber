import SwiftUI

// MARK: - 通用削刮面板：三种削刮方式 × 三种目标类型，复用一套 UI
//
// 真机 schema 实测（2026-09-19）：
//  - listScrapers(types: [ScrapeContentType!])，枚举无 STUDIO → 工作室削刮仅支持 stash-box 源
//  - scrapeSingleScene/Studio/Performer 位于 Query 根，源 = 本地刮削器（scraper_id）或 Stash-box（stash_box_index）
//  - queryScrape*Query 关键词削刮不存在 → 「名称削刮」统一走 scrapeSingle*（input.query）
//
// 方式：
//  1) 片段削刮 —— 本地刮削器以当前条目的现有信息为上下文削刮
//  2) 名称削刮 —— 输入名称，经 Stash-box / 支持名称削刮的本地刮削器搜索
//  3) URL 削刮 —— 粘贴详情页 URL，由匹配的刮削器削刮
// 结果进入预览页比对后确认写回。

struct ScrapeSheet: View {
    enum Mode: String, Identifiable {
        case fragment = "片段削刮"
        case query = "名称削刮"
        case url = "URL 削刮"
        var id: String { rawValue }
    }

    let kind: ScrapeKind
    let targetID: String
    let existing: ExistingMeta
    var onApplied: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .fragment
    @State private var localScrapers: [Scraper] = []
    @State private var boxes: [StashBoxInfo] = []
    @State private var urlText = ""
    @State private var queryText = ""
    @State private var results: [ScrapedItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var picked: ScrapedItem?
    @State private var didApply = false

    /// 本套 Stash：工作室削刮仅支持 stash-box 按名称，无片段/URL 方式
    private var availableModes: [Mode] {
        switch kind {
        case .scene, .performer: return [.fragment, .query, .url]
        case .studio: return [.query]
        }
    }

    /// 削刮源（本地刮削器 / stash-box），dict 直接作为 ScraperSourceInput
    private struct Source: Identifiable {
        let id: String
        let name: String
        let dict: [String: Any]
    }

    private var fragmentSources: [Source] {
        localScrapers.filter { $0.supportsFragment }.map {
            Source(id: "sc-\($0.id)", name: $0.name, dict: ["scraper_id": $0.id])
        }
    }

    private var querySources: [Source] {
        var s = boxes.enumerated().map { i, b in
            Source(id: "box-\(i)", name: (b.name ?? "Stash-box") + "（Stash-box）",
                   dict: ["stash_box_index": i])
        }
        if kind != .studio {
            s += localScrapers.filter { $0.supportsName }.map {
                Source(id: "sc-\($0.id)", name: $0.name, dict: ["scraper_id": $0.id])
            }
        }
        return s
    }

    var body: some View {
        NavigationStack {
            List {
                if availableModes.count > 1 {
                    Section {
                        Picker("方式", selection: $mode) {
                            ForEach(availableModes) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _ in results = [] }
                    } header: {
                        Text("削刮\(kind.title)")
                    }
                }

                switch mode {
                case .fragment:
                    sourceSection(
                        fragmentSources,
                        header: "选择刮削器（按当前信息削刮）",
                        emptyText: fragmentSources.isEmpty ? "服务端未返回支持片段削刮的本地刮削器" : nil,
                        footer: "以当前条目的已有字段作为片段上下文发给刮削器。",
                        needsQueryText: false
                    ) { src in
                        Task { await scrapeFragment(with: src) }
                    }

                case .query:
                    Section {
                        TextField("输入\(kind.title)名称关键词", text: $queryText)
                    }
                    sourceSection(
                        querySources,
                        header: "选择削刮源（按名称搜索）",
                        emptyText: querySources.isEmpty ? "未找到可用削刮源（无 Stash-box 且无本地刮削器）" : nil,
                        footer: "Stash-box（StashDB / ThePornDB 等）按名称全局搜索；本地刮削器需声明支持名称削刮。",
                        needsQueryText: true
                    ) { src in
                        Task { await scrapeQuery(with: src) }
                    }

                case .url:
                    Section {
                        TextField("https://example.com/xxx", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await scrapeURL() }
                        } label: {
                            Label("开始削刮", systemImage: "sparkle.magnifyingglass")
                        }
                        .disabled(urlText.isEmpty || loading)
                    } footer: {
                        Text("需要刮削器支持 URL 类型削刮。")
                    }
                }

                if loading {
                    Section {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("正在削刮…")
                        }
                    }
                }

                if !results.isEmpty {
                    Section("削刮结果（\(results.count) 条，点击查看并应用）") {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                            Button {
                                picked = item
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImageView(urlString: item.imageURLString)
                                        .frame(width: 64, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let sub = item.subtitle {
                                            Text(sub).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("元数据削刮")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { mode = availableModes.contains(mode) ? mode : availableModes[0] }
            .task { await loadSources() }
            .errorAlert($error)
            .sheet(item: $picked) { item in
                ScrapePreview(
                    item: item,
                    kind: kind,
                    targetID: targetID,
                    existing: existing
                ) {
                    didApply = true
                    dismiss()
                    onApplied()
                }
            }
        }
    }

    private func sourceSection(
        _ sources: [Source],
        header: String,
        emptyText: String?,
        footer: String,
        needsQueryText: Bool,
        action: @escaping (Source) -> Void
    ) -> some View {
        Section {
            if let emptyText, !loading {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(sources) { src in
                Button {
                    action(src)
                } label: {
                    HStack {
                        Text(src.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("削刮")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .disabled(loading || (needsQueryText && queryText.isEmpty))
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    private func loadSources() async {
        guard localScrapers.isEmpty && boxes.isEmpty else { return }
        do {
            let client = try settings.makeClient()
            Scraper.kindContext = kind
            localScrapers = (try? await StashAPI.scrapers(client, kind: kind)) ?? []
            boxes = (try? await StashAPI.stashBoxes(client)) ?? []
        } catch {
            // 源加载失败不阻塞 URL 方式
            self.error = "削刮源加载失败：\(error.localizedDescription)"
        }
    }

    private func run(_ body: (GraphQLClient) async throws -> [ScrapedItem]) async {
        loading = true
        error = nil
        results = []
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            let items = try await body(client)
            results = items
            if items.isEmpty {
                error = "没有削刮到结果。可换一个削刮源重试，或确认服务端刮削器可用（查看 Stash 日志）。"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scrapeFragment(with src: Source) async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneFragment(client, source: src.dict, sceneId: targetID)
                    .map { ScrapedItem.scene($0) }
            case .studio:
                return []   // 本套 Stash 工作室无片段削刮
            case .performer:
                return try await StashAPI.scrapePerformerFragment(client, source: src.dict, performerId: targetID)
                    .map { ScrapedItem.performer($0) }
            }
        }
    }

    private func scrapeQuery(with src: Source) async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneByName(client, source: src.dict, query: queryText)
                    .map { ScrapedItem.scene($0) }
            case .studio:
                return try await StashAPI.scrapeStudio(client, source: src.dict, query: queryText)
                    .map { ScrapedItem.studio($0) }
            case .performer:
                return try await StashAPI.scrapePerformerByName(client, source: src.dict, query: queryText)
                    .map { ScrapedItem.performer($0) }
            }
        }
    }

    private func scrapeURL() async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneURL(client, url: urlText).map { ScrapedItem.scene($0) }
            case .studio:
                return []   // 本套 Stash 工作室无 URL 削刮
            case .performer:
                return try await StashAPI.scrapePerformerURL(client, url: urlText).map { ScrapedItem.performer($0) }
            }
        }
    }
}

// MARK: - 削刮结果预览与写回

struct ScrapePreview: View {
    let item: ScrapedItem
    let kind: ScrapeKind
    let targetID: String
    let existing: ExistingMeta
    var onApplied: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var applying = false
    @State private var error: String?

    private var rows: [(label: String, current: String?, new: String?)] {
        func join(_ a: [String]) -> String? { a.isEmpty ? nil : a.joined(separator: "、") }
        switch item {
        case .scene(let s):
            return [
                ("标题", existing.title, s.title),
                ("日期", existing.date, s.date),
                ("工作室", existing.studio, s.studio?.name),
                ("简介", existing.details, s.details),
                ("演员", join(existing.performers), s.performers.flatMap { ps in
                    ps.compactMap(\.name).isEmpty ? nil : ps.compactMap(\.name).joined(separator: "、")
                }),
                ("标签", join(existing.tags), s.tags.flatMap { ts in
                    ts.compactMap(\.name).isEmpty ? nil : ts.compactMap(\.name).joined(separator: "、")
                }),
                ("URL", existing.urls.joined(separator: " "), s.urls?.joined(separator: " ")),
            ]
        case .studio(let st):
            return [
                ("名称", existing.title, st.name),
                ("简介", existing.details, st.details),
                ("别名", nil, st.aliases),
                ("URL", existing.urls.joined(separator: " "), st.urls.flatMap { us in
                    us.filter { !$0.isEmpty }.isEmpty ? nil : us.filter { !$0.isEmpty }.joined(separator: " ")
                }),
                ("标签", join(existing.tags), st.tags.flatMap { ts in
                    ts.compactMap(\.name).isEmpty ? nil : ts.compactMap(\.name).joined(separator: "、")
                }),
            ]
        case .performer(let p):
            let career = [p.careerStart, p.careerEnd].compactMap { $0 }
                .joined(separator: " - ")
            return [
                ("名称", existing.title, p.name),
                ("区别名", nil, p.disambiguation),
                ("出生日期", existing.birthdate, p.birthdate),
                ("国籍", existing.country, p.country),
                ("族裔", nil, p.ethnicity),
                ("三围", nil, p.measurements),
                ("从业年限", nil, career.isEmpty ? nil : career),
                ("简介", existing.details, p.details),
                ("标签", join(existing.tags), p.tags.flatMap { ts in
                    ts.compactMap(\.name).isEmpty ? nil : ts.compactMap(\.name).joined(separator: "、")
                }),
            ]
        }
    }

    private var changedRows: [(label: String, current: String?, new: String?)] {
        rows.filter { row in
            guard let new = row.new, !new.isEmpty else { return false }
            return new != row.current
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let img = item.imageURLString {
                    Section {
                        RemoteImageView(urlString: img)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    ForEach(changedRows, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let cur = row.current, !cur.isEmpty {
                                Text(cur)
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                    .strikethrough()
                                    .lineLimit(2)
                            }
                            Text(row.new ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("将写入 \(changedRows.count) 个字段")
                } footer: {
                    Text("空字段不会写入，库内不存在的演员/标签/工作室将自动创建。")
                }
            }
            .navigationTitle("削刮结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if applying {
                        ProgressView()
                    } else {
                        Button("应用并写回") {
                            Task { await apply() }
                        }
                        .disabled(changedRows.isEmpty)
                    }
                }
            }
            .errorAlert($error)
        }
    }

    private func apply() async {
        applying = true
        defer { applying = false }
        do {
            let client = try settings.makeClient()
            _ = try await StashAPI.applyScraped(client, item: item, targetID: targetID)
            onApplied()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
