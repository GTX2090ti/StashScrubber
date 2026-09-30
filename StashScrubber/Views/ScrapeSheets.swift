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

    private var availableModes: [Mode] {
        switch kind {
        case .scene, .performer: return [.fragment, .query, .url]
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
        s += localScrapers.filter { $0.supportsName }.map {
            Source(id: "sc-\($0.id)", name: $0.name, dict: ["scraper_id": $0.id])
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
                        .onChange(of: mode) { newMode in
                            results = []
                            error = nil
                            // 切回片段方式时自动重新削刮
                            if newMode == .fragment { Task { await scrapeAllFragment() } }
                        }
                    } header: {
                        Text("削刮\(kind.title)")
                    }
                }

                switch mode {
                case .fragment:
                    // 片段削刮：不再显示刮削器列表，自动对所有支持片段削刮的源并发削刮
                    EmptyView()

                case .query:
                    Section {
                        TextField("输入\(kind.title)名称关键词", text: $queryText)
                            .onSubmit { Task { await scrapeAllQuery() } }
                        Button {
                            Task { await scrapeAllQuery() }
                        } label: {
                            Label("开始削刮（自动遍历所有削刮源）", systemImage: "sparkle.magnifyingglass")
                        }
                        .disabled(queryText.isEmpty || loading)
                    } footer: {
                        Text("自动对 Stash-box 与所有支持名称削刮的本地刮削器并发搜索，结果合并展示。")
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
                            Text(loadingText)
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
                if mode == .fragment, !results.isEmpty, !loading {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await scrapeAllFragment() }
                        } label: {
                            Label("重新削刮", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear { mode = availableModes.contains(mode) ? mode : availableModes[0] }
            .task {
                await loadSources()
                // 面板打开即自动开始片段削刮，不再让用户先选刮削器
                if mode == .fragment { await scrapeAllFragment() }
            }
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

    /// 加载中的提示文案（显示正在遍历几个源）
    private var loadingText: String {
        switch mode {
        case .fragment:
            return fragmentSources.isEmpty ? "正在削刮…" : "正在从 \(fragmentSources.count) 个削刮源获取…"
        case .query:
            return querySources.isEmpty ? "正在削刮…" : "正在从 \(querySources.count) 个削刮源搜索…"
        case .url:
            return "正在削刮…"
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
            self.error = "削刮源加载失败：" + NetError.friendly(error)
        }
    }

    /// 自动遍历所有削刮源并发削刮，成功结果合并展示；单个源失败不阻塞其他源
    private func runAll(
        sources: [Source],
        scrapeOne: @escaping (GraphQLClient, Source) async throws -> [ScrapedItem]
    ) async {
        loading = true
        error = nil
        results = []
        defer { loading = false }

        guard !sources.isEmpty else {
            error = "未找到可用削刮源，请先在 Stash 中配置刮削器或 Stash-box。"
            return
        }
        do {
            let client = try settings.makeClient()
            var collected: [ScrapedItem] = []
            var failures = 0
            await withTaskGroup(of: Result<[ScrapedItem], Error>.self) { group in
                for src in sources {
                    group.addTask {
                        do {
                            return .success(try await scrapeOne(client, src))
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                for await res in group {
                    switch res {
                    case .success(let items): collected.append(contentsOf: items)
                    case .failure: failures += 1
                    }
                }
            }
            results = collected
            if collected.isEmpty {
                error = failures == sources.count
                    ? "所有削刮源均失败，请查看 Stash 服务端日志或网络日志。"
                    : "没有削刮到结果。"
            }
        } catch {
            self.error = NetError.friendly(error)
        }
    }

    /// 片段削刮：自动对所有支持片段削刮的本地刮削器并发执行
    private func scrapeAllFragment() async {
        await runAll(sources: fragmentSources, scrapeOne: { client, src in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneFragment(client, source: src.dict, sceneId: targetID)
                    .map { ScrapedItem.scene($0) }
            case .performer:
                return try await StashAPI.scrapePerformerFragment(client, source: src.dict, performerId: targetID)
                    .map { ScrapedItem.performer($0) }
            }
        })
    }

    /// 名称削刮：自动对所有削刮源（Stash-box + 本地刮削器）并发搜索
    private func scrapeAllQuery() async {
        await runAll(sources: querySources, scrapeOne: { client, src in
            switch kind {
            case .scene:
                return try await StashAPI.scrapeSceneByName(client, source: src.dict, query: queryText)
                    .map { ScrapedItem.scene($0) }
            case .performer:
                return try await StashAPI.scrapePerformerByName(client, source: src.dict, query: queryText)
                    .map { ScrapedItem.performer($0) }
            }
        })
    }

    private func scrapeURL() async {
        loading = true
        error = nil
        results = []
        defer { loading = false }
        do {
            let client = try settings.makeClient()
            let items: [ScrapedItem]
            switch kind {
            case .scene:
                items = try await StashAPI.scrapeSceneURL(client, url: urlText).map { ScrapedItem.scene($0) }
            case .performer:
                items = try await StashAPI.scrapePerformerURL(client, url: urlText).map { ScrapedItem.performer($0) }
            }
            results = items
            if items.isEmpty {
                error = "没有削刮到结果。"
            }
        } catch {
            self.error = NetError.friendly(error)
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
    @State private var includeImage = true

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
                        if item.rawImageRef != nil {
                            Toggle("同时应用图片", isOn: $includeImage)
                        }
                    }
                } else if item.rawImageRef != nil {
                    Section {
                        Toggle("同时应用图片（base64 图源无法预览）", isOn: $includeImage)
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
                    Text("空字段不会写入，库内不存在的演员/标签/工作室将自动创建。开启「应用图片」时会把刮削到的图片下载后转为 base64 写入（短片→封面，演员→头像），下载失败不影响其余字段。")
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
                        .disabled(changedRows.isEmpty && !(includeImage && item.rawImageRef != nil))
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
            _ = try await StashAPI.applyScraped(client, item: item, targetID: targetID, includeImage: includeImage)
            onApplied()
        } catch {
            self.error = NetError.friendly(error)
        }
    }
}
