@preconcurrency import AVFoundation
import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchAudioTestFixture {
        let database: AppDatabaseManager
        let testRootURL: URL
        let managedRootURL: URL
        let vaultURL: URL
        let now: Date
        let meeting: MeetingRecord
        let session: RecordingSessionRecord

        init(
            name: String,
            meetingStatus: MeetingStatus = .transcriptNotFound,
            endedAt: Date? = nil,
            duration: TimeInterval? = nil,
            retainAudioAfterBatch: Bool = false,
            batchCompletedAt: Date? = nil
        ) throws {
            database = try AppDatabaseManager(path: ":memory:")
            testRootURL = FileManager.default.temporaryDirectory
                .appending(path: "dahlia-\(name)-test-\(UUID.v7().uuidString)", directoryHint: .isDirectory)
            managedRootURL = testRootURL.appending(path: "Managed", directoryHint: .isDirectory)
            vaultURL = testRootURL.appending(path: "Vault", directoryHint: .isDirectory)
            now = Date(timeIntervalSince1970: 1_776_384_000)

            let vault = VaultRecord(id: .v7(), path: vaultURL.path, name: "Test", createdAt: now, lastOpenedAt: now)
            meeting = MeetingRecord(
                id: .v7(),
                vaultId: vault.id,
                projectId: nil,
                name: name,
                status: meetingStatus,
                duration: duration,
                createdAt: now,
                updatedAt: now
            )
            session = RecordingSessionRecord(
                id: .v7(),
                meetingId: meeting.id,
                startedAt: now,
                endedAt: endedAt,
                duration: duration,
                offsetSeconds: 0,
                createdAt: now,
                updatedAt: now,
                transcriptionMode: .batch,
                retainAudioAfterBatch: retainAudioAfterBatch,
                batchCompletedAt: batchCompletedAt
            )
            try database.dbQueue.write { db in
                try vault.insert(db)
                try meeting.insert(db)
                try session.insert(db)
            }
        }

        var managedRelativePath: String {
            BatchAudioStorage.managedRelativePath(
                meetingId: meeting.id,
                sessionId: session.id,
                source: .microphone
            )
        }

        func makeAudioRecord(finalizedAt: Date?, totalFrameCount: Int64?) -> RecordingAudioFileRecord {
            RecordingAudioFileRecord(
                id: .v7(),
                recordingSessionId: session.id,
                source: .microphone,
                storageLocation: .managed,
                relativePath: managedRelativePath,
                sampleRate: 16000,
                channelCount: 1,
                finalizedAt: finalizedAt,
                totalFrameCount: totalFrameCount,
                createdAt: now,
                updatedAt: now
            )
        }

        func removeFiles() {
            try? FileManager.default.removeItem(at: testRootURL)
        }

        static func writeCAF(url: URL, frameCount: AVAudioFrameCount) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let format = try #require(
                AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)
            )
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: false
            )
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
            buffer.frameLength = frameCount
            try file.write(from: buffer)
        }
    }
#endif
