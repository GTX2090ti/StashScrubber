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

    /// 图片会话（含 resource 总时长封顶）统一来自 NetTransport.image
    private static var session: URLSession { NetTransport.image }

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

    private func load() async {
        image = nil
        failed = false
        guard let url = resolvedURL() else {
            failed = true
            NetLog.shared.record(category: .image, level: .warn, title: "图片地址无效",
                                 url: urlString, message: "无法解析图片地址或当前档案未配置")
            return
        }
        var req = URLRequest(url: url)
        let key = AppSettings.shared.apiKey
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "ApiKey") }
        let t0 = Date()
        do {
            let (data, resp) = try await Self.session.data(for: req)
            let ms = Date().timeIntervalSince(t0) * 1000
            let status = (resp as? HTTPURLResponse)?.statusCode
            // Stash 对缺省图返回 SVG 占位（如工作室默认图）、异常时返回 HTML，
            // UIImage 无法解码这些格式 → 显示占位图标
            if let img = UIImage(data: data) {
                if NetLog.verboseImage {
                    NetLog.shared.record(category: .image, level: .info, title: "图片",
                                         method: "GET", url: url.absoluteString,
                                         status: status, ms: ms, bytes: data.count)
                }
                if let aspect = smartCropAspect {
                    // 智能裁剪移出主线程；Vision 请求在部分 iOS 26 设备上会挂死
                    //（ANECF 推理故障，重启 App 也无效），必须带超时熔断兜底
                    image = await SmartCrop.run(img, aspect: aspect)
                } else {
                    image = img
                }
            } else {
                failed = true
                NetLog.shared.record(category: .image, level: .warn, title: "图片无法解码",
                                     method: "GET", url: url.absoluteString,
                                     status: status, ms: ms, bytes: data.count,
                                     message: "返回内容不是可解码的位图（可能是 SVG 占位图或 HTML 错误页）")
            }
        } catch {
            // 视图复用 / 页面切换导致的任务取消：静默保持原状，不算失败，也不入日志
            if !NetError.isCancellation(error) {
                failed = true
                NetLog.shared.record(category: .image, level: .error, title: "图片下载失败",
                                     method: "GET", url: url.absoluteString,
                                     ms: Date().timeIntervalSince(t0) * 1000,
                                     message: NetError.friendly(error))
            }
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
private final class ResumeOnce {
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

    static func run(_ img: UIImage, aspect: CGFloat) async -> UIImage {
        lock.lock()
        let skip = broken
        lock.unlock()
        if skip { return img.fallbackCropped(toAspect: aspect) }

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
                    lock.lock()
                    broken = true
                    lock.unlock()
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
