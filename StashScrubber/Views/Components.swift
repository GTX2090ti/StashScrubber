import SwiftUI
import UIKit
import Vision

// MARK: - 主题：苹果原生，不强制外观，跟随系统浅色/深色模式
// 配色一律使用系统语义色，强调色使用系统默认 accentColor

extension Color {
    /// 统一走系统强调色，保持原生观感
    static let appAccent = Color.accentColor
}

// MARK: - 远程图片（自动携带 Stash ApiKey 请求头）

struct RemoteImageView: View {
    let urlString: String?
    var placeholderIcon: String = "photo"
    /// 非 nil 时按该宽高比（如 2/3）对原图做智能裁剪：Vision 显著性找焦点，窗口对齐焦点
    var smartCropAspect: CGFloat? = nil
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
                Image(systemName: placeholderIcon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: urlString) { await load() }
    }

    /// 服务端返回的图片是绝对地址（指向 Stash 本机 / 内网 IP）。
    /// 当主机与当前档案不一致（例如外网反代档案）时，重写为「当前档案基址 + 原路径与查询参数」，
    /// 保证内外网档案都能正确加载图片。重写规则统一在 StashEndpoint。
    private func resolvedURL() -> URL? {
        guard let s = urlString, !s.isEmpty else { return nil }
        return StashEndpoint.rewriteImage(s, base: AppSettings.shared.serverURL)
    }

    /// 取图统一走 ImageCache（内存 → 磁盘 → 网络），命中缓存不再发起请求；
    /// 智能裁剪结果同样被缓存，滚动时不会反复跑 Vision。
    /// 下载、解码失败的日志由 ImageCache 统一记录。
    private func load() async {
        image = nil
        failed = false
        guard let url = resolvedURL() else {
            failed = true
            NetLog.shared.record(category: .image, level: .warn, title: "图片地址无效",
                                 url: urlString, message: "无法解析图片地址或当前档案未配置")
            return
        }
        if let cached = ImageCache.shared.memoryImage(for: url, cropAspect: smartCropAspect) {
            image = cached   // 内存命中：同步落位，滚动时不闪加载圈
            return
        }
        let img = await ImageCache.shared.image(for: url,
                                                apiKey: AppSettings.shared.apiKey,
                                                cropAspect: smartCropAspect)
        // 视图被复用/页面切走导致的任务取消：结果作废，不要覆盖新任务的加载态
        if Task.isCancelled { return }
        if let img {
            image = img
        } else {
            failed = true
        }
    }
}

// MARK: - 智能裁剪（横版截图 -> 竖版海报时自动选取主体区域）

extension UIImage {
    /// 按目标宽高比裁剪：Vision 注意力显著性检测定位主体焦点，裁剪窗口对齐焦点；
    /// 检测失败时回退：横图略偏上居中（人物头部常在上方），竖图居中。
    func smartCropped(toAspect aspect: CGFloat) -> UIImage {
        guard let cg = cgImage, imageOrientation == .up else { return self }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let currentAspect = w / h
        if abs(currentAspect - aspect) < 0.02 { return self }

        let cropW: CGFloat, cropH: CGFloat
        if currentAspect > aspect {   // 原图偏宽（16:9 -> 2:3）：窗口窄高，占满高
            cropH = h
            cropW = h * aspect
        } else {                      // 原图偏高：窗口宽扁，占满宽
            cropW = w
            cropH = w / aspect
        }

        // 默认焦点：横图偏上（45% 高度处），竖图居中
        var fx = w / 2
        var fy = currentAspect > aspect ? h * 0.45 : h / 2

        // Vision 显著性检测：取第一个显著区域中心作为焦点（归一化坐标原点在左下，需翻转 Y）
        if let obs = saliencyFocus() {
            fx = obs.midX * w
            fy = (1 - obs.midY) * h
        }

        let ox = min(max(fx - cropW / 2, 0), w - cropW)
        let oy = min(max(fy - cropH / 2, 0), h - cropH)
        let rect = CGRect(x: ox, y: oy, width: cropW, height: cropH)
        if let cropped = cg.cropping(to: rect) {
            return UIImage(cgImage: cropped, scale: scale, orientation: .up)
        }
        return self
    }

    /// 兜底裁剪：不用 Vision，横图窗口取偏上（人物头部常在上方 45% 处），竖图居中
    func fallbackCropped(toAspect aspect: CGFloat) -> UIImage {
        guard let cg = cgImage else { return self }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let currentAspect = w / h
        if abs(currentAspect - aspect) < 0.02 { return self }
        let cropW: CGFloat, cropH: CGFloat
        if currentAspect > aspect {
            cropH = h
            cropW = h * aspect
        } else {
            cropW = w
            cropH = w / aspect
        }
        let ox = (w - cropW) / 2
        let oy = currentAspect > aspect ? (h - cropH) * 0.25 : (h - cropH) / 2
        let rect = CGRect(x: ox, y: oy, width: cropW, height: cropH)
        if let cropped = cg.cropping(to: rect) {
            return UIImage(cgImage: cropped, scale: scale, orientation: .up)
        }
        return self
    }

    /// 注意力显著性焦点（归一化 midX/midY，Vision 坐标系），无结果返回 nil
    private func saliencyFocus() -> CGRect? {
        guard let cg = cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNSaliencyImageObservation,
                  let box = obs.salientObjects?.first?.boundingBox else { return nil }
            return box
        } catch {
            return nil
        }
    }
}

// MARK: - 智能裁剪门面（超时熔断，保证图片必定出图）

/// 原子一次性领取：保证续体只被 resume 一次（Vision 线程与超时回调赛跑）
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    /// 返回 true 表示领取成功（可且仅可 resume 一次）
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

enum SmartCrop {
    private static let lock = NSLock()
    /// 熔断标记：显著性请求一旦超时，判定该设备 Vision 推理不可用（iOS 26 ANECF 已知问题），后续全部走兜底
    private static var broken = false

    /// 用 withLock 访问：NSLock 的 lock()/unlock() 在异步上下文被标为 noasync（Swift 6 下为错误）
    private static var isBroken: Bool { lock.withLock { broken } }
    private static func markBroken() { lock.withLock { broken = true } }

    static func run(_ img: UIImage, aspect: CGFloat) async -> UIImage {
        if isBroken { return img.fallbackCropped(toAspect: aspect) }

        // 注意：不能用 TaskGroup 赛跑——组退出会隐式等待挂死的 Vision 子任务，超时失效。
        // 改用续体 + 原子领取：超时回调先到先得，挂死任务被遗弃（broken 熔断后不再新增）。
        return await withCheckedContinuation { cont in
            let once = ResumeOnce()
            Task.detached(priority: .userInitiated) {
                let r = img.smartCropped(toAspect: aspect)
                if once.claim() { cont.resume(returning: r) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                if once.claim() {
                    markBroken()
                    cont.resume(returning: img.fallbackCropped(toAspect: aspect))
                }
            }
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

    /// 取消噪音：导航 / 切标签页取消 .task 时 URLSession 报 cancelled，不是真错误
    private static func isNoise(_ m: String) -> Bool {
        let low = m.lowercased()
        return low == "cancelled" || low.contains("已取消")
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { message != nil && !Self.isNoise(message ?? "") },
                    set: { if !$0 { message = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .onChange(of: message) { m in
                // 噪音消息直接清掉，避免堵住后续真错误的弹窗
                if let m, Self.isNoise(m) { message = nil }
            }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

// MARK: - 空状态 / 加载失败

struct EmptyStateView: View {
    let title: String
    let hint: String
    /// 可选：给空状态加一个重试入口（网络异常时比「下拉刷新」提示更直接）
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

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
            if let retryTitle, let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// 加载卡住 / 超时：中置提示 + 重试按钮。
/// 用于替代「永久转圈」——网络层卡死时用户至少知道发生了什么并能自救。
struct LoadRetryView: View {
    let title: String
    let hint: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                retry()
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
