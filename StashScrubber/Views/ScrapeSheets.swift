import SwiftUI

// MARK: - 通用削刮面板：三种削刮方式 × 三种目标类型，复用一套 UI
//
// 方式：
//  1) 片段削刮 —— 选择服务端刮削器，以当前条目的现有信息为上下文削刮
//  2) URL 削刮 —— 粘贴详情页 URL，由匹配的刮削器削刮
//  3) 关键词削刮 —— 输入名称，跨刮削器搜索候选
// 结果进入预览页比对后确认写回。

struct ScrapeSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case fragment = "片段削刮"
        case url = "URL 削刮"
        case query = "关键词削刮"
        var id: String { rawValue }
    }

    let kind: ScrapeKind
    let targetID: String
    let existing: ExistingMeta
    var onApplied: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .fragment
    @State private var scrapers: [Scraper] = []
    @State private var urlText = ""
    @State private var queryText = ""
    @State private var results: [ScrapedItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var picked: ScrapedItem?
    @State private var didApply = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("方式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in results = [] }
                } header: {
                    Text("削刮\(kind.title)")
                }

                switch mode {
                case .fragment:
                    scraperSection

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

                case .query:
                    Section {
                        TextField("输入\(kind.title)名称关键词", text: $queryText)
                            .onSubmit { Task { await scrapeQuery() } }
                        Button {
                            Task { await scrapeQuery() }
                        } label: {
                            Label("搜索削刮", systemImage: "magnifyingglass")
                        }
                        .disabled(queryText.isEmpty || loading)
                    } footer: {
                        Text("将对支持名称削刮的刮削器发起搜索。")
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
            .task { await loadScrapers() }
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

    private var scraperSection: some View {
        Section {
            if scrapers.isEmpty && !loading {
                Text("服务端未返回支持片段削刮的刮削器")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(scrapers.filter { $0.supportsFragment }) { sc in
                Button {
                    Task { await scrapeFragment(with: sc) }
                } label: {
                    HStack {
                        Text(sc.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("削刮")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .disabled(loading)
            }
        } header: {
            Text("选择刮削器（按当前信息削刮）")
        } footer: {
            Text("以当前条目的已有字段作为片段上下文发给刮削器。")
        }
    }

    private func loadScrapers() async {
        guard scrapers.isEmpty else { return }
        do {
            let client = try settings.makeClient()
            Scraper.kindContext = kind
            scrapers = try await StashAPI.scrapers(client, kind: kind)
        } catch {
            // 刮削器列表加载失败不阻塞 URL / 关键词方式
            self.error = "刮削器列表加载失败：\(error.localizedDescription)"
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
                error = "没有削刮到结果。请确认服务端刮削器可用（查看 Stash 日志）。"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scrapeFragment(with sc: Scraper) async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneFragment(client, scraperId: sc.id, sceneId: targetID)
                    .map { ScrapedItem.scene($0) }
            case .image:
                return try await StashAPI.scrapeImageFragment(client, scraperId: sc.id, imageId: targetID)
                    .map { ScrapedItem.image($0) }
            case .performer:
                return try await StashAPI.scrapePerformerFragment(client, scraperId: sc.id, performerId: targetID)
                    .map { ScrapedItem.performer($0) }
            }
        }
    }

    private func scrapeURL() async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneURL(client, url: urlText).map { ScrapedItem.scene($0) }
            case .image:
                throw StashAPIError.server(["图片暂不支持 URL 削刮，请使用片段削刮或关键词削刮方式"])
            case .performer:
                return try await StashAPI.scrapePerformerURL(client, url: urlText).map { ScrapedItem.performer($0) }
            }
        }
    }

    private func scrapeQuery() async {
        await run { client in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneQuery(client, query: queryText).map { ScrapedItem.scene($0) }
            case .image:
                return try await StashAPI.scrapeImageQuery(client, query: queryText).map { ScrapedItem.image($0) }
            case .performer:
                return try await StashAPI.scrapePerformerQuery(client, query: queryText).map { ScrapedItem.performer($0) }
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
        case .image(let i):
            return [
                ("标题", existing.title, i.title),
                ("日期", existing.date, i.date),
                ("工作室", existing.studio, i.studio?.name),
                ("演员", join(existing.performers), i.performers.flatMap { ps in
                    ps.compactMap(\.name).isEmpty ? nil : ps.compactMap(\.name).joined(separator: "、")
                }),
                ("标签", join(existing.tags), i.tags.flatMap { ts in
                    ts.compactMap(\.name).isEmpty ? nil : ts.compactMap(\.name).joined(separator: "、")
                }),
            ]
        case .performer(let p):
            return [
                ("名称", existing.title, p.name),
                ("区别名", nil, p.disambiguation),
                ("出生日期", existing.birthdate, p.birthdate),
                ("国籍", existing.country, p.country),
                ("族裔", nil, p.ethnicity),
                ("三围", nil, p.measurements),
                ("从业年限", nil, p.careerLength),
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
