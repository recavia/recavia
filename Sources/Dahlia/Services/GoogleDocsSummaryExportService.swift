import Foundation

enum GoogleDocsSummaryExportService {
    @MainActor
    static func exportSummary(
        document: SummaryDocument,
        context: SummaryRenderContext,
        fileName: String,
        driveStore: GoogleDriveStore = .shared,
        apiClient: any GoogleDriveAPIClientProviding = GoogleDriveAPIClient()
    ) async throws -> String {
        let actionItemsHeading = L10n.actionItems
        let imageUnavailableText = L10n.summaryImageUnavailable
        let rendered = await Task.detached(priority: .userInitiated) {
            GoogleDocsSummaryRenderer.render(
                document: document,
                context: context,
                actionItemsHeading: actionItemsHeading,
                imageUnavailableText: imageUnavailableText
            )
        }.value
        let properties = [
            "dahliaKind": "summary",
            "dahliaMeetingId": context.meetingId.uuidString,
        ]

        return try await driveStore.performAuthorizedOperation { session in
            try await apiClient.upsertGoogleDocument(
                accessToken: session.accessToken,
                fileName: fileName,
                data: rendered.data,
                dataMimeType: rendered.mimeType,
                appProperties: properties
            )
        }
    }
}
