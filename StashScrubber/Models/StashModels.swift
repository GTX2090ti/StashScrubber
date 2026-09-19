import Foundation

// MARK: - Stash 核心实体（GraphQL 响应解码）

struct Tag: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct Studio: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var url: String?
    var details: String?
    var imagePath: String?
    var rating100: Int?
    var tags: [Tag]?

    enum CodingKeys: String, CodingKey {
        case id, name, url, details, rating100, tags
        case imagePath = "image_path"
    }
}

struct Performer: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    var disambiguation: String?
    var birthdate: String?
    var details: String?
    var country: String?
    var ethnicity: String?
    var measurements: String?
    var careerLength: String?
    var imagePath: String?
    var rating100: Int?
    var tags: [Tag]?

    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, birthdate, details, country
        case ethnicity, measurements
        case careerLength = "career_length"
        case imagePath = "image_path"
        case rating100, tags
    }
}

struct Scene: Codable, Hashable, Identifiable {
    let id: String
    var title: String?
    var details: String?
    var date: String?
    var rating100: Int?
    var oCounter: Int?
    var urls: [String]?
    var studio: Studio?
    var performers: [Performer]?
    var tags: [Tag]?
    var paths: ScenePaths?

    enum CodingKeys: String, CodingKey {
        case id, title, details, date, rating100, urls
        case oCounter = "o_counter"
        case studio, performers, tags, paths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        rating100 = try c.decodeIfPresent(Int.self, forKey: .rating100)
        oCounter = try c.decodeIfPresent(Int.self, forKey: .oCounter)
        studio = try c.decodeIfPresent(Studio.self, forKey: .studio)
        performers = try c.decodeIfPresent([Performer].self, forKey: .performers)
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags)
        paths = try c.decodeIfPresent(ScenePaths.self, forKey: .paths)
        // 该 Stash 实测 urls 为 [String] 纯字符串数组
        urls = try c.decodeIfPresent([String].self, forKey: .urls)
    }
}

struct ScenePaths: Codable, Hashable {
    let screenshot: String?
    let webp: String?
}

struct ScenePage: Codable {
    let count: Int
    let scenes: [Scene]
}

struct StudioPage: Codable {
    let count: Int
    let studios: [Studio]
}

struct TagPage: Codable {
    let count: Int
    let tags: [Tag]
}

struct PerformerPage: Codable {
    let count: Int
    let performers: [Performer]
}

// MARK: - 刮削器描述

struct Scraper: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    var scene: Capability?
    var studio: Capability?
    var performer: Capability?

    struct Capability: Codable, Hashable {
        let supportedScrapes: [String]?
        enum CodingKeys: String, CodingKey {
            case supportedScrapes = "supported_scrapes"
        }
    }

    var supportsFragment: Bool {
        switch Self.kindContext {
        case .scene: return scene?.supportedScrapes?.contains("FRAGMENT") ?? false
        case .studio: return studio?.supportedScrapes?.contains("FRAGMENT") ?? false
        case .performer: return performer?.supportedScrapes?.contains("FRAGMENT") ?? false
        }
    }

    var supportsName: Bool {
        switch Self.kindContext {
        case .scene: return scene?.supportedScrapes?.contains("NAME") ?? false
        case .studio: return studio?.supportedScrapes?.contains("NAME") ?? false
        case .performer: return performer?.supportedScrapes?.contains("NAME") ?? false
        }
    }

    /// 查询时临时记录当前目标类型，供 supports* 使用（由 API 层设置）
    static var kindContext: ScrapeKind = .scene
}

// MARK: - 元数据更新输入

struct SceneUpdateInput: Encodable {
    var id: String
    var title: String?
    var details: String?
    var date: String?
    var rating100: Int?
    var studioId: String?
    var performerIds: [String]?
    var tagIds: [String]?
    var urls: [String]?
}

struct StudioUpdateInput: Encodable {
    var id: String
    var name: String?
    var url: String?
    var details: String?
    var rating100: Int?
    var tagIds: [String]?
}

struct PerformerUpdateInput: Encodable {
    var id: String
    var name: String?
    var disambiguation: String?
    var birthdate: String?
    var details: String?
    var country: String?
    var ethnicity: String?
    var measurements: String?
    var careerLength: String?
    var rating100: Int?
    var tagIds: [String]?
}
