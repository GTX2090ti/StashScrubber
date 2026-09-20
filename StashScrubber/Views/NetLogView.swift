import SwiftUI
import UIKit

// MARK: - 网络日志页
//
// 记录每一次 GraphQL 请求、图片下载、WiFi 探测与切换动作的网络层结果，
// 支持按分类/关键字筛选、逐条或整体复制、清空。
// 日志保存在内存中（上限 600 条），App 重启后清空。

struct NetLogView: View {
    @ObservedObject private var log = NetLog.shared

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case errors = "错误"
        case graphql = "GraphQL"
        case image = "图片"
        case wifi = "WiFi"
        case diag = "诊断"
        case auth = "登录"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var keyword = ""
    @State private var copied: String?
    @State private var confirmClear = false
    @State private var expanded: Set<UUID> = []
    @AppStorage(NetLog.verboseImageKey) private var verboseImage = false

    private var filtered: [NetLog.Entry] {
        log.entries.reversed().filter { e in
            switch filter {
            case .all: break
            case .errors: if e.level != .error { return false }
            case .graphql: if e.category != .graphql { return false }
            case .image: if e.category != .image { return false }
            case .wifi: if e.category != .wifi { return false }
            case .diag: if e.category != .diag { return false }
            case .auth: if e.category != .auth { return false }
            }
            let k = keyword.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { return true }
            let hay = [e.title, e.url ?? "", e.message ?? "", e.category.rawValue]
                .joined(separator: " ")
                .lowercased()
            return hay.contains(k.lowercased())
        }
    }

    var body: some View {
        List {
            Section {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("记录条数", value: "\(log.entries.count) / \(NetLog.capacity)")
                LabeledContent("其中错误", value: "\(log.errorCount)")

                Toggle("记录图片成功请求", isOn: $verboseImage)
            } header: {
                Text("筛选")
            } footer: {
                Text("默认只记录图片失败；开启后会记录每张图片的成功下载（列表滚动时日志量较大，仅排障时建议开启）。日志保存在内存中，App 重启后清空——反馈问题前请先复制。")
            }

            Section {
                if filtered.isEmpty {
                    Text(log.entries.isEmpty ? "暂无网络请求记录" : "没有匹配的记录")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
                ForEach(filtered) { e in
                    row(e)
                        .swipeActions(edge: .trailing) {
                            Button {
                                copy(NetLog.exportText([e]), label: "该条记录")
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                        .onTapGesture {
                            if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) }
                        }
                }
            } header: {
                Text("记录（新→旧）")
            }
        }
        .navigationTitle("网络日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "搜索地址 / 标题 / 错误")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copy(NetLog.exportText(filtered), label: "当前筛选的 \(filtered.count) 条")
                    } label: {
                        Label("复制当前筛选", systemImage: "doc.on.doc")
                    }
                    Button {
                        let errs = log.entries.reversed().filter { $0.level == .error }
                        copy(NetLog.exportText(errs), label: "全部错误 \(errs.count) 条")
                    } label: {
                        Label("复制仅错误", systemImage: "exclamationmark.triangle")
                    }
                    Button {
                        copy(NetLog.exportText(log.entries.reversed()), label: "全部 \(log.entries.count) 条")
                    } label: {
                        Label("复制全部", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("清空全部网络日志？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { NetLog.shared.clear() }
            Button("取消", role: .cancel) {}
        }
        .alert("已复制", isPresented: Binding(get: { copied != nil }, set: { if !$0 { copied = nil } })) {
            Button("好", role: .cancel) { copied = nil }
        } message: {
            Text(copied ?? "")
        }
    }

    // MARK: 行

    @ViewBuilder
    private func row(_ e: NetLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: levelIcon(e.level))
                .foregroundStyle(levelColor(e.level))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.category.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    Text(e.title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(NetLog.timeFormatter.string(from: e.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !e.summary.isEmpty {
                    Text(e.summary)
                        .font(.caption)
                        .foregroundStyle(e.level == .error ? .red : .secondary)
                        .lineLimit(expanded.contains(e.id) ? nil : 2)
                }
                if expanded.contains(e.id) {
                    if let u = e.url {
                        Text(u)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button {
                        copy(NetLog.exportText([e]), label: "该条记录")
                    } label: {
                        Label("复制此条", systemImage: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func levelIcon(_ l: NetLevel) -> String {
        switch l {
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func levelColor(_ l: NetLevel) -> Color {
        switch l {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text
        copied = "\(label)已复制到剪贴板"
    }
}
