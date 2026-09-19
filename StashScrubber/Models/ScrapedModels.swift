import Foundation

// MARK: - 削刮目标类型

enum ScrapeKind: Hashable {
    case scene, image, performer

    var title: String {
        switch self {
        case .scene: return "场景"
        case .image: return "图片"
        case .performer: return "演员"
        }
    }
}

// MARK: - 刮削结果实体（对应 Stash ScrapedScene / ScrapedImage / ScrapedPerformer）

struct ScrapedStudio: Codable, Hashable {
    let id: String?
    let storedId: String?
    let name: String?
    let imagePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case storedId = "stored_id"
        case imagePath = "image_path"
    }
}

struct ScrapedTag: Codable, Hashable {
    let id: String?
    let storedId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case storedId = "stored_id"
    }
}

struct ScrapedPerformer: Codable, Hashable {
    let id: String?
    let storedId: String?
    let name: String?
    let disambiguation: String?
    let birthdate: String?
    let details: String?
    let country: String?
    let ethnicity: String?
    let measurements: String?
    let careerLength: String?
    let urls: [String]?
    let imagePath: String?
    let tags: [ScrapedTag]?

    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, birthdate, details
        case country, ethnicity, measurements, urls
        case storedId = "stored_id"
        case imagePath = "image_path"
        case tags
    }
}

struct ScrapedScene: Codable, Hashable {
    let id: String?
    let title: String?
    let details: String?
    let date: String?
    let duration: Double?
    let urls: [String]?
    let image: String?
    let studio: ScrapedStudio?
    let performers: [ScrapedPerformer]?
    let tags: [ScrapedTag]?
}

struct ScrapedImage: Codable, Hashable {
    let id: String?
    let title: String?
    let date: String?
    let urls: [String]?
    let image: String?
    let studio: ScrapedStudio?
    let performers: [ScrapedPerformer]?
    let tags: [ScrapedTag]?
}

// MARK: - 统一削刮结果包装（供通用削刮界面使用）

enum ScrapedItem: Hashable, Identifiable {
    case scene(ScrapedScene)
    case image(ScrapedImage)
    case performer(ScrapedPerformer)

    var id: String {
        switch self {
        case .scene(let s):
            return "scene:" + (s.title ?? "") + "|" + (s.date ?? "") + "|" + (s.studio?.name ?? "")
        case .image(let i):
            return "image:" + (i.title ?? "") + "|" + (i.date ?? "") + "|" + (i.studio?.name ?? "")
        case .performer(let p):
            return "perf:" + (p.name ?? "") + "|" + (p.birthdate ?? "")
        }
    }

    var displayName: String {
        switch self {
        case .scene(let s): return s.title ?? "（无标题场景）"
        case .image(let i): return i.title ?? "（无标题图片）"
        case .performer(let p): return p.name ?? "（无名演员）"
        }
    }

    var subtitle: String? {
        switch self {
        case .scene(let s):
            let parts = [s.studio?.name, s.date].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .image(let i):
            let parts = [i.studio?.name, i.date].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .performer(let p):
            let parts = [p.birthdate, p.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// 仅展示可远程加载的 URL 图片（base64 结果不在此预览）
    var imageURLString: String? {
        func httpOnly(_ s: String?) -> String? {
            guard let s, s.hasPrefix("http") else { return nil }
            return s
        }
        switch self {
        case .scene(let s): return httpOnly(s.image)
        case .image(let i): return httpOnly(i.image)
        case .performer(let p): return p.imagePath
        }
    }
}

// MARK: - 已有条目元数据快照（用于削刮结果对比预览）

struct ExistingMeta: Hashable {
    var title: String?
    var details: String?
    var date: String?
    var birthdate: String?
    var country: String?
    var studio: String?
    var performers: [String]
    var tags: [String]
    var urls: [String]

    init(scene: Scene) {
        title = scene.title
        details = scene.details
        date = scene.date
        birthdate = nil
        country = nil
        studio = scene.studio?.name
        performers = scene.performers?.map(\.name) ?? []
        tags = scene.tags?.map(\.name) ?? []
        urls = scene.urls ?? []
    }

    init(image: StashImage) {
        title = image.title
        details = nil
        date = image.date
        birthdate = nil
        country = nil
        studio = image.studio?.name
        performers = image.performers?.map(\.name) ?? []
        tags = image.tags?.map(\.name) ?? []
        urls = []
    }

    init(performer: Performer) {
        title = performer.name
        details = performer.details
        date = nil
        birthdate = performer.birthdate
        country = performer.country
        studio = nil
        performers = []
        tags = performer.tags?.map(\.name) ?? []
        urls = []
    }

    init() {
        title = nil; details = nil; date = nil; birthdate = nil; country = nil
        studio = nil; performers = []; tags = []; urls = []
    }
}
