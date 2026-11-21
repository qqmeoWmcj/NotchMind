import Foundation

/// Verbatim, ready-to-use payload extracted from materials (prompts, scripts, commands, configs).
public struct CopyPayload: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(type)_\(label)_\(content.prefix(16))" }
    public let type: String       // "prompt" | "script" | "command" | "params" | "workflow"
    public let label: String      // Short human-readable label
    public let content: String    // Exact, ready-to-paste verbatim code / prompt
    public let sourceNote: String?

    enum CodingKeys: String, CodingKey {
        case type, label, content
        case sourceNote = "source_note"
    }

    public init(type: String, label: String, content: String, sourceNote: String? = nil) {
        self.type = type
        self.label = label
        self.content = content
        self.sourceNote = sourceNote
    }
}

/// External treasure tool, repository, or tutorial link discovered in posts or comments.
public struct TreasureLink: Codable, Sendable, Identifiable, Equatable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let why: String?

    enum CodingKeys: String, CodingKey {
        case title, url, why
    }

    public init(title: String, url: String, why: String? = nil) {
        self.title = title
        self.url = url
        self.why = why
    }
}
