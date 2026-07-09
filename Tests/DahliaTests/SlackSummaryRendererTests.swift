import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SlackSummaryRendererTests {
        @Test
        func rendersSlackReadySummaryWithoutTranscriptReferences() {
            let document = SummaryDocument(
                title: "Weekly Sync",
                sections: [
                    SummarySection(
                        id: UUID.v7(),
                        heading: "Summary",
                        blocks: [
                            .paragraph(SummaryText("Ship **alpha** based on [decision](transcript://00:10:00).")),
                            .bulletedList(items: [
                                SummaryText("Confirm rollout", transcriptRef: TranscriptReference(time: "00:11:00")),
                            ]),
                            .numberedList(items: [
                                SummaryText("Prepare notes"),
                            ]),
                            .checklist(items: [
                                SummaryBlock.ChecklistItem(text: SummaryText("Follow up"), checked: false),
                            ]),
                            .quote(SummaryText("Keep launch small")),
                            .code(language: "swift", content: SummaryText("let enabled = true")),
                        ]
                    ),
                ]
            )

            let rendered = SlackSummaryRenderer.render(document: document, actionItemsHeading: "Action Items")

            #expect(rendered.contains("*Weekly Sync*"))
            #expect(rendered.contains("*Summary*"))
            #expect(rendered.contains("Ship *alpha* based on decision."))
            #expect(rendered.contains("- Confirm rollout"))
            #expect(rendered.contains("1. Prepare notes"))
            #expect(rendered.contains("- [ ] Follow up"))
            #expect(rendered.contains("> Keep launch small"))
            #expect(rendered.contains("```\nlet enabled = true\n```"))
            #expect(!rendered.contains("transcript://"))
            #expect(!rendered.contains("00:11:00"))
        }

        @Test
        func appendsStructuredActionItems() {
            let document = SummaryDocument(
                title: "",
                sections: [],
                actionItems: [
                    SummaryActionItem(title: "Send proposal", assignee: "Aki"),
                    SummaryActionItem(title: "Schedule review", assignee: ""),
                ]
            )

            let rendered = SlackSummaryRenderer.render(document: document, actionItemsHeading: "Action Items")

            #expect(rendered == """
            *Action Items*
            - [ ] Send proposal (Aki)
            - [ ] Schedule review
            """)
        }
    }
#endif
