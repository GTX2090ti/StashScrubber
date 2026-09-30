import Foundation

// MARK: - 削刮目标类型

enum ScrapeKind: Hashable {
    case scene, performer

    var title: String {
        switch self {
        case .scene: return "短片"
        case .performer: return "演员"
        }
    }
}

// MARK: - 削刮结果实体
//
// 真机 schema 实测（2026-09-19）：ScrapedScene/Performer/Tag/Studio 均无 id 字段（仅 stored_id）；
// 演员图片在 images 数组；从业时间拆为 career_start / career_end；工作室图片字段名为 image。

struct ScrapedStudio: Codable, Hashable {
    let storedId: String?
    let name: String?
    let image: String?
    let details: String?
    let aliases: String?
    let urls: [String]?
    let tags: [ScrapedTag]?

    enum CodingKeys: String, CodingKey {
        case name, image, details, aliases, urls, tags
        case storedId = "stored_id"
    }
}

struct ScrapedTag: Codable, Hashable {
    let storedId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case name
        case storedId = "stored_id"
    }
}

struct ScrapedPerformer: Codable, Hashable {
    let storedId: String?
    let name: String?
    let disambiguation: String?
    let aliases: String?
    let birthdate: String?
    let gender: String?
    let country: String?
    let ethnicity: String?
    let hairColor: String?
    let eyeColor: String?
    let height: String?   // 刮削源可能返回 "156" 字符串，统一按字符串接收再转 Int
    let weight: String?   // 同上
    let measurements: String?
    let fakeTits: String?
    let tattoos: String?
    let piercings: String?
    let careerStart: String?
    let careerEnd: String?
    let details: String?
    let rating100: Int?
    let urls: [String]?
    let images: [String]?
    let tags: [ScrapedTag]?

    enum CodingKeys: String, CodingKey {
        case name, disambiguation, aliases, birthdate, gender, details
        case country, ethnicity, measurements, fakeTits, tattoos, piercings
        case height, weight, urls, images, rating100
        case storedId = "stored_id"
        case hairColor = "hair_color"
        case eyeColor = "eye_color"
        case careerStart = "career_start"
        case careerEnd = "career_end"
        case tags
    }
}

struct ScrapedScene: Codable, Hashable {
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

// MARK: - 统一削刮结果包装（供通用削刮界面使用）

enum ScrapedItem: Hashable, Identifiable {
    case scene(ScrapedScene)
    case performer(ScrapedPerformer)

    var id: String {
        switch self {
        case .scene(let s):
            return "scene:" + (s.title ?? "") + "|" + (s.date ?? "") + "|" + (s.studio?.name ?? "")
        case .performer(let p):
            return "perf:" + (p.name ?? "") + "|" + (p.birthdate ?? "")
        }
    }

    var displayName: String {
        switch self {
        case .scene(let s): return s.title ?? "（无标题短片）"
        case .performer(let p): return p.name ?? "（无名演员）"
        }
    }

    var subtitle: String? {
        switch self {
        case .scene(let s):
            let parts = [s.studio?.name, s.date].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .performer(let p):
            let parts = [p.birthdate, p.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// 原始图片引用（URL 或 base64 data URI 均可，供「应用图片」判断）
    var rawImageRef: String? {
        switch self {
        case .scene(let s): return s.image.flatMap { $0.isEmpty ? nil : $0 }
        case .performer(let p): return p.images?.first(where: { !$0.isEmpty })
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
        case .performer(let p): return httpOnly(p.images?.first)
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
