import Foundation

enum LegacyMarkdownSummaryParser {
    static func parse(
        markdown: String,
        title: String = "",
        context: SummaryRenderContext? = nil
    ) -> SummaryDocument {
        let lines = bodyWithoutFrontmatter(markdown).components(separatedBy: "\n")
        var sections: [SummarySection] = []
        var currentSection = SummarySection(id: .v7(), heading: "", blocks: [])
        var i = 0

        func finishCurrentSection() {
            guard !currentSection.heading.isEmpty || !currentSection.blocks.isEmpty else { return }
            sections.append(currentSection)
            currentSection = SummarySection(id: .v7(), heading: "", blocks: [])
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count {
                    i += 1
                }
                currentSection.blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if isHorizontalRule(trimmed) {
                i += 1
                continue
            }

            if let match = trimmed.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                let level = match.1.count
                let normalized = normalizedTextAndRefs(String(match.2))
                if level <= 2 {
                    finishCurrentSection()
                    currentSection.heading = normalized.text
                } else {
                    currentSection.blocks.append(.heading(level: level, text: normalized.text, transcriptRefs: normalized.refs))
                }
                i += 1
                continue
            }

            if isTableStart(lines: lines, index: i) {
                var tableRefs: [TranscriptReference] = []
                let headers = parsePipeRow(trimmed).map { text in
                    let normalized = normalizedTextAndRefs(text)
                    tableRefs.append(contentsOf: normalized.refs)
                    return normalized.text
                }
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).contains("|") {
                    rows.append(parsePipeRow(lines[i]).map { text in
                        let normalized = normalizedTextAndRefs(text)
                        tableRefs.append(contentsOf: normalized.refs)
                        return normalized.text
                    })
                    i += 1
                }
                currentSection.blocks.append(.table(headers: headers, rows: rows, transcriptRefs: tableRefs))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let content = lines[i].trimmingCharacters(in: .whitespaces)
                        .replacing(/^>\s?/, with: "")
                    quoteLines.append(content)
                    i += 1
                }
                let normalized = normalizedTextAndRefs(quoteLines.joined(separator: " "))
                currentSection.blocks.append(.quote(normalized.text, transcriptRefs: normalized.refs))
                continue
            }

            if let checklistMatch = checklistItem(in: trimmed) {
                var items: [SummaryBlock.ChecklistItem] = []
                var refs: [TranscriptReference] = []
                let first = normalizedTextAndRefs(checklistMatch.text)
                refs.append(contentsOf: first.refs)
                items.append(.init(text: first.text, checked: checklistMatch.checked))
                i += 1
                while i < lines.count,
                      let next = checklistItem(in: lines[i].trimmingCharacters(in: .whitespaces)) {
                    let normalized = normalizedTextAndRefs(next.text)
                    refs.append(contentsOf: normalized.refs)
                    items.append(.init(text: normalized.text, checked: next.checked))
                    i += 1
                }
                currentSection.blocks.append(.checklist(items: items, transcriptRefs: refs))
                continue
            }

            if let item = unorderedListItem(in: trimmed) {
                var refs: [TranscriptReference] = []
                let first = normalizedTextAndRefs(item)
                refs.append(contentsOf: first.refs)
                var items = [first.text]
                i += 1
                while i < lines.count,
                      let next = unorderedListItem(in: lines[i].trimmingCharacters(in: .whitespaces)),
                      checklistItem(in: lines[i].trimmingCharacters(in: .whitespaces)) == nil {
                    let normalized = normalizedTextAndRefs(next)
                    refs.append(contentsOf: normalized.refs)
                    items.append(normalized.text)
                    i += 1
                }
                currentSection.blocks.append(.bulletedList(items: items, transcriptRefs: refs))
                continue
            }

            if let item = orderedListItem(in: trimmed) {
                var refs: [TranscriptReference] = []
                let first = normalizedTextAndRefs(item)
                refs.append(contentsOf: first.refs)
                var items = [first.text]
                i += 1
                while i < lines.count,
                      let next = orderedListItem(in: lines[i].trimmingCharacters(in: .whitespaces)) {
                    let normalized = normalizedTextAndRefs(next)
                    refs.append(contentsOf: normalized.refs)
                    items.append(normalized.text)
                    i += 1
                }
                currentSection.blocks.append(.numberedList(items: items, transcriptRefs: refs))
                continue
            }

            var paragraphLines: [String] = []
            while i < lines.count {
                let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || isBlockStart(candidate, lines: lines, index: i) {
                    break
                }
                paragraphLines.append(candidate)
                i += 1
            }
            let blocks = parseInlineBlocks(paragraphLines.joined(separator: " "), context: context)
            currentSection.blocks.append(contentsOf: blocks)
        }

        finishCurrentSection()
        return SummaryDocument(title: title, sections: sections, tags: [], actionItems: [])
    }

    static func parseInlineBlocks(_ text: String, context: SummaryRenderContext? = nil) -> [SummaryBlock] {
        let matches = obsidianImageEmbedRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else {
            let normalized = normalizeInlineMarkdown(text).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? [] : [.paragraph(normalized)]
        }

        var blocks: [SummaryBlock] = []
        var cursor = text.startIndex
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let targetRange = Range(match.range(at: 1), in: text) else { continue }

            let prefix = String(text[cursor ..< fullRange.lowerBound])
            appendParagraph(prefix, to: &blocks)

            let target = String(text[targetRange])
            let caption = if let aliasRange = Range(match.range(at: 2), in: text) {
                String(text[aliasRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                ""
            }
            let normalizedCaption = normalizedTextAndRefs(caption)
            if let screenshotId = resolvedScreenshotId(for: target, context: context) {
                blocks.append(.image(screenshotId: screenshotId, caption: normalizedCaption.text, transcriptRefs: normalizedCaption.refs))
            } else if !normalizedCaption.text.isEmpty {
                appendParagraph(caption, to: &blocks)
            }

            cursor = fullRange.upperBound
        }

        appendParagraph(String(text[cursor...]), to: &blocks)
        return blocks
    }

    static func normalizeInlineMarkdown(_ text: String) -> String {
        normalizedTextAndRefs(text).text
    }

    static func normalizedTextAndRefs(_ text: String) -> (text: String, refs: [TranscriptReference]) {
        let markdownResult = replaceTranscriptMarkdownLinks(in: text)
        let obsidianResult = replaceObsidianLinks(in: markdownResult.text)
        return (
            text: cleanupReferenceWhitespace(obsidianResult.text),
            refs: uniqueReferences(markdownResult.refs + obsidianResult.refs)
        )
    }

    private static func replaceTranscriptMarkdownLinks(in text: String) -> (text: String, refs: [TranscriptReference]) {
        let matches = transcriptMarkdownLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return (text, []) }

        var refs: [TranscriptReference] = []
        var normalized = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: normalized),
                  let labelRange = Range(match.range(at: 1), in: normalized),
                  let timeRange = Range(match.range(at: 2), in: normalized) else { continue }

            let label = String(normalized[labelRange])
            let time = String(normalized[timeRange])
            refs.append(TranscriptReference(time: time, label: label))
            normalized.replaceSubrange(fullRange, with: label == time ? "" : label)
        }

        return (normalized, Array(refs.reversed()))
    }

    private static func replaceObsidianLinks(in text: String) -> (text: String, refs: [TranscriptReference]) {
        let matches = obsidianLinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return (text, []) }

        var refs: [TranscriptReference] = []
        var normalized = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: normalized),
                  let targetRange = Range(match.range(at: 1), in: normalized) else { continue }

            let target = String(normalized[targetRange])
            let alias = Range(match.range(at: 2), in: normalized).map { String(normalized[$0]) }
            let parsed = transcriptReference(for: target, alias: alias)
            if let ref = parsed.ref {
                refs.append(ref)
            }
            let replacement = if let ref = parsed.ref, parsed.replacement == ref.time {
                ""
            } else {
                parsed.replacement
            }
            normalized.replaceSubrange(fullRange, with: replacement)
        }

        return (normalized, Array(refs.reversed()))
    }

    private static let obsidianImageEmbedRegex = try! NSRegularExpression(
        pattern: #"\!\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#
    )

    private static let transcriptMarkdownLinkRegex = try! NSRegularExpression(
        pattern: #"\[([^\]]+)\]\(transcript://([0-9]{2}:[0-9]{2}:[0-9]{2})\)"#
    )

    private static let obsidianLinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#
    )

    private static func bodyWithoutFrontmatter(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else {
            return markdown
        }

        let bodyStart = lines.index(after: closingIndex)
        guard bodyStart < lines.endIndex else { return "" }
        return lines[bodyStart...].joined(separator: "\n")
    }

    private static func appendParagraph(_ text: String, to blocks: inout [SummaryBlock]) {
        let normalized = normalizedTextAndRefs(text)
        let paragraph = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph, transcriptRefs: normalized.refs))
    }

    private static func resolvedScreenshotId(for target: String, context: SummaryRenderContext?) -> UUID? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let component = (trimmed as NSString).lastPathComponent as NSString
        let stem = component.deletingPathExtension
        guard let id = UUID(uuidString: stem) else { return nil }

        if let context, !context.screenshots.contains(where: { $0.id == id }) {
            return nil
        }
        return id
    }

    private static func transcriptReference(for target: String, alias: String?) -> (replacement: String, ref: TranscriptReference?) {
        guard let hashIndex = target.lastIndex(of: "#") else {
            return (alias ?? "", nil)
        }
        let timestamp = String(target[target.index(after: hashIndex)...])
        guard timestamp.firstMatch(of: /^\d{2}:\d{2}:\d{2}$/) != nil else {
            return (alias ?? "", nil)
        }
        let label = alias?.nilIfBlank ?? timestamp
        return (label, TranscriptReference(time: timestamp, label: label))
    }

    private static func cleanupReferenceWhitespace(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueReferences(_ refs: [TranscriptReference]) -> [TranscriptReference] {
        var seen: Set<String> = []
        return refs.filter { ref in
            let key = "\(ref.time)\u{0}\(ref.label)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func isBlockStart(_ line: String, lines: [String], index: Int) -> Bool {
        line.hasPrefix("```")
            || isHorizontalRule(line)
            || line.firstMatch(of: /^#{1,6}\s+.+$/) != nil
            || isTableStart(lines: lines, index: index)
            || line.hasPrefix(">")
            || checklistItem(in: line) != nil
            || unorderedListItem(in: line) != nil
            || orderedListItem(in: line) != nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.allSatisfy { $0 == "-" || $0 == " " } && line.count(where: { $0 == "-" }) >= 3
    }

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|")
            && separator.contains("|")
            && separator.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            .isEmpty
            && separator.contains("-")
    }

    private static func checklistItem(in line: String) -> (text: String, checked: Bool)? {
        guard let match = line.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.+)$/) else { return nil }
        let marker = String(match.1)
        return (String(match.2), marker.lowercased() == "x")
    }

    private static func unorderedListItem(in line: String) -> String? {
        guard let match = line.firstMatch(of: /^[-*+]\s+(.+)$/) else { return nil }
        return String(match.1)
    }

    private static func orderedListItem(in line: String) -> String? {
        guard let match = line.firstMatch(of: /^\d+\.\s+(.+)$/) else { return nil }
        return String(match.1)
    }

    private static func parsePipeRow(_ line: String) -> [String] {
        line.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
