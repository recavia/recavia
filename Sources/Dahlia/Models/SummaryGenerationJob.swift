import Foundation

/// A single meeting-scoped summary generation and its optional exports.
@MainActor @Observable
final class SummaryGenerationJob: Identifiable {
    let id = UUID.v7()
    let meetingId: UUID
    let meetingName: String
    let startedAt: Date
    let progress = SummaryProgressState()

    init(meetingId: UUID, meetingName: String, startedAt: Date = .now) {
        self.meetingId = meetingId
        self.meetingName = meetingName
        self.startedAt = startedAt
    }

    var hasFailure: Bool {
        stepStatuses.contains(where: \.isFailed)
    }

    var failureMessages: [String] {
        stepStatuses.compactMap(\.failureMessage)
    }

    var isFinished: Bool {
        stepStatuses.allSatisfy(\.isTerminal)
    }

    private var stepStatuses: [SummaryProgressState.StepStatus] {
        [progress.summaryGeneration, progress.vaultExport, progress.googleDocsExport]
    }
}
