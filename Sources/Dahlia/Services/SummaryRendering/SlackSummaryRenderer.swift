import Foundation

enum SlackSummaryRenderer {
    static func render(document: SummaryDocument, actionItemsHeading: String) -> String {
        var chunks: [String] = []

        if let title = renderInlineText(document.title).nilIfBlank {
            chunks.append("*\(title)*")
        }

        chunks.append(contentsOf: document.sections.compactMap(renderSection))

        if let actionItems = renderActionItems(document.actionItems, heading: actionItemsHeading) {
            chunks.append(actionItems)
        }

        return chunks
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderSection(_ section: SummarySection) -> String? {
        var chunks: [String] = []

        if let heading = renderInlineText(section.heading).nilIfBlank {
            chunks.append("*\(heading)*")
        }

        chunks.append(contentsOf: section.blocks.compactMap(renderBlock))

        return chunks
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .nilIfBlank
    }

    private static func renderBlock(_ block: SummaryBlock) -> String? {
        switch block.content {
        case let .paragraph(text):
            return renderInlineText(text.text).nilIfBlank
        case let .bulletedList(items):
            return renderList(items.map(\.text), prefix: "- ")
        case let .numberedList(items):
            let lines = items.enumerated().compactMap { index, item in
                renderInlineText(item.text).nilIfBlank.map { "\(index + 1). \($0)" }
            }
            return lines.joined(separator: "\n").nilIfBlank
        case let .checklist(items):
            let lines = items.compactMap { item in
                renderInlineText(item.text.text).nilIfBlank.map { "- [\(item.checked ? "x" : " ")] \($0)" }
            }
            return lines.joined(separator: "\n").nilIfBlank
        case let .quote(text):
            let lines = renderInlineText(text.text)
                .components(separatedBy: .newlines)
                .compactMap(\.nilIfBlank)
                .map { "> \($0)" }
            return lines.joined(separator: "\n").nilIfBlank
        case let .code(_, content):
            guard let code = content.text.nilIfBlank else { return nil }
            return "```\n\(code)\n```"
        case let .image(_, caption):
            return renderInlineText(caption.text).nilIfBlank
        case let .heading(_, content):
            return renderInlineText(content.text).nilIfBlank.map { "*\($0)*" }
        case let .table(headers, rows):
            return renderTable(headers: headers, rows: rows)
        }
    }

    private static func renderList(_ items: [String], prefix: String) -> String? {
        let lines = items.compactMap { item in
            renderInlineText(item).nilIfBlank.map { "\(prefix)\($0)" }
        }
        return lines.joined(separator: "\n").nilIfBlank
    }

    private static func renderTable(headers: [SummaryText], rows: [[SummaryText]]) -> String? {
        guard !headers.isEmpty else { return nil }

        let headerTexts = headers.map { renderInlineText($0.text) }
        let lines = rows.compactMap { row -> String? in
            let cells = zip(headerTexts, row).compactMap { header, cell -> String? in
                guard let header = header.nilIfBlank,
                      let value = renderInlineText(cell.text).nilIfBlank else { return nil }
                return "\(header): \(value)"
            }
            return cells.isEmpty ? nil : "- \(cells.joined(separator: "; "))"
        }

        return lines.joined(separator: "\n").nilIfBlank
    }

    private static func renderActionItems(_ actionItems: [SummaryActionItem], heading: String) -> String? {
        let lines = actionItems.compactMap { item -> String? in
            guard let title = renderInlineText(item.title).nilIfBlank else { return nil }
            if let assignee = renderInlineText(item.assignee).nilIfBlank {
                return "- [ ] \(title) (\(assignee))"
            }
            return "- [ ] \(title)"
        }

        guard !lines.isEmpty else { return nil }
        return (["*\(renderInlineText(heading))*"] + lines).joined(separator: "\n")
    }

    private static func renderInlineText(_ text: String) -> String {
        var rendered = text.trimmingCharacters(in: .whitespacesAndNewlines)
        rendered = replaceMatches(
            in: rendered,
            pattern: #"\[([^\]]+)\]\(transcript://[0-9]{2}:[0-9]{2}:[0-9]{2}\)"#
        ) { match, source in
            guard let labelRange = Range(match.range(at: 1), in: source) else { return "" }
            return String(source[labelRange])
        }
        rendered = replaceMatches(
            in: rendered,
            pattern: #"\!\[([^\]]*)\]\([^)]+\)"#
        ) { match, source in
            guard let labelRange = Range(match.range(at: 1), in: source) else { return "" }
            return String(source[labelRange])
        }
        rendered = replaceMatches(
            in: rendered,
            pattern: #"\[([^\]]+)\]\(([^)]+)\)"#
        ) { match, source in
            guard let labelRange = Range(match.range(at: 1), in: source),
                  let urlRange = Range(match.range(at: 2), in: source) else { return "" }
            return "<\(source[urlRange])|\(source[labelRange])>"
        }
        return rendered.replacingOccurrences(of: "**", with: "*")
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var rendered = text
        let matches = regex.matches(in: rendered, range: NSRange(rendered.startIndex..., in: rendered))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 0), in: rendered) else { continue }
            rendered.replaceSubrange(range, with: replacement(match, rendered))
        }
        return rendered
    }
}
