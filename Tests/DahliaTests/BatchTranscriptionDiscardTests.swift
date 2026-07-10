import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchTranscriptionDiscardTests {
        @Test
        func discardingFailedSessionDeletesAudioAndPreservesTimelineAndExistingTranscript() throws {
            let fixture = try BatchAudioTestFixture(
                name: "Discard",
                meetingStatus: .ready,
                endedAt: Date(timeIntervalSince1970: 1_776_384_010),
                duration: 10
            )
            defer { fixture.removeFiles() }
            var failedSession = fixture.session
            failedSession.batchLastError = "Audio is damaged"
            let audioRecord = fixture.makeAudioRecord(finalizedAt: nil, totalFrameCount: nil)
            let existingSegment = TranscriptSegmentRecord(
                id: .v7(),
                meetingId: fixture.meeting.id,
                sessionId: nil,
                startTime: fixture.now,
                endTime: fixture.now.addingTimeInterval(1),
                text: "Existing transcript",
                translatedText: nil,
                isConfirmed: true,
                speakerLabel: "mic"
            )
            try fixture.database.dbQueue.write { db in
                try failedSession.update(db)
                try audioRecord.insert(db)
                try existingSegment.insert(db)
            }
            let partialURL = BatchAudioStorage.partialURL(
                baseURL: fixture.managedRootURL,
                relativePath: fixture.managedRelativePath
            )
            try BatchAudioTestFixture.writeCAF(url: partialURL, frameCount: 320)

            let repository = MeetingRepository(dbQueue: fixture.database.dbQueue)
            let discarded = try repository.discardFailedBatchSession(
                id: failedSession.id,
                managedRootURL: fixture.managedRootURL
            )

            let result = try fixture.database.dbQueue.read { db in
                let session = try RecordingSessionRecord.fetchOne(db, key: failedSession.id)
                let audioFileCount = try RecordingAudioFileRecord.fetchCount(db)
                let segment = try TranscriptSegmentRecord.fetchOne(db, key: existingSegment.id)
                return try (#require(session), audioFileCount, #require(segment))
            }
            #expect(discarded)
            #expect(result.0.batchDiscardedAt != nil)
            #expect(result.0.batchLastError == nil)
            #expect(result.0.duration == 10)
            #expect(BatchTranscriptionState.derive(from: result.0) == nil)
            #expect(result.1 == 0)
            #expect(result.2.text == "Existing transcript")
            #expect(!FileManager.default.fileExists(atPath: partialURL.path))
        }
    }
#endif
