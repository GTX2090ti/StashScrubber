import Foundation
import UIKit
import Combine
import CryptoKit

// MARK: - 图片缓存（内存 + 磁盘两级，带容量上限）
//
// 此前图片一律走 ephemeral 会话直连下载，滚动列表反复重拉同一张图 —— 弱网下就是满屏转圈。
// 本缓存补上两级存储：
//   1. 内存层 NSCache<UIImage>：按像素字节计费，系统内存吃紧时自动释放
//   2. 磁盘层 Caches/StashImageCache：存「原始下载字节」，容量上限可配，超限按最久未使用淘汰
//
// 设计取舍：
// - 键：重写后的图片 URL 全串（不同档案主机不同 → 缓存天然按档案隔离）
// - 智能裁剪结果只进内存层（按 原键 + 宽高比 区分），复用同一张海报不必反复跑 Vision
// - 关闭缓存 = 不读也不写（等同无缓存），UI 已注明
// - 同键并发请求合并为一次网络下载（in-flight 去重）；失败项 20 秒内不重试，避免滚动刷屏

final class ImageCache: ObservableObject, @unchecked Sendable {

    static let shared = ImageCache()

    // MARK: 配置项（UserDefaults 键，设置页通过 @AppStorage 绑定）

    static let enabledKey = "stash.imageCacheEnabled"
    static let limitMBKey = "stash.imageCacheLimitMB"
    /// 默认磁盘上限 300MB
    static let defaultLimitMB = 300
    /// 可选档位；0 表示不限制
    static let limitOptions: [Int] = [0, 100, 300, 500, 1024, 2048]

    static func limitLabel(_ mb: Int) -> String {
        if mb <= 0 { return "不限制" }
        if mb >= 1024 { return "\(mb / 1024) GB" }
        return "\(mb) MB"
    }

    /// 未写入过任何值时视为开启（bool(forKey:) 对缺失键返回 false，会误判为关闭）
    static var isEnabled: Bool {
        guard let v = UserDefaults.standard.object(forKey: enabledKey) as? Bool else { return true }
        return v
    }

    static var limitBytes: Int64 {
        let mb = (UserDefaults.standard.object(forKey: limitMBKey) as? Int) ?? defaultLimitMB
        return mb <= 0 ? 0 : Int64(mb) * 1_048_576
    }

    // MARK: 状态（设置页展示）

    @Published private(set) var diskBytes: Int64 = 0
    @Published private(set) var diskCount: Int = 0

    // MARK: 存储层

    /// 内存层：cost 为解码后的像素字节数，系统内存紧张时由 NSCache 自行回收
    private let mem: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        let budget = Int(ProcessInfo.processInfo.physicalMemory / 16)
        c.totalCostLimit = min(max(budget, 32 * 1_048_576), 128 * 1_048_576)
        c.countLimit = 500
        c.evictsObjectsWithDiscardedContent = true
        return c
    }()

    private let io = DispatchQueue(label: "stash.imagecache.io", qos: .utility)

    /// 磁盘目录（init 中确定并建好，避免 lazy 首次访问的并发重复创建）
    private let dir: URL

    // MARK: 并发控制

    private let flightLock = NSLock()
    private var inflight: [String: Task<DownloadOutcome, Never>] = [:]
    /// 失败冷却：弱网时网格内几十张图同时失败会反复重试，拖住网络
    private var failedAt: [String: Date] = [:]
    private static let failureCooldown: TimeInterval = 20

    /// 仅在 io 队列访问
    private var bytesSinceTrim: Int64 = 0
    private var lastTrimAt = Date.distantPast

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("StashImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
        io.async { [weak self] in
            self?.trim()   // 启动时清一次历史超限缓存
        }
    }

    // MARK: - 取图（内存 → 磁盘 → 网络）

    /// 同步内存查询：列表滚动时先同步取一次，命中即落位，避免 ProgressView 闪一帧。
    /// 需要裁剪时只接受「裁剪结果」缓存（返回未裁剪原图会导致画面跳变）。
    func memoryImage(for url: URL, cropAspect: CGFloat?) -> UIImage? {
        guard Self.isEnabled else { return nil }
        let key = Self.fileName(for: url.absoluteString)
        if let aspect = cropAspect {
            let derivedKey = key + "@" + String(format: "%.3f", Double(aspect))
            return mem.object(forKey: derivedKey as NSString)
        }
        return mem.object(forKey: key as NSString)
    }

    /// 取图主入口。返回 nil 表示最终失败（失败详情已进网络日志）。
    /// - Parameter cropAspect: 非 nil 时返回按该宽高比智能裁剪后的图（结果缓存在内存层）
    func image(for url: URL, apiKey: String, cropAspect: CGFloat? = nil) async -> UIImage? {
        let key = Self.fileName(for: url.absoluteString)
        let derivedKey = cropAspect.map { key + "@" + String(format: "%.3f", Double($0)) }

        if Self.isEnabled {
            // 1) 裁剪结果命中（滚动时最省：Vision 完全不跑）
            if let derivedKey, let img = mem.object(forKey: derivedKey as NSString) { return img }
            // 2) 原图内存命中
            if let img = mem.object(forKey: key as NSString) { return await derive(img, key: derivedKey, aspect: cropAspect) }
            // 3) 磁盘命中
            if let data = await readData(key: key) {
                if let img = UIImage(data: data) {
                    store(img, cost: Self.cost(of: img), key: key)
                    return await derive(img, key: derivedKey, aspect: cropAspect)
                }
                // 坏文件（下载中断 / 非位图）：删掉，避免每次都读到同一份坏数据
                io.async { try? FileManager.default.removeItem(at: self.dir.appendingPathComponent(key)) }
            }
        }

        // 4) 网络
        if inFailureCooldown(key) { return nil }
        let outcome = await fetchData(url: url, apiKey: apiKey, key: key)
        guard let data = outcome.data else {
            // 取消（视图滚走 / 页面切换）不吃冷却；真实失败才进冷却，避免反复重拉坏图
            if outcome.error != nil { markFailure(key) }
            return nil
        }
        guard let img = UIImage(data: data) else {
            // Stash 对缺省图返回 SVG 占位（如工作室 / 演员默认图）——属预期情况，记 info 不刷错误
            let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
            let isSVG = head.contains("<svg") || (head.contains("<?xml") && head.contains("svg"))
            let isHTML = head.contains("<!doctype html") || head.contains("<html")
            NetLog.shared.record(category: .image,
                                 level: isSVG ? .info : .warn,
                                 title: isSVG ? "SVG 占位图（该条目无封面）" : "图片无法解码",
                                 method: "GET", url: url.absoluteString, bytes: data.count,
                                 message: isSVG
                                     ? "Stash 返回 SVG 占位图，无实际封面"
                                     : (isHTML
                                        ? "返回的是 HTML 错误页（对端可能不是 Stash / 反代图片路径未放行）"
                                        : "返回内容不是可解码的位图"))
            // 非占位的解码失败同样进冷却：否则每次滚动都会重拉同一张坏图
            if !isSVG { markFailure(key) }
            return nil
        }
        clearFailure(key)
        if Self.isEnabled {
            store(img, cost: Self.cost(of: img), key: key)
            writeToDisk(data: data, key: key)
        }
        return await derive(img, key: derivedKey, aspect: cropAspect)
    }

    /// 智能裁剪（Vision 慢且在部分 iOS 26 设备会挂死，故结果只算一次并缓存）
    private func derive(_ img: UIImage, key: String?, aspect: CGFloat?) async -> UIImage {
        guard let aspect else { return img }
        let out = await SmartCrop.run(img, aspect: aspect)
        if let key, Self.isEnabled {
            mem.setObject(out, forKey: key as NSString, cost: Self.cost(of: out))
        }
        return out
    }

    // MARK: - 网络（同键合并 + 失败冷却）

    /// 下载结果：data 为 nil 时 error 非空表示真实失败（HTTP 错误 / 非图片 / 网络异常），
    /// error 为空表示仅是被取消（调用方不应计入冷却）
    private struct DownloadOutcome {
        var data: Data?
        var error: String?
    }

    private func fetchData(url: URL, apiKey: String, key: String) async -> DownloadOutcome {
        let task = flightTask(url: url, apiKey: apiKey, key: key)
        return await task.value
    }

    private func flightTask(url: URL, apiKey: String, key: String) -> Task<DownloadOutcome, Never> {
        flightLock.lock()
        if let t = inflight[key] {
            flightLock.unlock()
            return t
        }
        let t = Task<DownloadOutcome, Never> { [weak self] in
            let outcome = await Self.download(url: url, apiKey: apiKey)
            _ = self?.finishFlight(key)
            return outcome
        }
        inflight[key] = t
        flightLock.unlock()
        return t
    }

    private func finishFlight(_ key: String) {
        flightLock.lock()
        inflight[key] = nil
        flightLock.unlock()
    }

    private func inFailureCooldown(_ key: String) -> Bool {
        flightLock.lock()
        defer { flightLock.unlock() }
        guard let t = failedAt[key] else { return false }
        return Date().timeIntervalSince(t) < Self.failureCooldown
    }

    private func markFailure(_ key: String) {
        flightLock.lock()
        failedAt[key] = Date()
        if failedAt.count > 400 { failedAt.removeAll() }
        flightLock.unlock()
    }

    private func clearFailure(_ key: String) {
        flightLock.lock()
        failedAt[key] = nil
        flightLock.unlock()
    }

    private static func download(url: URL, apiKey: String) async -> DownloadOutcome {
        var req = URLRequest(url: url)
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        let request = req   // 交给 @Sendable 闭包前转不可变副本
        let t0 = Date()
        do {
            // 硬超时兜底：图片会话的 URLSession 超时同样可能失灵（连接池被吊死），
            // 35s 封底确保网格不会有一张图永远转圈；到点重建图片会话丢掉吊死连接。
            let r = try await NetCall.deadline(35, op: "图片下载", onTimeout: {
                NetTransport.resetImage(reason: "图片下载硬超时，重建图片会话丢弃吊死连接")
            }) {
                let (d, resp) = try await NetTransport.image.data(for: request)
                let http = resp as? HTTPURLResponse
                return NetHTTPResult(
                    data: d,
                    status: http?.statusCode,
                    contentType: http?.value(forHTTPHeaderField: "Content-Type")?.lowercased()
                )
            }
            let data = r.data
            let status = r.status
            let ct = r.contentType ?? ""
            let ms = Date().timeIntervalSince(t0) * 1000

            // 状态码校验：非 2xx 一律失败。此前不校验，500 错误页会被当成功数据往下传。
            if let code = status, !(200...299).contains(code) {
                let msg = "HTTP \(code)"
                NetLog.shared.record(category: .image, level: .error, title: "图片下载失败",
                                     method: "GET", url: url.absoluteString, status: code,
                                     ms: ms, bytes: data.count, message: msg)
                return DownloadOutcome(data: nil, error: msg)
            }
            // Content-Type 校验：Stash / 反代在异常时会以 200 返回 HTML 错误页，
            // 这类响应必须在下载阶段就被判失败（进冷却），否则每次滚动都重拉同一张坏图。
            if !ct.isEmpty, !ct.contains("image") {
                let msg = "返回的不是图片（Content-Type: \(ct)，\(NetLog.byteText(data.count))）"
                NetLog.shared.record(category: .image, level: .error, title: "图片下载失败",
                                     method: "GET", url: url.absoluteString, status: status,
                                     ms: ms, bytes: data.count, message: msg)
                return DownloadOutcome(data: nil, error: msg)
            }
            if NetLog.verboseImage {
                NetLog.shared.record(category: .image, level: .info, title: "图片下载",
                                     method: "GET", url: url.absoluteString,
                                     status: status, ms: ms, bytes: data.count,
                                     message: ct.isEmpty ? nil : ct)
            }
            return DownloadOutcome(data: data, error: nil)
        } catch {
            // 视图复用 / 页面切换导致的取消：静默，不入日志、不冷却
            if NetError.isCancellation(error) {
                return DownloadOutcome(data: nil, error: nil)
            }
            let msg = NetError.friendly(error)
            NetLog.shared.record(category: .image, level: .error, title: "图片下载失败",
                                 method: "GET", url: url.absoluteString,
                                 ms: Date().timeIntervalSince(t0) * 1000,
                                 message: msg)
            return DownloadOutcome(data: nil, error: msg)
        }
    }

    // MARK: - 写入

    private func store(_ img: UIImage, cost: Int, key: String) {
        guard Self.isEnabled else { return }
        mem.setObject(img, forKey: key as NSString, cost: cost)
    }

    private func writeToDisk(data: Data, key: String) {
        io.async {
            let url = self.dir.appendingPathComponent(key)
            try? data.write(to: url, options: [.atomic])
            self.bytesSinceTrim += Int64(data.count)
            // 节流：频繁滚动时不每张都全目录扫描，累计够量或间隔够久才修剪
            if self.bytesSinceTrim > 4 * 1_048_576 || Date().timeIntervalSince(self.lastTrimAt) > 10 {
                self.trim()
            }
        }
    }

    // MARK: - 磁盘读取

    private func readData(key: String) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            io.async {
                let url = self.dir.appendingPathComponent(key)
                guard let data = try? Data(contentsOf: url) else {
                    cont.resume(returning: nil)
                    return
                }
                self.touch(url)
                cont.resume(returning: data)
            }
        }
    }

    /// LRU 触摸：距上次修改超过 6 小时才刷新 mtime，避免每次读取都写元数据
    private func touch(_ url: URL) {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let d = v.contentModificationDate,
              Date().timeIntervalSince(d) > 6 * 3600 else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    // MARK: - 容量控制

    /// 限容修剪：超出上限时按「最久未使用」删除，淘汰到上限的 85%（留余量，避免每次写入都触发删除）
    /// - Note: 必须在 io 队列调用
    private func trim() {
        bytesSinceTrim = 0
        lastTrimAt = Date()

        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []

        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for u in items where u.pathExtension == "img" {
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = Int64(v?.fileSize ?? 0)
            total += size
            entries.append((u, size, v?.contentModificationDate ?? .distantPast))
        }

        let limit = Self.limitBytes
        var remaining = entries.count
        if limit > 0, total > limit {
            let target = Int64(Double(limit) * 0.85)
            for e in entries.sorted(by: { $0.date < $1.date }) {
                if total <= target { break }
                try? fm.removeItem(at: e.url)
                total -= e.size
                remaining -= 1
            }
        }
        publish(bytes: total, count: remaining)
    }

    private func publish(bytes: Int64, count: Int) {
        DispatchQueue.main.async {
            self.diskBytes = bytes
            self.diskCount = count
        }
    }

    /// 重新统计占用（设置页出现 / 上限变更后调用）
    func refreshUsage() {
        io.async {
            let fm = FileManager.default
            let items = (try? fm.contentsOfDirectory(
                at: self.dir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles])) ?? []
            var total: Int64 = 0
            var n = 0
            for u in items where u.pathExtension == "img" {
                let v = try? u.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(v?.fileSize ?? 0)
                n += 1
            }
            self.publish(bytes: total, count: n)
        }
    }

    /// 上限变更后立即按新上限修剪
    func trimNow() {
        io.async { self.trim() }
    }

    /// 清空两级缓存
    func clear() {
        mem.removeAllObjects()
        flightLock.lock()
        failedAt.removeAll()
        flightLock.unlock()
        io.async {
            let fm = FileManager.default
            let items = (try? fm.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
            for u in items { try? fm.removeItem(at: u) }
            self.publish(bytes: 0, count: 0)
        }
    }

    // MARK: - 工具

    /// 解码后位图的字节数（内存计费依据）
    static func cost(of img: UIImage) -> Int {
        if let cg = img.cgImage { return cg.bytesPerRow * cg.height }
        let s = img.scale
        return Int(img.size.width * s) * Int(img.size.height * s) * 4
    }

    /// 磁盘文件名：URL 全串的 SHA256 前 40 位 + .img
    static func fileName(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(40)) + ".img"
    }
}
