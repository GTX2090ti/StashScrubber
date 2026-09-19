import SwiftUI

// MARK: - 分类数据（工作室 / 演员 / 标签 全量缓存，编辑表单共用）

@MainActor
final class TaxonomyStore: ObservableObject {
    @Published var studios: [NamedOption] = []
    @Published var performers: [NamedOption] = []
    @Published var tags: [NamedOption] = []

    func load(client: GraphQLClient) async {
        do {
            async let s = StashAPI.allStudios(client)
            async let p = StashAPI.allPerformers(client)
            async let t = StashAPI.allTags(client)
            studios = (try await s).map { NamedOption(id: $0.id, name: $0.name) }
            performers = (try await p).map { NamedOption(id: $0.id, name: $0.name) }
            tags = (try await t).map { NamedOption(id: $0.id, name: $0.name) }
        } catch {
            // 分类加载失败时表单仍可编辑文本字段
        }
    }
}

// MARK: - 场景元数据编辑

struct SceneEditView: View {
    let scene: Scene
    var onSaved: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taxonomy = TaxonomyStore()

    @State private var title = ""
    @State private var details = ""
    @State private var date = ""
    @State private var rating: Double = 0
    @State private var studioId = ""
    @State private var performerIds: Set<String> = []
    @State private var tagIds: Set<String> = []
    @State private var urlsText = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    TextField("日期（yyyy-MM-dd）", text: $date)
                        .keyboardType(.numbersAndPunctuation)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("评分")
                            Spacer()
                            if rating > 0 {
                                Text(String(format: "%.1f / 5.0", rating / 20))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未评分").foregroundStyle(.secondary)
                            }
                        }
                        Slider(value: $rating, in: 0...100, step: 5)
                    }
                }
                Section("简介") {
                    TextEditor(text: $details)
                        .frame(minHeight: 100)
                }
                Section("工作室") {
                    Picker("工作室", selection: $studioId) {
                        Text("无").tag("")
                        ForEach(taxonomy.studios) { st in
                            Text(st.name).tag(st.id)
                        }
                    }
                }
                Section {
                    MultiSelectPicker(title: "演员", options: taxonomy.performers, selection: $performerIds)
                    MultiSelectPicker(title: "标签", options: taxonomy.tags, selection: $tagIds)
                }
                Section {
                    TextEditor(text: $urlsText)
                        .frame(minHeight: 60)
                        .font(.footnote)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("URL（每行一个）")
                }
            }
            .navigationTitle("编辑场景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await save() } }
                    }
                }
            }
            .task {
                title = scene.title ?? ""
                details = scene.details ?? ""
                date = scene.date ?? ""
                rating = Double(scene.rating100 ?? 0)
                studioId = scene.studio?.id ?? ""
                performerIds = Set(scene.performers?.map(\.id) ?? [])
                tagIds = Set(scene.tags?.map(\.id) ?? [])
                urlsText = (scene.urls ?? []).joined(separator: "\n")
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
            let urls = urlsText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            var input = SceneUpdateInput(
                id: scene.id,
                title: title.isEmpty ? nil : title,
                details: details.isEmpty ? nil : details,
                date: date.isEmpty ? nil : date,
                rating100: rating > 0 ? Int(rating) : nil,
                studioId: studioId.isEmpty ? nil : studioId,
                performerIds: Array(performerIds),
                tagIds: Array(tagIds),
                urls: urls.isEmpty ? nil : urls
            )
            try await StashAPI.updateScene(client, input: input)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 图片元数据编辑

struct ImageEditView: View {
    let image: StashImage
    var onSaved: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taxonomy = TaxonomyStore()

    @State private var title = ""
    @State private var date = ""
    @State private var rating: Double = 0
    @State private var studioId = ""
    @State private var performerIds: Set<String> = []
    @State private var tagIds: Set<String> = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    TextField("日期（yyyy-MM-dd）", text: $date)
                        .keyboardType(.numbersAndPunctuation)
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
                Section("工作室") {
                    Picker("工作室", selection: $studioId) {
                        Text("无").tag("")
                        ForEach(taxonomy.studios) { st in
                            Text(st.name).tag(st.id)
                        }
                    }
                }
                Section {
                    MultiSelectPicker(title: "演员", options: taxonomy.performers, selection: $performerIds)
                    MultiSelectPicker(title: "标签", options: taxonomy.tags, selection: $tagIds)
                }
            }
            .navigationTitle("编辑图片")
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
                title = image.title ?? ""
                date = image.date ?? ""
                rating = Double(image.rating100 ?? 0)
                studioId = image.studio?.id ?? ""
                performerIds = Set(image.performers?.map(\.id) ?? [])
                tagIds = Set(image.tags?.map(\.id) ?? [])
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
            let input = ImageUpdateInput(
                id: image.id,
                title: title.isEmpty ? nil : title,
                date: date.isEmpty ? nil : date,
                rating100: rating > 0 ? Int(rating) : 0,
                studioId: studioId.isEmpty ? nil : studioId,
                performerIds: Array(performerIds),
                tagIds: Array(tagIds)
            )
            try await StashAPI.updateImage(client, input: input)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 演员元数据编辑

struct PerformerEditView: View {
    let performer: Performer
    var onSaved: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taxonomy = TaxonomyStore()

    @State private var name = ""
    @State private var disambiguation = ""
    @State private var birthdate = ""
    @State private var country = ""
    @State private var ethnicity = ""
    @State private var measurements = ""
    @State private var careerLength = ""
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
                    TextField("区别名", text: $disambiguation)
                    TextField("出生日期（yyyy-MM-dd）", text: $birthdate)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("国籍", text: $country)
                    HStack {
                        Text("评分")
                        Spacer()
                        Text(rating > 0 ? String(format: "%.1f / 5.0", rating / 20) : "未评分")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $rating, in: 0...100, step: 5)
                }
                Section("档案") {
                    TextField("族裔", text: $ethnicity)
                    TextField("三围", text: $measurements)
                    TextField("从业年限（如 2015-2020）", text: $careerLength)
                    TextEditor(text: $details)
                        .frame(minHeight: 80)
                }
                Section {
                    MultiSelectPicker(title: "标签", options: taxonomy.tags, selection: $tagIds)
                }
            }
            .navigationTitle("编辑演员")
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
                name = performer.name
                disambiguation = performer.disambiguation ?? ""
                birthdate = performer.birthdate ?? ""
                country = performer.country ?? ""
                ethnicity = performer.ethnicity ?? ""
                measurements = performer.measurements ?? ""
                careerLength = performer.careerLength ?? ""
                details = performer.details ?? ""
                rating = Double(performer.rating100 ?? 0)
                tagIds = Set(performer.tags?.map(\.id) ?? [])
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
            let input = PerformerUpdateInput(
                id: performer.id,
                name: name.isEmpty ? nil : name,
                disambiguation: disambiguation.isEmpty ? nil : disambiguation,
                birthdate: birthdate.isEmpty ? nil : birthdate,
                details: details.isEmpty ? nil : details,
                country: country.isEmpty ? nil : country,
                ethnicity: ethnicity.isEmpty ? nil : ethnicity,
                measurements: measurements.isEmpty ? nil : measurements,
                careerLength: careerLength.isEmpty ? nil : careerLength,
                rating100: rating > 0 ? Int(rating) : 0,
                tagIds: Array(tagIds)
            )
            try await StashAPI.updatePerformer(client, input: input)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
