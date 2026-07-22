import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    @Suite(.serialized)
    struct CaptionViewModelSummaryGenerationTests {
        @Test
        func differentMeetingsRunConcurrentlyAndOnlyUpdateTheirOwnSelection() async throws {
            let fixture = try SummaryGenerationFixture()
            defer { fixture.removeFiles() }
            let runner = BlockingSummaryRunner()
            let viewModel = CaptionViewModel(summaryGenerationRunner: runner.run)
            let options = SummaryGenerationOptions(
                previousMeetingCount: 0,
                exportOptions: SummaryExportOptions(exportsToVault: false, exportsToGoogleDocs: false)
            )

            await fixture.select(fixture.first, in: viewModel, note: "first note")
            viewModel.triggerManualSummary(options: options)
            await runner.waitForCallCount(1)

            await fixture.select(fixture.second, in: viewModel, note: "second note")
            viewModel.triggerManualSummary(options: options)
            await runner.waitForCallCount(2)

            #expect(viewModel.summaryGeneratingMeetingIDs == [fixture.first.id, fixture.second.id])
            #expect(runner.calls.map(\.meetingID) == [fixture.first.id, fixture.second.id])
            #expect(runner.calls.map(\.noteText) == ["first note", "second note"])

            runner.complete(meetingID: fixture.first.id, title: "First summary")
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: fixture.first.id) })
            #expect(viewModel.isSummaryGenerating(meetingId: fixture.second.id))
            #expect(viewModel.currentSummaryDocument == nil)

            runner.complete(meetingID: fixture.second.id, title: "Second summary")
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: fixture.second.id) })
            #expect(viewModel.currentSummaryDocument?.title == "Second summary")

            let firstStored = try fixture.summary(for: fixture.first.id)
            let secondStored = try fixture.summary(for: fixture.second.id)
            #expect(try firstStored?.loadDocument().title == "First summary")
            #expect(try secondStored?.loadDocument().title == "Second summary")
        }

        @Test
        func settingsAreFrozenAndFailedJobSurvivesRetryUntilDismissed() async throws {
            let fixture = try SummaryGenerationFixture()
            defer { fixture.removeFiles() }
            let runner = BlockingSummaryRunner()
            let sleeper = ControlledSummaryJobSleeper()
            let settings = AppSettings.shared
            let originalModel = settings.codexModelID
            let originalEffort = settings.codexReasoningEffort
            settings.codexModelID = "frozen-model"
            settings.codexReasoningEffort = "high"
            defer {
                settings.codexModelID = originalModel
                settings.codexReasoningEffort = originalEffort
            }
            let viewModel = CaptionViewModel(
                summaryGenerationRunner: runner.run,
                summaryJobSleeper: sleeper.sleep
            )
            let options = SummaryGenerationOptions(
                previousMeetingCount: 0,
                exportOptions: SummaryExportOptions(exportsToVault: false, exportsToGoogleDocs: false)
            )
            await fixture.select(fixture.first, in: viewModel, note: "note")

            viewModel.triggerManualSummary(options: options)
            await runner.waitForCallCount(1)
            settings.codexModelID = "changed-model"
            settings.codexReasoningEffort = "low"
            #expect(runner.calls[0].settings.modelID == "frozen-model")
            #expect(runner.calls[0].settings.reasoningEffort == "high")

            runner.fail(meetingID: fixture.first.id)
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: fixture.first.id) })
            let failedJobID = try #require(viewModel.summaryGenerationJobs.first(where: \.hasFailure)?.id)

            viewModel.triggerManualSummary(options: options)
            await runner.waitForCallCount(2)
            #expect(viewModel.summaryGenerationJobs.contains { $0.id == failedJobID })
            #expect(viewModel.summaryGenerationJobs.count == 2)

            runner.complete(meetingID: fixture.first.id, title: "Recovered")
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: fixture.first.id) })
            await sleeper.waitUntilSleeping()
            #expect(viewModel.summaryGenerationJobs.count == 2)
            await sleeper.resume()
            #expect(await waitUntil { viewModel.summaryGenerationJobs.count == 1 })
            #expect(viewModel.summaryGenerationJobs[0].id == failedJobID)

            viewModel.dismissSummaryGenerationJob(failedJobID)
            #expect(viewModel.summaryGenerationJobs.isEmpty)
        }

        @Test
        func automaticRequestsWaitForTheirSessionsAndCoalesceAfterTheActiveJob() async throws {
            let fixture = try SummaryGenerationFixture()
            defer { fixture.removeFiles() }
            let runner = BlockingSummaryRunner()
            let viewModel = CaptionViewModel(summaryGenerationRunner: runner.run)
            let options = SummaryGenerationOptions(
                previousMeetingCount: 0,
                exportOptions: SummaryExportOptions(exportsToVault: false, exportsToGoogleDocs: false)
            )
            await fixture.select(fixture.first, in: viewModel, note: "manual")
            viewModel.triggerManualSummary(options: options)
            await runner.waitForCallCount(1)
            await fixture.select(fixture.second, in: viewModel, note: "visible")

            let firstSessionID = try fixture.insertRecordingSession(for: fixture.first, offset: 0)
            let secondSessionID = UUID.v7()
            viewModel.registerPendingBatchSummaryForTesting(
                sessionID: firstSessionID,
                meetingID: fixture.first.id,
                options: options,
                dbQueue: fixture.database.dbQueue,
                vaultURL: fixture.vaultURL
            )
            viewModel.registerPendingBatchSummaryForTesting(
                sessionID: secondSessionID,
                meetingID: fixture.first.id,
                options: options,
                dbQueue: fixture.database.dbQueue,
                vaultURL: fixture.vaultURL
            )
            await viewModel.handleBatchTranscriptionUpdate(.init(
                meetingId: fixture.first.id,
                state: .completed(sessionId: firstSessionID)
            ))
            #expect(runner.calls.count == 1)

            runner.complete(meetingID: fixture.first.id, title: "Manual")
            await runner.waitForCallCount(2)
            #expect(runner.calls[1].recordingSessionIDs == [firstSessionID])

            _ = try fixture.insertRecordingSession(
                for: fixture.first,
                id: secondSessionID,
                offset: 60
            )
            await viewModel.handleBatchTranscriptionUpdate(.init(
                meetingId: fixture.first.id,
                state: .completed(sessionId: secondSessionID)
            ))
            #expect(runner.calls.count == 2)

            runner.complete(meetingID: fixture.first.id, title: "First automatic")
            await runner.waitForCallCount(3)
            #expect(Set(runner.calls[2].recordingSessionIDs) == [firstSessionID, secondSessionID])
            runner.complete(meetingID: fixture.first.id, title: "Second automatic")
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: fixture.first.id) })
            #expect(runner.calls.count == 3)
            #expect(viewModel.currentMeetingId == fixture.second.id)
            #expect(viewModel.currentSummaryDocument == nil)
        }

        @Test
        func backgroundPreparationFailureCreatesDismissibleJob() async throws {
            let fixture = try SummaryGenerationFixture()
            defer { fixture.removeFiles() }
            let viewModel = CaptionViewModel()
            let missingMeetingID = UUID.v7()
            let sessionID = UUID.v7()
            viewModel.registerPendingBatchSummaryForTesting(
                sessionID: sessionID,
                meetingID: missingMeetingID,
                options: SummaryGenerationOptions(
                    previousMeetingCount: 0,
                    exportOptions: SummaryExportOptions(exportsToVault: false, exportsToGoogleDocs: false)
                ),
                dbQueue: fixture.database.dbQueue,
                vaultURL: fixture.vaultURL
            )

            await viewModel.handleBatchTranscriptionUpdate(.init(
                meetingId: missingMeetingID,
                state: .completed(sessionId: sessionID)
            ))

            let failedJob = try #require(viewModel.summaryGenerationJobs.first)
            #expect(failedJob.meetingId == missingMeetingID)
            #expect(failedJob.hasFailure)
            #expect(failedJob.isFinished)
            viewModel.dismissSummaryGenerationJob(failedJob.id)
            #expect(viewModel.summaryGenerationJobs.isEmpty)
        }

        @Test
        func batchConfirmationKeepsOriginalDatabaseAndVaultAfterNavigation() async throws {
            let original = try SummaryGenerationFixture()
            let destination = try SummaryGenerationFixture()
            defer {
                original.removeFiles()
                destination.removeFiles()
            }
            let runner = BlockingSummaryRunner()
            let viewModel = CaptionViewModel(summaryGenerationRunner: runner.run)
            let options = SummaryGenerationOptions(
                previousMeetingCount: 0,
                exportOptions: SummaryExportOptions(exportsToVault: false, exportsToGoogleDocs: false)
            )
            await original.select(original.first, in: viewModel, note: "original")
            let sessionID = try original.insertRecordingSession(for: original.first, offset: 0)
            viewModel.presentBatchTranscriptionConfirmation(
                sessionId: sessionID,
                meetingId: original.first.id,
                dbQueue: original.database.dbQueue
            )

            await destination.select(destination.first, in: viewModel, note: "destination")
            viewModel.confirmPendingBatchSummaryForTesting(
                sessionID: sessionID,
                meetingID: original.first.id,
                options: options
            )
            await viewModel.handleBatchTranscriptionUpdate(.init(
                meetingId: original.first.id,
                state: .completed(sessionId: sessionID)
            ))
            await runner.waitForCallCount(1)

            #expect(runner.calls[0].meetingID == original.first.id)
            runner.complete(meetingID: original.first.id, title: "Original summary")
            #expect(await waitUntil { !viewModel.isSummaryGenerating(meetingId: original.first.id) })
            #expect(try original.summary(for: original.first.id) != nil)
            #expect(try destination.summary(for: original.first.id) == nil)
            #expect(viewModel.currentMeetingId == destination.first.id)
            #expect(viewModel.currentSummaryDocument == nil)
        }

        private func waitUntil(
            attempts: Int = 200,
            condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            for _ in 0 ..< attempts {
                if condition() { return true }
                await Task.yield()
            }
            return condition()
        }
    }

    @MainActor
    private final class BlockingSummaryRunner {
        struct Call {
            let meetingID: UUID
            let noteText: String?
            let settings: SummaryGenerationSettings
            let recordingSessionIDs: [UUID]
        }

        enum TestError: Error {
            case failed
        }

        private(set) var calls: [Call] = []
        private var continuations: [UUID: CheckedContinuation<Result<SummaryService.GeneratedSummary, Error>, Never>] = [:]
        private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        func run(_ input: SummaryGenerationRunnerInput) async throws -> SummaryService.GeneratedSummary {
            calls.append(Call(
                meetingID: input.promptContext.meetingId,
                noteText: input.noteText,
                settings: input.generationSettings,
                recordingSessionIDs: input.recordingSessions.map(\.id)
            ))
            resumeCallWaiters()
            let result = await withCheckedContinuation { continuation in
                continuations[input.promptContext.meetingId] = continuation
            }
            return try result.get()
        }

        func waitForCallCount(_ count: Int) async {
            if calls.count >= count { return }
            await withCheckedContinuation { continuation in
                callWaiters.append((count, continuation))
            }
        }

        func complete(meetingID: UUID, title: String) {
            continuations.removeValue(forKey: meetingID)?.resume(returning: .success(.init(
                document: SummaryDocument(title: title, sections: []),
                fileName: "summary.md",
                markdown: title
            )))
        }

        func fail(meetingID: UUID) {
            continuations.removeValue(forKey: meetingID)?.resume(returning: .failure(TestError.failed))
        }

        private func resumeCallWaiters() {
            let ready = callWaiters.filter { calls.count >= $0.count }
            callWaiters.removeAll { calls.count >= $0.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    private actor ControlledSummaryJobSleeper {
        private var continuation: CheckedContinuation<Void, Never>?
        private var waiter: CheckedContinuation<Void, Never>?

        func sleep(for _: Duration) async throws {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                waiter?.resume()
                waiter = nil
            }
        }

        func waitUntilSleeping() async {
            if continuation != nil { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class SummaryGenerationFixture {
        let database: AppDatabaseManager
        let vault: VaultRecord
        let vaultURL: URL
        let first: MeetingRecord
        let second: MeetingRecord

        init() throws {
            database = try AppDatabaseManager(path: ":memory:")
            vaultURL = FileManager.default.temporaryDirectory
                .appending(path: "dahlia-summary-vm-\(UUID.v7())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            let now = Date(timeIntervalSince1970: 1_776_384_000)
            vault = VaultRecord(id: .v7(), path: vaultURL.path, name: "Test", createdAt: now, lastOpenedAt: now)
            first = MeetingRecord(
                id: .v7(), vaultId: vault.id, projectId: nil, name: "First", createdAt: now, updatedAt: now
            )
            second = MeetingRecord(
                id: .v7(),
                vaultId: vault.id,
                projectId: nil,
                name: "Second",
                createdAt: now.addingTimeInterval(60),
                updatedAt: now.addingTimeInterval(60)
            )
            let firstSegment = TranscriptSegment(
                startTime: now, text: "first transcript", isConfirmed: true, speakerLabel: "mic"
            )
            let secondSegment = TranscriptSegment(
                startTime: now.addingTimeInterval(60), text: "second transcript", isConfirmed: true, speakerLabel: "mic"
            )
            try database.dbQueue.write { db in
                try vault.insert(db)
                try first.insert(db)
                try second.insert(db)
                try TranscriptSegmentRecord(from: firstSegment, meetingId: first.id).insert(db)
                try TranscriptSegmentRecord(from: secondSegment, meetingId: second.id).insert(db)
            }
        }

        func select(_ meeting: MeetingRecord, in viewModel: CaptionViewModel, note: String) async {
            viewModel.loadMeeting(
                meeting.id,
                dbQueue: database.dbQueue,
                projectURL: nil,
                projectId: nil,
                vaultURL: vaultURL
            )
            for _ in 0 ..< 200 {
                if viewModel.currentMeetingId == meeting.id,
                   viewModel.currentMeetingHasTranscriptSegments { break }
                await Task.yield()
            }
            viewModel.noteText = note
        }

        func summary(for meetingID: UUID) throws -> SummaryRecord? {
            try database.dbQueue.read { db in
                try SummaryRecord.fetchOne(db, key: meetingID)
            }
        }

        func insertRecordingSession(
            for meeting: MeetingRecord,
            id: UUID = .v7(),
            offset: TimeInterval
        ) throws -> UUID {
            let startedAt = meeting.createdAt.addingTimeInterval(offset)
            let session = RecordingSessionRecord(
                id: id,
                meetingId: meeting.id,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(30),
                duration: 30,
                offsetSeconds: offset,
                createdAt: startedAt,
                updatedAt: startedAt,
                transcriptionMode: .batch,
                retainAudioAfterBatch: false,
                batchCompletedAt: startedAt.addingTimeInterval(30)
            )
            try database.dbQueue.write { db in try session.insert(db) }
            return id
        }

        func removeFiles() {
            try? FileManager.default.removeItem(at: vaultURL)
        }
    }
#endif
