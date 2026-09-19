import Foundation

// MARK: - 场景筛选状态（对齐 Stash WebUI 筛选器）
//
// 字段与服务端真实 schema 逐项核对并实测通过（2026-09-19）：
// - studios/tags 为 HierarchicalMultiCriterionInput {value, modifier, depth, excludes}
// - performers 为 MultiCriterionInput {value, modifier, excludes}
// - rating100/o_counter/duration 为 IntCriterionInput {value, value2, modifier}
// - date 为 DateCriterionInput {value, value2, modifier}（BETWEEN / GREATER_THAN / LESS_THAN）
// - organized 为 Boolean；resolution 为 ResolutionCriterionInput {value: ResolutionEnum, modifier}

struct SceneFilterState: Codable, Equatable {
    var studioIDs: [String] = []
    var performerIDs: [String] = []
    var tagIDs: [String] = []
    var tagIncludeAll = false        // false=任一标签(INCLUDES) / true=全部标签(INCLUDES_ALL)
    var minRating100: Int? = nil     // 评分下限（rating100 百分制）
    var organized: Int? = nil        // nil=不限 / 1=仅已整理 / 0=仅未整理
    var minOCounter: Int? = nil      // O 计数下限
    var dateFrom = ""                // yyyy-MM-dd
    var dateTo = ""                  // yyyy-MM-dd
    var minDuration: Int? = nil      // 时长下限（秒）
    var resolution: String? = nil    // ResolutionEnum，GREATER_THAN=不低于

    var isEmpty: Bool {
        activeCount == 0
    }

    var activeCount: Int {
        var n = 0
        if !studioIDs.isEmpty { n += 1 }
        if !performerIDs.isEmpty { n += 1 }
        if !tagIDs.isEmpty { n += 1 }
        if minRating100 != nil { n += 1 }
        if organized != nil { n += 1 }
        if minOCounter != nil { n += 1 }
        if !dateFrom.isEmpty || !dateTo.isEmpty { n += 1 }
        if minDuration != nil { n += 1 }
        if resolution != nil { n += 1 }
        return n
    }

    /// 组装服务端 SceneFilterType JSON；无条件时返回 nil
    func toSceneFilter() -> [String: Any]? {
        guard !isEmpty else { return nil }
        var sf: [String: Any] = [:]
        if !studioIDs.isEmpty {
            sf["studios"] = ["value": studioIDs, "modifier": "INCLUDES", "depth": -1]
        }
        if !performerIDs.isEmpty {
            sf["performers"] = ["value": performerIDs, "modifier": "INCLUDES"]
        }
        if !tagIDs.isEmpty {
            sf["tags"] = [
                "value": tagIDs,
                "modifier": tagIncludeAll ? "INCLUDES_ALL" : "INCLUDES",
                "depth": -1
            ]
        }
        if let r = minRating100 {
            sf["rating100"] = ["value": r - 1, "value2": NSNull(), "modifier": "GREATER_THAN"]
        }
        if let o = organized {
            sf["organized"] = (o == 1)
        }
        if let m = minOCounter {
            sf["o_counter"] = ["value": m - 1, "value2": NSNull(), "modifier": "GREATER_THAN"]
        }
        if !dateFrom.isEmpty || !dateTo.isEmpty {
            let from = dateFrom.isEmpty ? "0001-01-01" : dateFrom
            let to = dateTo.isEmpty ? "9999-12-31" : dateTo
            let modifier = (!dateFrom.isEmpty && !dateTo.isEmpty) ? "BETWEEN"
                           : (dateTo.isEmpty ? "GREATER_THAN" : "LESS_THAN")
            sf["date"] = ["value": from, "value2": to, "modifier": modifier]
        }
        if let m = minDuration {
            sf["duration"] = ["value": m - 1, "value2": NSNull(), "modifier": "GREATER_THAN"]
        }
        if let res = resolution {
            sf["resolution"] = ["value": res, "modifier": "GREATER_THAN"]
        }
        return sf.isEmpty ? nil : sf
    }
}
