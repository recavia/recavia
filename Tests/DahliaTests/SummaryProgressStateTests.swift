@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct SummaryProgressStateTests {
        @Test
        func waitsForGoogleDocsExportToReachTerminalState() {
            let state = SummaryProgressState()
            state.summaryGeneration = .completed
            state.vaultExport = .skipped

            #expect(!state.isAllDone)

            state.googleDocsExport = .completed

            #expect(state.isAllDone)
        }

        @Test
        func generationJobsKeepMeetingProgressAndFailuresIndependent() {
            let first = SummaryGenerationJob(meetingId: .v7(), meetingName: "Planning")
            let second = SummaryGenerationJob(meetingId: .v7(), meetingName: "Review")

            first.progress.summaryGeneration = .failed("offline")
            first.progress.vaultExport = .skipped
            first.progress.googleDocsExport = .skipped
            second.progress.summaryGeneration = .running

            #expect(first.hasFailure)
            #expect(first.isFinished)
            #expect(first.failureMessages == ["offline"])
            #expect(!second.hasFailure)
            #expect(second.failureMessages.isEmpty)
        }
    }
#endif
