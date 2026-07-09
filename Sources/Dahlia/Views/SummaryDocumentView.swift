import AppKit
import SwiftUI

struct SummaryDocumentView: View {
    let document: SummaryDocument
    let imageProvider: (UUID) -> NSImage?
    let transcriptTextProvider: (TranscriptReference) -> String?

    init(
        document: SummaryDocument,
        imageProvider: @escaping (UUID) -> NSImage?,
        transcriptTextProvider: @escaping (TranscriptReference) -> String? = { _ in nil }
    ) {
        self.document = document
        self.imageProvider = imageProvider
        self.transcriptTextProvider = transcriptTextProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !document.title.isEmpty {
                inlineMarkdownText(document.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }

            ForEach(document.sections) { section in
                sectionView(section)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func sectionView(_ section: SummarySection) -> some View {
        if !section.heading.isEmpty {
            inlineMarkdownText(section.heading)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }

        ForEach(section.blocks) { block in
            blockView(block)
        }
    }

    private func blockView(_ block: SummaryBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch block.content {
            case let .paragraph(text):
                inlineMarkdownText(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case let .bulletedList(items):
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            inlineMarkdownText(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                }
                .padding(.leading, 8)
            case let .numberedList(items):
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).")
                                .monospacedDigit()
                            inlineMarkdownText(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                }
                .padding(.leading, 8)
            case let .checklist(items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: item.checked ? "checkmark.square" : "square")
                                .foregroundStyle(item.checked ? .secondary : .tertiary)
                            inlineMarkdownText(item.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                }
                .padding(.leading, 8)
            case let .quote(text):
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                    inlineMarkdownText(text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 8)
                }
                .padding(.vertical, 2)
            case let .code(_, code):
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            case let .image(screenshotId, caption):
                imageView(screenshotId: screenshotId, caption: caption)
            case let .heading(level, text):
                headingView(level: level, text: text)
            case let .table(headers, rows):
                tableView(headers: headers, rows: rows)
            }

            transcriptReferencesView(block.transcriptRefs)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1, 2:
            inlineMarkdownText(text)
                .font(.title3.bold())
                .padding(.top, 4)
        case 3:
            inlineMarkdownText(text)
                .font(.headline)
                .padding(.top, 2)
        default:
            inlineMarkdownText(text)
                .font(.subheadline.bold())
                .padding(.top, 2)
        }
    }

    private func imageView(screenshotId: UUID, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = imageProvider(screenshotId) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(L10n.summaryImageUnavailable)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            if !caption.isEmpty {
                inlineMarkdownText(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inlineMarkdownText(cell)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
            }
        }
        .border(Color.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func transcriptReferencesView(_ refs: [TranscriptReference]) -> some View {
        if !refs.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                    TranscriptReferenceChip(
                        reference: ref,
                        transcriptText: transcriptTextProvider(ref)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func inlineMarkdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

}

private struct TranscriptReferenceChip: View {
    let reference: TranscriptReference
    let transcriptText: String?

    @State private var isTranscriptPopoverPresented = false

    var body: some View {
        Text(reference.time)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .onHover { isHovering in
                isTranscriptPopoverPresented = isHovering && transcriptText?.nilIfBlank != nil
            }
            .popover(isPresented: $isTranscriptPopoverPresented, arrowEdge: .bottom) {
                if let transcriptText = transcriptText?.nilIfBlank {
                    Text(transcriptText)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280, alignment: .leading)
                        .padding(10)
                }
            }
    }
}
