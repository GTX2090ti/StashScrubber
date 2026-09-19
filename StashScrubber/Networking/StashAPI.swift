import Foundation

// MARK: - Stash GraphQL API 封装

enum StashAPI {

    // MARK: 系统

    static func version(_ c: GraphQLClient) async throws -> String {
        struct R: Decodable { let version: Version }
        struct Version: Decodable { let version: String? }
        let r: R = try await c.send("query { version { version } }", as: R.self)
        return r.version.version ?? "未知版本"
    }

    // MARK: 查询 - 场景

    static func findScenes(
        _ c: GraphQLClient, query: String = "", page: Int = 1, perPage: Int = 40,
        sort: String = "date", direction: String = "DESC"
    ) async throws -> ScenePage {
        struct R: Decodable { let findScenes: ScenePage }
        let q = """
        query FindScenes($filter: FindFilterType!) {
          findScenes(filter: $filter) {
            count
            scenes {
              id title details date rating100 o_counter
              urls
              studio { id name }
              performers { id name }
              tags { id name }
              paths { screenshot webp }
            }
          }
        }
        """
        var filter: [String: Any] = [
            "page": page, "per_page": perPage, "sort": sort, "direction": direction
        ]
        if !query.isEmpty { filter["q"] = query }
        let r: R = try await c.send(q, variables: ["filter": filter], as: R.self)
        return r.findScenes
    }

    static func scene(_ c: GraphQLClient, id: String) async throws -> Scene {
        struct R: Decodable { let findScene: Scene? }
        let q = """
        query FindScene($id: ID!) {
          findScene(id: $id) {
            id title details date rating100 o_counter
            urls
            studio { id name }
            performers { id name image_path birthdate details }
            tags { id name }
            paths { screenshot webp }
          }
        }
        """
        let r: R = try await c.send(q, variables: ["id": id], as: R.self)
        guard let s = r.findScene else { throw StashAPIError.noData }
        return s
    }

    // MARK: 查询 - 工作室

    static func findStudios(
        _ c: GraphQLClient, query: String = "", page: Int = 1, perPage: Int = 40
    ) async throws -> StudioPage {
        struct R: Decodable { let findStudios: StudioPage }
        let q = """
        query FindStudios($filter: FindFilterType!) {
          findStudios(filter: $filter) {
            count
            studios {
              id name url details image_path rating100
              tags { id name }
            }
          }
        }
        """
        var filter: [String: Any] = ["page": page, "per_page": perPage, "sort": "name", "direction": "ASC"]
        if !query.isEmpty { filter["q"] = query }
        let r: R = try await c.send(q, variables: ["filter": filter], as: R.self)
        return r.findStudios
    }

    static func studio(_ c: GraphQLClient, id: String) async throws -> Studio {
        struct R: Decodable { let findStudio: Studio? }
        let q = """
        query FindStudio($id: ID!) {
          findStudio(id: $id) {
            id name url details image_path rating100
            tags { id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: ["id": id], as: R.self)
        guard let s = r.findStudio else { throw StashAPIError.noData }
        return s
    }

    /// 某工作室下的场景（详情页「相关场景」）
    static func findScenesByStudio(
        _ c: GraphQLClient, studioId: String, page: Int = 1, perPage: Int = 24
    ) async throws -> ScenePage {
        struct R: Decodable { let findScenes: ScenePage }
        let q = """
        query FindScenesByStudio($filter: FindFilterType!, $sf: SceneFilterType!) {
          findScenes(filter: $filter, scene_filter: $sf) {
            count
            scenes {
              id title details date rating100 o_counter
              urls
              studio { id name }
              performers { id name }
              tags { id name }
              paths { screenshot webp }
            }
          }
        }
        """
        let filter: [String: Any] = ["page": page, "per_page": perPage, "sort": "date", "direction": "DESC"]
        let sf: [String: Any] = ["studios": ["value": [studioId], "modifier": "INCLUDES"]]
        let r: R = try await c.send(q, variables: ["filter": filter, "sf": sf], as: R.self)
        return r.findScenes
    }

    // MARK: 查询 - 标签

    static func findTags(
        _ c: GraphQLClient, query: String = "", page: Int = 1, perPage: Int = 120
    ) async throws -> TagPage {
        struct R: Decodable { let findTags: TagPage }
        let q = """
        query FindTags($filter: FindFilterType!) {
          findTags(filter: $filter) {
            count
            tags { id name }
          }
        }
        """
        var filter: [String: Any] = ["page": page, "per_page": perPage, "sort": "name", "direction": "ASC"]
        if !query.isEmpty { filter["q"] = query }
        let r: R = try await c.send(q, variables: ["filter": filter], as: R.self)
        return r.findTags
    }

    /// 带某标签的场景（标签详情页）
    static func findScenesByTag(
        _ c: GraphQLClient, tagId: String, page: Int = 1, perPage: Int = 24
    ) async throws -> ScenePage {
        struct R: Decodable { let findScenes: ScenePage }
        let q = """
        query FindScenesByTag($filter: FindFilterType!, $sf: SceneFilterType!) {
          findScenes(filter: $filter, scene_filter: $sf) {
            count
            scenes {
              id title details date rating100 o_counter
              urls
              studio { id name }
              performers { id name }
              tags { id name }
              paths { screenshot webp }
            }
          }
        }
        """
        let filter: [String: Any] = ["page": page, "per_page": perPage, "sort": "date", "direction": "DESC"]
        let sf: [String: Any] = ["tags": ["value": [tagId], "modifier": "INCLUDES"]]
        let r: R = try await c.send(q, variables: ["filter": filter, "sf": sf], as: R.self)
        return r.findScenes
    }

    // MARK: 查询 - 演员

    static func findPerformers(
        _ c: GraphQLClient, query: String = "", page: Int = 1, perPage: Int = 40
    ) async throws -> PerformerPage {
        struct R: Decodable { let findPerformers: PerformerPage }
        let q = """
        query FindPerformers($filter: FindFilterType!) {
          findPerformers(filter: $filter) {
            count
            performers {
              id name disambiguation image_path birthdate country rating100
              tags { id name }
            }
          }
        }
        """
        var filter: [String: Any] = ["page": page, "per_page": perPage, "sort": "name", "direction": "ASC"]
        if !query.isEmpty { filter["q"] = query }
        let r: R = try await c.send(q, variables: ["filter": filter], as: R.self)
        return r.findPerformers
    }

    static func performer(_ c: GraphQLClient, id: String) async throws -> Performer {
        struct R: Decodable { let findPerformer: Performer? }
        let q = """
        query FindPerformer($id: ID!) {
          findPerformer(id: $id) {
            id name disambiguation image_path birthdate country ethnicity
            measurements career_length details rating100
            tags { id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: ["id": id], as: R.self)
        guard let p = r.findPerformer else { throw StashAPIError.noData }
        return p
    }

    // MARK: 元数据来源（工作室 / 演员 / 标签 全量，供编辑器选择）

    static func allStudios(_ c: GraphQLClient) async throws -> [Studio] {
        struct R: Decodable { let allStudios: [Studio] }
        return try await c.send("query { allStudios { id name } }", as: R.self).allStudios
    }

    static func allPerformers(_ c: GraphQLClient) async throws -> [Performer] {
        struct R: Decodable { let allPerformers: [Performer] }
        return try await c.send("query { allPerformers { id name } }", as: R.self).allPerformers
    }

    static func allTags(_ c: GraphQLClient) async throws -> [Tag] {
        struct R: Decodable { let allTags: [Tag] }
        return try await c.send("query { allTags { id name } }", as: R.self).allTags
    }

    // MARK: 刮削器列表（统一 listScrapers(types:)，本套 Stash 无 listSceneScrapers 等拆分字段）

    /// - Parameter kind: 目标类型，决定 ScraperType 取 SCENE / STUDIO / PERFORMER
    static func scrapers(_ c: GraphQLClient, kind: ScrapeKind) async throws -> [Scraper] {
        let typeName: String
        switch kind {
        case .scene: typeName = "SCENE"
        case .studio: typeName = "STUDIO"
        case .performer: typeName = "PERFORMER"
        }
        struct R: Decodable { let listScrapers: [Scraper] }
        let q = """
        query ListScrapers($types: [ScraperType!]!) {
          listScrapers(types: $types) {
            id name
            scene { supported_scrapes }
            studio { supported_scrapes }
            performer { supported_scrapes }
          }
        }
        """
        let r: R = try await c.send(q, variables: ["types": [typeName]], as: R.self)
        return r.listScrapers
    }

    // MARK: 削刮 - 场景

    /// 片段削刮：以现有场景信息为上下文，用指定刮削器削刮
    static func scrapeSceneFragment(_ c: GraphQLClient, scraperId: String, sceneId: String) async throws -> [ScrapedScene] {
        struct R: Decodable { let scrapeSingleScene: [ScrapedScene?] }
        let q = """
        mutation ScrapeSingleScene($source: ScraperSourceInput!, $input: ScrapeSingleSceneInput!) {
          scrapeSingleScene(source: $source, input: $input) {
            id title details date duration urls image
            studio { id stored_id name image_path }
            performers { id stored_id name disambiguation birthdate details country image_path tags { id stored_id name } }
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "source": ["source_type": "SCRAPER", "id": scraperId],
            "input": ["scene_id": sceneId]
        ], as: R.self)
        return r.scrapeSingleScene.compactMap { $0 }
    }

    /// URL 削刮
    static func scrapeSceneURL(_ c: GraphQLClient, url: String) async throws -> [ScrapedScene] {
        struct R: Decodable { let scrapeSingleScene: [ScrapedScene?] }
        let q = """
        mutation ScrapeSceneURL($source: ScraperSourceInput!) {
          scrapeSingleScene(source: $source, input: {}) {
            id title details date duration urls image
            studio { id stored_id name image_path }
            performers { id stored_id name disambiguation birthdate details country image_path tags { id stored_id name } }
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "source": ["source_type": "URL", "url": url]
        ], as: R.self)
        return r.scrapeSingleScene.compactMap { $0 }
    }

    /// 关键词搜索削刮
    static func scrapeSceneQuery(_ c: GraphQLClient, query: String) async throws -> [ScrapedScene] {
        struct R: Decodable { let queryScrapeSceneQuery: [ScrapedScene?] }
        let q = """
        query ScrapeSceneQuery($filter: FindFilterType!, $query: String!) {
          queryScrapeSceneQuery(filter: $filter, query: $query) {
            id title details date duration urls image
            studio { id stored_id name image_path }
            performers { id stored_id name disambiguation birthdate details country image_path tags { id stored_id name } }
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "filter": ["q": query], "query": query
        ], as: R.self)
        return r.queryScrapeSceneQuery.compactMap { $0 }
    }

    // MARK: 削刮 - 工作室

    /// 片段削刮：以现有工作室信息为上下文，用指定刮削器削刮
    static func scrapeStudioFragment(_ c: GraphQLClient, scraperId: String, studioId: String) async throws -> [ScrapedStudio] {
        struct R: Decodable { let scrapeSingleStudio: [ScrapedStudio?] }
        let q = """
        mutation ScrapeSingleStudio($source: ScraperSourceInput!, $input: ScrapeSingleStudioInput!) {
          scrapeSingleStudio(source: $source, input: $input) {
            id stored_id name image_path details urls
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "source": ["source_type": "SCRAPER", "id": scraperId],
            "input": ["studio_id": studioId]
        ], as: R.self)
        return r.scrapeSingleStudio.compactMap { $0 }
    }

    /// 工作室 URL 削刮（与场景相同模式：source 指向 URL，input 留空）
    static func scrapeStudioURL(_ c: GraphQLClient, url: String) async throws -> [ScrapedStudio] {
        struct R: Decodable { let scrapeSingleStudio: [ScrapedStudio?] }
        let q = """
        mutation ScrapeStudioURL($source: ScraperSourceInput!) {
          scrapeSingleStudio(source: $source, input: {}) {
            id stored_id name image_path details urls
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "source": ["source_type": "URL", "url": url]
        ], as: R.self)
        return r.scrapeSingleStudio.compactMap { $0 }
    }

    /// 工作室关键词搜索削刮
    static func scrapeStudioQuery(_ c: GraphQLClient, query: String) async throws -> [ScrapedStudio] {
        struct R: Decodable { let queryScrapeStudioQuery: [ScrapedStudio?] }
        let q = """
        query ScrapeStudioQuery($filter: FindFilterType!, $query: String!) {
          queryScrapeStudioQuery(filter: $filter, query: $query) {
            id stored_id name image_path details urls
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "filter": ["q": query], "query": query
        ], as: R.self)
        return r.queryScrapeStudioQuery.compactMap { $0 }
    }

    // MARK: 削刮 - 演员

    static func scrapePerformerFragment(_ c: GraphQLClient, scraperId: String, performerId: String) async throws -> [ScrapedPerformer] {
        struct R: Decodable { let scrapeSinglePerformer: [ScrapedPerformer?] }
        let q = """
        mutation ScrapeSinglePerformer($source: ScraperSourceInput!, $input: ScrapeSinglePerformerInput!) {
          scrapeSinglePerformer(source: $source, input: $input) {
            id stored_id name disambiguation birthdate details country ethnicity
            measurements career_length urls image_path
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "source": ["source_type": "SCRAPER", "id": scraperId],
            "input": ["performer_id": performerId]
        ], as: R.self)
        return r.scrapeSinglePerformer.compactMap { $0 }
    }

    static func scrapePerformerQuery(_ c: GraphQLClient, query: String) async throws -> [ScrapedPerformer] {
        struct R: Decodable { let queryScrapePerformerQuery: [ScrapedPerformer?] }
        let q = """
        query ScrapePerformerQuery($filter: FindFilterType!, $query: String!) {
          queryScrapePerformerQuery(filter: $filter, query: $query) {
            id stored_id name disambiguation birthdate details country ethnicity
            measurements career_length urls image_path
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: [
            "filter": ["q": query], "query": query
        ], as: R.self)
        return r.queryScrapePerformerQuery.compactMap { $0 }
    }

    /// 演员 URL 削刮
    static func scrapePerformerURL(_ c: GraphQLClient, url: String) async throws -> [ScrapedPerformer] {
        struct R: Decodable { let scrapePerformerURL: [ScrapedPerformer?] }
        let q = """
        mutation ScrapePerformerURL($url: String!) {
          scrapePerformerURL(url: $url) {
            id stored_id name disambiguation birthdate details country ethnicity
            measurements career_length urls image_path
            tags { id stored_id name }
          }
        }
        """
        let r: R = try await c.send(q, variables: ["url": url], as: R.self)
        return r.scrapePerformerURL.compactMap { $0 }
    }

    // MARK: 元数据写回

    static func updateScene(_ c: GraphQLClient, input: SceneUpdateInput) async throws {
        struct R: Decodable { let sceneUpdate: IDOnly? }
        struct IDOnly: Decodable { let id: String }
        let q = """
        mutation UpdateScene($input: SceneUpdateInput!) {
          sceneUpdate(input: $input) { id }
        }
        """
        let r: R = try await c.send(q, variables: ["input": try jsonDict(input)], as: R.self)
        if r.sceneUpdate == nil { throw StashAPIError.noData }
    }

    static func updateStudio(_ c: GraphQLClient, input: StudioUpdateInput) async throws {
        struct R: Decodable { let studioUpdate: IDOnly? }
        struct IDOnly: Decodable { let id: String }
        let q = """
        mutation UpdateStudio($input: StudioUpdateInput!) {
          studioUpdate(input: $input) { id }
        }
        """
        let r: R = try await c.send(q, variables: ["input": try jsonDict(input)], as: R.self)
        if r.studioUpdate == nil { throw StashAPIError.noData }
    }

    static func updatePerformer(_ c: GraphQLClient, input: PerformerUpdateInput) async throws {
        struct R: Decodable { let performerUpdate: IDOnly? }
        struct IDOnly: Decodable { let id: String }
        let q = """
        mutation UpdatePerformer($input: PerformerUpdateInput!) {
          performerUpdate(input: $input) { id }
        }
        """
        let r: R = try await c.send(q, variables: ["input": try jsonDict(input)], as: R.self)
        if r.performerUpdate == nil { throw StashAPIError.noData }
    }

    // MARK: 实体创建（削刮结果中出现库里没有的 演员/标签/工作室 时调用）

    static func createPerformer(_ c: GraphQLClient, name: String) async throws -> String {
        struct R: Decodable { let performerCreate: IDOnly }
        struct IDOnly: Decodable { let id: String }
        let r: R = try await c.send(
            "mutation CreatePerformer($input: PerformerCreateInput!) { performerCreate(input: $input) { id } }",
            variables: ["input": ["name": name]], as: R.self
        )
        return r.performerCreate.id
    }

    static func createTag(_ c: GraphQLClient, name: String) async throws -> String {
        struct R: Decodable { let tagCreate: IDOnly }
        struct IDOnly: Decodable { let id: String }
        let r: R = try await c.send(
            "mutation CreateTag($input: TagCreateInput!) { tagCreate(input: $input) { id } }",
            variables: ["input": ["name": name]], as: R.self
        )
        return r.tagCreate.id
    }

    static func createStudio(_ c: GraphQLClient, name: String) async throws -> String {
        struct R: Decodable { let studioCreate: IDOnly }
        struct IDOnly: Decodable { let id: String }
        let r: R = try await c.send(
            "mutation CreateStudio($input: StudioCreateInput!) { studioCreate(input: $input) { id } }",
            variables: ["input": ["name": name]], as: R.self
        )
        return r.studioCreate.id
    }

    // MARK: 削刮结果回写（核心流程）

    /// 将削刮结果应用到已有条目：
    /// 1. scraped 实体带 stored_id / id 的直接复用库内 ID
    /// 2. 库内不存在的 演员/标签/工作室 自动创建后再引用
    /// 3. 仅写入削刮结果中非空的字段，避免覆盖已有数据
    static func applyScraped(_ c: GraphQLClient, item: ScrapedItem, targetID: String) async throws -> Int {
        var changed = 0

        func resolvePerformerID(_ p: ScrapedPerformer) async throws -> String? {
            if let sid = p.storedId ?? p.id { return sid }
            guard let name = p.name, !name.isEmpty else { return nil }
            return try await createPerformer(c, name: name)
        }

        func resolveTagID(_ t: ScrapedTag) async throws -> String? {
            if let sid = t.storedId ?? t.id { return sid }
            guard let name = t.name, !name.isEmpty else { return nil }
            return try await createTag(c, name: name)
        }

        func resolveStudioID(_ s: ScrapedStudio) async throws -> String? {
            if let sid = s.storedId ?? s.id { return sid }
            guard let name = s.name, !name.isEmpty else { return nil }
            return try await createStudio(c, name: name)
        }

        switch item {
        case .scene(let s):
            var input = SceneUpdateInput(id: targetID)
            if let v = s.title, !v.isEmpty { input.title = v; changed += 1 }
            if let v = s.details, !v.isEmpty { input.details = v; changed += 1 }
            if let v = s.date, !v.isEmpty { input.date = v; changed += 1 }
            if let st = s.studio, let sid = try await resolveStudioID(st) { input.studioId = sid; changed += 1 }
            if let ps = s.performers {
                var ids: [String] = []
                for p in ps { if let pid = try await resolvePerformerID(p) { ids.append(pid) } }
                if !ids.isEmpty { input.performerIds = ids; changed += 1 }
            }
            if let ts = s.tags {
                var ids: [String] = []
                for t in ts { if let tid = try await resolveTagID(t) { ids.append(tid) } }
                if !ids.isEmpty { input.tagIds = ids; changed += 1 }
            }
            if let us = s.urls, !us.isEmpty { input.urls = us; changed += 1 }
            if changed > 0 { try await updateScene(c, input: input) }

        case .studio(let st):
            var input = StudioUpdateInput(id: targetID)
            if let v = st.name, !v.isEmpty { input.name = v; changed += 1 }
            if let v = st.details, !v.isEmpty { input.details = v; changed += 1 }
            if let u = st.urls?.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                input.url = u; changed += 1
            }
            if let ts = st.tags {
                var ids: [String] = []
                for t in ts { if let tid = try await resolveTagID(t) { ids.append(tid) } }
                if !ids.isEmpty { input.tagIds = ids; changed += 1 }
            }
            if changed > 0 { try await updateStudio(c, input: input) }

        case .performer(let p):
            var input = PerformerUpdateInput(id: targetID)
            if let v = p.name, !v.isEmpty { input.name = v; changed += 1 }
            if let v = p.disambiguation { input.disambiguation = v; changed += 1 }
            if let v = p.birthdate { input.birthdate = v; changed += 1 }
            if let v = p.details, !v.isEmpty { input.details = v; changed += 1 }
            if let v = p.country { input.country = v; changed += 1 }
            if let v = p.ethnicity { input.ethnicity = v; changed += 1 }
            if let v = p.measurements { input.measurements = v; changed += 1 }
            if let v = p.careerLength { input.careerLength = v; changed += 1 }
            if let ts = p.tags {
                var ids: [String] = []
                for t in ts { if let tid = try await resolveTagID(t) { ids.append(tid) } }
                if !ids.isEmpty { input.tagIds = ids; changed += 1 }
            }
            if changed > 0 { try await updatePerformer(c, input: input) }
        }

        if changed == 0 {
            throw StashAPIError.noData // 无字段可写
        }
        return changed
    }
}
