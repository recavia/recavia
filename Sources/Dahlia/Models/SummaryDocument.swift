import Foundation

struct SummaryDocument: Codable, Equatable {
    var schemaVersion: Int
    var title: String
    var sections: [SummarySection]
    var tags: [String]
    var actionItems: [SummaryActionItem]

    init(
        schemaVersion: Int = 1,
        title: String,
        sections: [SummarySection],
        tags: [String] = [],
        actionItems: [SummaryActionItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.sections = sections
        self.tags = tags
        self.actionItems = actionItems
    }

    func databaseJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }
}

struct SummarySection: Codable, Equatable, Identifiable {
    var id: UUID
    var heading: String
    var blocks: [SummaryBlock]
}

struct TranscriptReference: Codable, Equatable {
    var time: String
    var label: String
}

struct SummaryBlock: Codable, Equatable, Identifiable {
    var id: UUID
    var transcriptRefs: [TranscriptReference]
    var content: SummaryBlockContent

    init(id: UUID = .v7(), transcriptRefs: [TranscriptReference] = [], content: SummaryBlockContent) {
        self.id = id
        self.transcriptRefs = transcriptRefs
        self.content = content
    }

    typealias ChecklistItem = SummaryBlockContent.ChecklistItem

    static func paragraph(_ text: String, transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .paragraph(text))
    }

    static func bulletedList(items: [String], transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .bulletedList(items: items))
    }

    static func numberedList(items: [String], transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .numberedList(items: items))
    }

    static func checklist(items: [ChecklistItem], transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .checklist(items: items))
    }

    static func quote(_ text: String, transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .quote(text))
    }

    static func code(language: String, code: String, transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .code(language: language, code: code))
    }

    static func image(screenshotId: UUID, caption: String, transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .image(screenshotId: screenshotId, caption: caption))
    }

    static func heading(level: Int, text: String, transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .heading(level: level, text: text))
    }

    static func table(headers: [String], rows: [[String]], transcriptRefs: [TranscriptReference] = []) -> SummaryBlock {
        SummaryBlock(transcriptRefs: transcriptRefs, content: .table(headers: headers, rows: rows))
    }

    static func == (lhs: SummaryBlock, rhs: SummaryBlock) -> Bool {
        lhs.transcriptRefs == rhs.transcriptRefs && lhs.content == rhs.content
    }
}

enum SummaryBlockContent: Equatable {
    case paragraph(String)
    case bulletedList(items: [String])
    case numberedList(items: [String])
    case checklist(items: [ChecklistItem])
    case quote(String)
    case code(language: String, code: String)
    case image(screenshotId: UUID, caption: String)
    case heading(level: Int, text: String)
    case table(headers: [String], rows: [[String]])

    struct ChecklistItem: Codable, Equatable {
        var text: String
        var checked: Bool
    }
}

extension SummaryBlockContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case items
        case language
        case code
        case screenshotId = "screenshot_id"
        case caption
        case level
        case headers
        case rows
    }

    private enum BlockType: String {
        case paragraph
        case bulletedList = "bulleted_list"
        case numberedList = "numbered_list"
        case checklist
        case quote
        case code
        case image
        case heading
        case table
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? BlockType.paragraph.rawValue

        switch BlockType(rawValue: type) {
        case .paragraph:
            self = .paragraph((try? container.decode(String.self, forKey: .text)) ?? "")
        case .bulletedList:
            self = .bulletedList(items: (try? container.decode([String].self, forKey: .items)) ?? [])
        case .numberedList:
            self = .numberedList(items: (try? container.decode([String].self, forKey: .items)) ?? [])
        case .checklist:
            self = .checklist(items: (try? container.decode([ChecklistItem].self, forKey: .items)) ?? [])
        case .quote:
            self = .quote((try? container.decode(String.self, forKey: .text)) ?? "")
        case .code:
            self = .code(
                language: (try? container.decode(String.self, forKey: .language)) ?? "",
                code: (try? container.decode(String.self, forKey: .code)) ?? ""
            )
        case .image:
            if let screenshotId = try? container.decode(UUID.self, forKey: .screenshotId) {
                self = .image(
                    screenshotId: screenshotId,
                    caption: (try? container.decode(String.self, forKey: .caption)) ?? ""
                )
            } else {
                self = .paragraph((try? container.decode(String.self, forKey: .caption)) ?? "")
            }
        case .heading:
            self = .heading(
                level: (try? container.decode(Int.self, forKey: .level)) ?? 3,
                text: (try? container.decode(String.self, forKey: .text)) ?? ""
            )
        case .table:
            self = .table(
                headers: (try? container.decode([String].self, forKey: .headers)) ?? [],
                rows: (try? container.decode([[String]].self, forKey: .rows)) ?? []
            )
        case nil:
            self = .paragraph((try? container.decode(String.self, forKey: .text)) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .paragraph(text):
            try container.encode(BlockType.paragraph.rawValue, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .bulletedList(items):
            try container.encode(BlockType.bulletedList.rawValue, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .numberedList(items):
            try container.encode(BlockType.numberedList.rawValue, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .checklist(items):
            try container.encode(BlockType.checklist.rawValue, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .quote(text):
            try container.encode(BlockType.quote.rawValue, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .code(language, code):
            try container.encode(BlockType.code.rawValue, forKey: .type)
            try container.encode(language, forKey: .language)
            try container.encode(code, forKey: .code)
        case let .image(screenshotId, caption):
            try container.encode(BlockType.image.rawValue, forKey: .type)
            try container.encode(screenshotId, forKey: .screenshotId)
            try container.encode(caption, forKey: .caption)
        case let .heading(level, text):
            try container.encode(BlockType.heading.rawValue, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
        case let .table(headers, rows):
            try container.encode(BlockType.table.rawValue, forKey: .type)
            try container.encode(headers, forKey: .headers)
            try container.encode(rows, forKey: .rows)
        }
    }
}

extension SummaryBlock {
    private enum CodingKeys: String, CodingKey {
        case id
        case transcriptRefs = "transcript_refs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? .v7()
        transcriptRefs = (try? container.decode([TranscriptReference].self, forKey: .transcriptRefs)) ?? []
        content = try SummaryBlockContent(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(transcriptRefs, forKey: .transcriptRefs)
        try content.encode(to: encoder)
    }
}
