import SwiftUI

// MARK: - 场景筛选面板（布局与交互对齐 Stash WebUI 筛选器）

struct SceneFilterSheet: View {
    @Binding var state: SceneFilterState
    var onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var taxonomy = TaxonomyStore()
    @State private var draft = SceneFilterState()

    private let resolutions: [(String, String)] = [
        ("VERY_LOW", "非常低"), ("LOW", "低"), ("R360P", "360p"),
        ("STANDARD", "标准 (SD)"), ("WEB_HD", "Web HD (540p)"), ("STANDARD_HD", "720p"),
        ("FULL_HD", "1080p"), ("QUAD_HD", "1440p"), ("FOUR_K", "4K")
    ]

    // [String] ↔ Set<String> 桥接（复用 MultiSelectPicker）
    private var studioBinding: Binding<Set<String>> {
        Binding(get: { Set(draft.studioIDs) }, set: { draft.studioIDs = Array($0).sorted() })
    }
    private var performerBinding: Binding<Set<String>> {
        Binding(get: { Set(draft.performerIDs) }, set: { draft.performerIDs = Array($0).sorted() })
    }
    private var tagBinding: Binding<Set<String>> {
        Binding(get: { Set(draft.tagIDs) }, set: { draft.tagIDs = Array($0).sorted() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("工作室") {
                    MultiSelectPicker(
                        title: "选择工作室（可多选）",
                        options: taxonomy.studios,
                        selection: studioBinding
                    )
                }

                Section("演员") {
                    MultiSelectPicker(
                        title: "选择演员（可多选）",
                        options: taxonomy.performers,
                        selection: performerBinding
                    )
                }

                Section {
                    MultiSelectPicker(
                        title: "选择标签（可多选）",
                        options: taxonomy.tags,
                        selection: tagBinding
                    )
                    Picker("匹配方式", selection: $draft.tagIncludeAll) {
                        Text("任一标签").tag(false)
                        Text("全部标签").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("标签")
                }

                Section("数值条件") {
                    Picker("评分至少", selection: $draft.minRating100) {
                        Text("不限").tag(Int?.none)
                        ForEach([20, 40, 60, 80, 100], id: \.self) { v in
                            Text("\(v / 20) 星").tag(Int?.some(v))
                        }
                    }
                    Picker("已整理", selection: $draft.organized) {
                        Text("不限").tag(Int?.none)
                        Text("仅已整理").tag(Int?.some(1))
                        Text("仅未整理").tag(Int?.some(0))
                    }
                    HStack {
                        Text("O 计数至少")
                        Spacer()
                        TextField(
                            "不限",
                            text: Binding(
                                get: { draft.minOCounter.map(String.init) ?? "" },
                                set: { draft.minOCounter = Int($0) }
                            )
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    }
                    HStack {
                        Text("时长至少（分钟）")
                        Spacer()
                        TextField(
                            "不限",
                            text: Binding(
                                get: { draft.minDuration.map { String($0 / 60) } ?? "" },
                                set: { draft.minDuration = Int($0).map { $0 * 60 } }
                            )
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    }
                    Picker("分辨率不低于", selection: $draft.resolution) {
                        Text("不限").tag(String?.none)
                        ForEach(resolutions, id: \.0) { r in
                            Text(r.1).tag(String?.some(r.0))
                        }
                    }
                }

                Section("日期范围（yyyy-MM-dd）") {
                    TextField("起始日期", text: $draft.dateFrom)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("结束日期", text: $draft.dateTo)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section {
                    Button(role: .destructive) {
                        draft = SceneFilterState()
                    } label: {
                        Label("清除全部条件", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("筛选场景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        state = draft
                        onApply()
                        dismiss()
                    }
                }
            }
            .task {
                draft = state
                if let client = try? AppSettings.shared.makeClient() {
                    await taxonomy.load(client: client)
                }
            }
        }
    }
}
