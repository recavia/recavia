import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SummaryDocumentCodableTests {
        @Test
        func summaryDocumentRoundTrips() throws {
            let imageId = UUID.v7()
            let sectionId = UUID.v7()
            let document = SummaryDocument(
                title: "Weekly sync",
                sections: [
                    SummarySection(
                        id: sectionId,
                        heading: "Decisions",
                        blocks: [
                            .paragraph(
                                "Ship",
                                transcriptRefs: [TranscriptReference(time: "00:10:00", label: "Decision")]
                            ),
                            .bulletedList(items: ["One", "Two"]),
                            .numberedList(items: ["First"]),
                            .checklist(items: [.init(text: "Send notes", checked: false)]),
                            .quote("Important"),
                            .code(language: "swift", code: "let value = 1"),
                            .image(screenshotId: imageId, caption: "Screen"),
                            .heading(level: 3, text: "Details"),
                            .table(headers: ["A", "B"], rows: [["1", "2"]]),
                        ]
                    ),
                ],
                tags: ["team"],
                actionItems: [SummaryActionItem(title: "Send notes", assignee: "me")]
            )

            let data = try JSONEncoder().encode(document)
            let decoded = try JSONDecoder().decode(SummaryDocument.self, from: data)

            #expect(decoded == document)
        }

        @Test
        func unknownBlockTypeFallsBackToParagraph() throws {
            let json = """
            {
              "schemaVersion": 1,
              "title": "Title",
              "sections": [
                {
                  "id": "\(UUID.v7().uuidString)",
                  "heading": "",
                  "blocks": [
                    {
                      "type": "callout",
                      "text": "Future block"
                    }
                  ]
                }
              ],
              "tags": [],
              "actionItems": []
            }
            """

            let document = try JSONDecoder().decode(SummaryDocument.self, from: Data(json.utf8))

            #expect(document.sections.first?.blocks == [.paragraph("Future block")])
        }

        @Test
        func decodesPersistedSummaryDocumentShape() throws {
            let imageId = UUID.v7()
            let json = """
            {
              "actionItems": [
                {
                  "assignee": "勝倉さん",
                  "title": "宿題をフォローアップする"
                }
              ],
              "schemaVersion": 1,
              "sections": [
                {
                  "blocks": [
                    {
                      "caption": "共有資料のスクリーンショット",
                      "id": "\(UUID.v7().uuidString)",
                      "screenshot_id": "\(imageId.uuidString)",
                      "transcript_refs": [
                        {
                          "label": "会議開始",
                          "time": "00:00:11"
                        }
                      ],
                      "type": "image"
                    }
                  ],
                  "heading": "",
                  "id": "\(UUID.v7().uuidString)"
                },
                {
                  "blocks": [
                    {
                      "id": "\(UUID.v7().uuidString)",
                      "items": [
                        "Lakebaseは**常時稼働ワークロードにはコスパが悪くなりやすい**。",
                        "ピークが高いワークロードにはフィットしやすい。"
                      ],
                      "transcript_refs": [
                        {
                          "label": "常時稼働は不向き",
                          "time": "00:02:32"
                        }
                      ],
                      "type": "bulleted_list"
                    },
                    {
                      "id": "\(UUID.v7().uuidString)",
                      "items": [
                        {
                          "checked": false,
                          "text": "次回アポを調整する。"
                        }
                      ],
                      "transcript_refs": [
                        {
                          "label": "宿題フォロー",
                          "time": "00:08:38"
                        }
                      ],
                      "type": "checklist"
                    }
                  ],
                  "heading": "Lakebaseの適用方針",
                  "id": "\(UUID.v7().uuidString)"
                }
              ],
              "tags": ["Databricks", "Lakebase"],
              "title": "マイポックス様向けLakebase提案相談"
            }
            """

            let document = try JSONDecoder().decode(SummaryDocument.self, from: Data(json.utf8))

            #expect(document.title == "マイポックス様向けLakebase提案相談")
            #expect(document.actionItems == [SummaryActionItem(title: "宿題をフォローアップする", assignee: "勝倉さん")])
            #expect(document.sections.count == 2)
            #expect(document.sections[0].blocks == [
                .image(
                    screenshotId: imageId,
                    caption: "共有資料のスクリーンショット",
                    transcriptRefs: [TranscriptReference(time: "00:00:11", label: "会議開始")]
                ),
            ])
            #expect(document.sections[1].blocks == [
                .bulletedList(
                    items: [
                        "Lakebaseは**常時稼働ワークロードにはコスパが悪くなりやすい**。",
                        "ピークが高いワークロードにはフィットしやすい。",
                    ],
                    transcriptRefs: [TranscriptReference(time: "00:02:32", label: "常時稼働は不向き")]
                ),
                .checklist(
                    items: [.init(text: "次回アポを調整する。", checked: false)],
                    transcriptRefs: [TranscriptReference(time: "00:08:38", label: "宿題フォロー")]
                ),
            ])
        }
    }
#endif
