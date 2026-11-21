import CoreGraphics
import CryptoKit
import Foundation

public enum KnowledgeDomain: String, CaseIterable, Codable, Sendable {
    case llm = "01-LLM与新模型"
    case learning = "02-AI学习与教程"
    case creative3D = "03-AI创作与3D工具"
    case industry = "04-行业深度认知"

    public var filename: String { "\(rawValue).md" }

    public static func normalize(_ raw: String) -> KnowledgeDomain {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = KnowledgeDomain(rawValue: cleaned) { return exact }
        let lower = cleaned.lowercased().replacingOccurrences(of: " ", with: "")
        if lower.hasPrefix("01") || lower.contains("llm") || lower.contains("模型") { return .llm }
        if lower.hasPrefix("02") || lower.contains("学习") || lower.contains("教程") { return .learning }
        if lower.hasPrefix("03") || lower.contains("创作") || lower.contains("3d") { return .creative3D }
        return .industry
    }
}

public enum ExternalDisplayPlacement: String, CaseIterable, Codable, Sendable, Identifiable {
    case topCenter = "topCenter"
    case topLeading = "topLeading"
    case topTrailingSafe = "topTrailingSafe"
    case custom = "custom"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .topCenter: return "顶部居中 (默认)"
        case .topLeading: return "顶部偏左"
        case .topTrailingSafe: return "顶部偏右 (避让控制中心)"
        case .custom: return "自由拖拽记忆"
        }
    }

    public var description: String {
        switch self {
        case .topCenter: return "居中悬浮胶囊，自动适配 16:9 / 16:10 / 21:9 带鱼屏，视线居中"
        case .topLeading: return "顶部偏左悬浮，避开屏幕中央与右侧控制中心"
        case .topTrailingSafe: return "顶部右侧悬浮，留出 220pt 空间避让控制中心、时钟与通知"
        case .custom: return "按住 HUD 拖拽至屏幕任意位置并自动记忆停靠坐标"
        }
    }
}

public enum GlassToneTier: String, CaseIterable, Codable, Sendable, Identifiable {
    case clear = "clear"
    case regular = "regular"
    case tinted = "tinted"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .clear: return "最玻璃"
        case .regular: return "默认中间档"
        case .tinted: return "色调 (显毛玻璃)"
        }
    }

    public var subtitle: String {
        switch self {
        case .clear: return "通透水晶质感与高光描边，充分透出壁纸"
        case .regular: return "标准原生液态玻璃，质感与对比度平衡"
        case .tinted: return "深邃磨砂毛玻璃，文字对比最清晰"
        }
    }

    public var targetIntensity: Double {
        switch self {
        case .clear: return 0.15
        case .regular: return 0.50
        case .tinted: return 0.90
        }
    }

    public static func from(intensity: Double) -> GlassToneTier {
        if intensity < 0.33 {
            return .clear
        } else if intensity < 0.67 {
            return .regular
        } else {
            return .tinted
        }
    }
}

public enum CapsuleStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case liquidGlass = "liquidGlass"
    case pureBlack = "pureBlack"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .liquidGlass: return "液态玻璃"
        case .pureBlack: return "纯黑灵动岛"
        }
    }
}

public enum GlassStylePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case regular = "regular"
    case clear = "clear"
    case tintedDark = "tintedDark"
    case frosted = "frosted"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .regular: return "原生液态"
        case .clear: return "通透水晶"
        case .tintedDark: return "深邃暗黑"
        case .frosted: return "雾面磨砂"
        }
    }
}

public enum MonitoringMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case manual = "manual"
    case focused = "focused"
    case continuous = "continuous"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .manual: return "按需"
        case .focused: return "聚焦"
        case .continuous: return "全自动"
        }
    }

    public var description: String {
        switch self {
        case .manual: return "仅在手动触发（⌘⇧S / 点击抓拍 / 粘贴链接）时分析，绝不乱抓无关窗口"
        case .focused: return "仅当前台窗口命中当前学习主题关键词时自动伴学，无关内容静默跳过"
        case .continuous: return "自动监测白名单视频/网页（PiliPlus、B站、YouTube 等）"
        }
    }

    public var symbolName: String {
        switch self {
        case .manual: return "hand.tap"
        case .focused: return "scope"
        case .continuous: return "eye"
        }
    }
}

public struct FocusGoal: Codable, Equatable, Sendable {
    public var title: String
    public var keywords: [String]
    public var projectContext: String
    public var feedbackFilePath: String

    public init(
        title: String = "",
        keywords: [String] = [],
        projectContext: String = "",
        feedbackFilePath: String = ""
    ) {
        self.title = title
        self.keywords = keywords
        self.projectContext = projectContext
        self.feedbackFilePath = feedbackFilePath
    }

    public var isConfigured: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !keywords.isEmpty
            || !projectContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum CompanionStatus: Equatable, Sendable {
    case idle
    case watching(target: String)
    case analyzing(label: String)
    case paused(reason: String)
    case error(message: String)

    public var isActive: Bool {
        switch self {
        case .watching, .analyzing: return true
        default: return false
        }
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var shortLabel: String {
        switch self {
        case .idle: return "休眠"
        case .watching(let target): return "同看 · \(target)"
        case .analyzing(let label): return "解析 · \(label)"
        case .paused(let reason): return reason
        case .error(let msg): return msg
        }
    }
}

public struct ConceptItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { term }
    public var term: String
    public var explanation: String
    public var analogy: String?

    public init(term: String, explanation: String, analogy: String? = nil) {
        self.term = term
        self.explanation = explanation
        self.analogy = analogy
    }
}

public struct QuizItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { question }
    public var question: String
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct KnowledgeEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: String
    public var url: String
    public var domain: String
    public var ladderLevel: String
    public var matchedProject: String?
    public var focusGoal: String?
    public var oneLineEssence: String
    public var prerequisites: [String]
    public var conceptBreakdown: [ConceptItem]
    public var keyPoints: [String]
    public var actionableSteps: [String]
    public var projectOptimizations: [String]
    public var pitfalls: [String]
    public var selfCheckQA: [QuizItem]
    public var copyableSnippets: [String]
    public var furtherExploration: [String]
    public var blenderScript: String?
    public var skillName: String?
    public var painPoint: String?
    public var copyReadyPayloads: [CopyPayload]
    public var treasureLinks: [TreasureLink]
    public var gotchas: [String]
    public var sourceType: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, source, url, domain
        case ladderLevel = "ladder_level"
        case matchedProject = "matched_project"
        case focusGoal = "focus_goal"
        case oneLineEssence = "one_line_essence"
        case prerequisites
        case conceptBreakdown = "concept_breakdown"
        case keyPoints = "key_points"
        case actionableSteps = "actionable_steps"
        case projectOptimizations = "project_optimizations"
        case pitfalls
        case selfCheckQA = "self_check_qa"
        case copyableSnippets = "copyable_snippets"
        case furtherExploration = "further_exploration"
        case blenderScript = "blender_script"
        case skillName = "skill_name"
        case painPoint = "pain_point"
        case copyReadyPayloads = "copy_ready_payloads"
        case treasureLinks = "treasure_links"
        case gotchas
        case sourceType = "source_type"
        case createdAt = "created_at"
    }

    public init(
        id: String? = nil,
        title: String,
        source: String,
        url: String,
        domain: String,
        ladderLevel: String = "L1基础教程",
        matchedProject: String? = nil,
        focusGoal: String? = nil,
        oneLineEssence: String,
        prerequisites: [String] = [],
        conceptBreakdown: [ConceptItem] = [],
        keyPoints: [String] = [],
        actionableSteps: [String] = [],
        projectOptimizations: [String] = [],
        pitfalls: [String] = [],
        selfCheckQA: [QuizItem] = [],
        copyableSnippets: [String] = [],
        furtherExploration: [String] = [],
        blenderScript: String? = nil,
        skillName: String? = nil,
        painPoint: String? = nil,
        copyReadyPayloads: [CopyPayload] = [],
        treasureLinks: [TreasureLink] = [],
        gotchas: [String] = [],
        sourceType: String? = nil,
        createdAt: String = Self.nowTimestamp()
    ) {
        self.title = title
        self.source = source
        self.url = url
        self.domain = KnowledgeDomain.normalize(domain).rawValue
        self.ladderLevel = ladderLevel
        self.matchedProject = matchedProject
        self.focusGoal = focusGoal
        self.oneLineEssence = oneLineEssence
        self.prerequisites = prerequisites
        self.conceptBreakdown = conceptBreakdown
        self.keyPoints = keyPoints
        self.actionableSteps = actionableSteps
        self.projectOptimizations = projectOptimizations
        self.pitfalls = pitfalls
        self.selfCheckQA = selfCheckQA
        self.copyableSnippets = copyableSnippets
        self.furtherExploration = furtherExploration
        self.blenderScript = blenderScript
        self.skillName = skillName
        self.painPoint = painPoint
        self.copyReadyPayloads = copyReadyPayloads
        self.treasureLinks = treasureLinks
        self.gotchas = gotchas
        self.sourceType = sourceType
        self.createdAt = createdAt
        if let id, !id.isEmpty {
            self.id = id
        } else {
            self.id = Self.stableID(url: url, source: source, title: title, essence: oneLineEssence)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.source = try c.decode(String.self, forKey: .source)
        self.url = try c.decode(String.self, forKey: .url)
        self.domain = try c.decode(String.self, forKey: .domain)
        self.ladderLevel = try c.decodeIfPresent(String.self, forKey: .ladderLevel) ?? "L1基础教程"
        self.matchedProject = try c.decodeIfPresent(String.self, forKey: .matchedProject)
        self.focusGoal = try c.decodeIfPresent(String.self, forKey: .focusGoal)
        self.oneLineEssence = try c.decode(String.self, forKey: .oneLineEssence)
        self.prerequisites = try c.decodeIfPresent([String].self, forKey: .prerequisites) ?? []
        self.conceptBreakdown = try c.decodeIfPresent([ConceptItem].self, forKey: .conceptBreakdown) ?? []
        self.keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        self.actionableSteps = try c.decodeIfPresent([String].self, forKey: .actionableSteps) ?? []
        self.projectOptimizations = try c.decodeIfPresent([String].self, forKey: .projectOptimizations) ?? []
        self.pitfalls = try c.decodeIfPresent([String].self, forKey: .pitfalls) ?? []
        self.selfCheckQA = try c.decodeIfPresent([QuizItem].self, forKey: .selfCheckQA) ?? []
        self.copyableSnippets = try c.decodeIfPresent([String].self, forKey: .copyableSnippets) ?? []
        self.furtherExploration = try c.decodeIfPresent([String].self, forKey: .furtherExploration) ?? []
        self.blenderScript = try c.decodeIfPresent(String.self, forKey: .blenderScript)
        self.skillName = try c.decodeIfPresent(String.self, forKey: .skillName)
        self.painPoint = try c.decodeIfPresent(String.self, forKey: .painPoint)
        self.copyReadyPayloads = try c.decodeIfPresent([CopyPayload].self, forKey: .copyReadyPayloads) ?? []
        self.treasureLinks = try c.decodeIfPresent([TreasureLink].self, forKey: .treasureLinks) ?? []
        self.gotchas = try c.decodeIfPresent([String].self, forKey: .gotchas) ?? []
        self.sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? Self.nowTimestamp()
    }

    public var displaySkillName: String {
        if let skillName, !skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return skillName
        }
        return title
    }

    public var isSkillCardWorthy: Bool {
        if copyReadyPayloads.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if let bs = blenderScript, !bs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let hasName = !(skillName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasName && !treasureLinks.isEmpty
    }

    public var bestPayload: String {
        if let first = copyReadyPayloads.first(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return first.content
        }
        if let bs = blenderScript, !bs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bs
        }
        if !actionableSteps.isEmpty {
            return actionableSteps.map { "- \($0)" }.joined(separator: "\n")
        }
        if let snip = copyableSnippets.first, !snip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snip
        }
        return oneLineEssence
    }

    public var bestCopyText: String {
        bestPayload
    }

    public var isBlenderRelated: Bool {
        if blenderScript != nil { return true }
        if domain == KnowledgeDomain.creative3D.rawValue { return true }
        let text = "\(title) \(oneLineEssence) \(focusGoal ?? "") \(domain)".lowercased()
        let keywords = [
            "blender", "bpy", "3d", "建模", "材质", "节点", "eevee", "cycles",
            "着色器", "渲染", "拓扑", "geometry node", "几何节点", "修改器", "modifier",
            "贴图", "灯光", "雕刻", "骨骼", "权重", "uv", "动画"
        ]
        return keywords.contains { text.contains($0) }
    }

    public static func stableID(url: String, source: String, title: String, essence: String) -> String {
        if let key = URLCanonicalizer.canonicalKey(from: url) {
            return sha256Prefix("url|\(key)")
        }
        let raw = "\(source.lowercased())|\(title.lowercased())|\(essence.lowercased())"
        return sha256Prefix(raw)
    }

    public static func sha256Prefix(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    public static func nowTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: Date())
    }
}

public struct TargetWindow: Equatable, Sendable {
    public let windowID: CGWindowID
    public let appName: String
    public let title: String
    public let bvid: String?
    public let isPiliPlus: Bool
    public let matchedSite: String

    public init(
        windowID: CGWindowID,
        appName: String,
        title: String,
        bvid: String? = nil,
        isPiliPlus: Bool = false,
        matchedSite: String = ""
    ) {
        self.windowID = windowID
        self.appName = appName
        self.title = title
        self.bvid = bvid
        self.isPiliPlus = isPiliPlus
        self.matchedSite = matchedSite
    }
}

public enum URLCanonicalizer {
    private static let localHosts: Set<String> = [
        "127.0.0.1", "localhost", "0.0.0.0", "::1",
    ]

    public static func extractBVID(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\bBV[0-9A-Za-z]{10}\b"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    public static func isLocalOrPrivateURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased()
        else { return false }
        if localHosts.contains(host) || host.hasSuffix(".local") { return true }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return true }
        return false
    }

    public static func isSupportedWebURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty
        else { return false }
        return !isLocalOrPrivateURL(trimmed)
    }

    public static func canonicalKey(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLocalOrPrivateURL(trimmed) else { return nil }
        if let bvid = extractBVID(from: trimmed) {
            return "bilibili:\(bvid)"
        }
        guard var comp = URLComponents(string: trimmed),
              let scheme = comp.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = comp.host?.lowercased()
        else { return nil }
        comp.scheme = "https"
        comp.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        comp.fragment = nil
        if let items = comp.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !["spm_id_from", "vd_source", "from", "share_source", "share_medium"].contains(name)
            }
            comp.queryItems = kept.isEmpty ? nil : kept
        }
        var result = comp.string ?? trimmed
        if result.hasSuffix("/") { result.removeLast() }
        return result.lowercased()
    }
}
