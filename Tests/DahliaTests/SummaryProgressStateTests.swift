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
        func resetRestoresGoogleDocsExportToPending() {
            let state = SummaryProgressState()
            state.googleDocsExport = .failed("offline")

            state.reset()

            #expect(!state.googleDocsExport.isTerminal)
        }
    }
#endif
