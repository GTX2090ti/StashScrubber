import SwiftUI
import UIKit

// MARK: - 主题：苹果原生，不强制外观，跟随系统浅色/深色模式
// 配色一律使用系统语义色，强调色使用系统默认 accentColor

extension Color {
    /// 统一走系统强调色，保持原生观感
    static let appAccent = Color.accentColor
}

// MARK: - 远程图片（自动携带 Stash ApiKey 请求头）

struct RemoteImageView: View {
    let urlString: String?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(UIColor.tertiarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        guard let s = urlString, !s.isEmpty, let url = URL(string: s) else {
            failed = true
            return
        }
        var req = URLRequest(url: url)
        let key = AppSettings.shared.apiKey
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "ApiKey") }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let img = UIImage(data: data) { image = img } else { failed = true }
        } catch {
            failed = true
        }
    }
}

// MARK: - 流式布局（标签 / 演员名chips 自动换行）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .appAccent

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 多选选择器（演员 / 标签 / 工作室）

struct NamedOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct MultiSelectPicker: View {
    let title: String
    let options: [NamedOption]
    @Binding var selection: Set<String>
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection.isEmpty {
                    Text("未选择").foregroundStyle(.secondary)
                } else {
                    Text("已选 \(selection.count) 项").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showSheet) {
            MultiSelectSheet(title: title, options: options, selection: $selection)
        }
    }
}

struct MultiSelectSheet: View {
    let title: String
    let options: [NamedOption]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [NamedOption] {
        query.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { opt in
                    Button {
                        if selection.contains(opt.id) { selection.remove(opt.id) }
                        else { selection.insert(opt.id) }
                    } label: {
                        HStack {
                            Text(opt.name).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(opt.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 错误弹窗修饰器

struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "操作失败",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
