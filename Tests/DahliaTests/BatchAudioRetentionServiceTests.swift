import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchAudioRetentionServiceTests {
        @Test
        func retainedAudioMovesToVaultAndIsDeletedWithMeeting() throws {
            let now = Date(timeIntervalSince1970: 1_776_384_000)
            let fixture = try BatchAudioTestFixture(
                name: "Retention",
                meetingStatus: .ready,
                endedAt: now.addingTimeInterval(0.02),
                duration: 0.02,
                retainAudioAfterBatch: true,
                batchCompletedAt: now
            )
            defer { fixture.removeFiles() }
            let audioRecord = fixture.makeAudioRecord(finalizedAt: now, totalFrameCount: 320)
            try fixture.database.dbQueue.write { db in
                try audioRecord.insert(db)
            }

            let managedURL = BatchAudioStorage.finalURL(
                baseURL: fixture.managedRootURL,
                relativePath: fixture.managedRelativePath
            )
            try BatchAudioTestFixture.writeCAF(url: managedURL, frameCount: 320)

            try BatchAudioRetentionService.retainCompletedAudio(
                sessionId: fixture.session.id,
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL
            )

            let retainedRecord = try #require(
                fixture.database.dbQueue.read { db in
                    try RecordingAudioFileRecord.fetchOne(db, key: audioRecord.id)
                }
            )
            let retainedURL = BatchAudioStorage.finalURL(
                for: retainedRecord,
                managedRootURL: fixture.managedRootURL,
                vaultURL: fixture.vaultURL
            )
            #expect(retainedRecord.storageLocation == .vault)
            #expect(retainedRecord.relativePath == BatchAudioStorage.vaultRelativePath(
                meetingId: fixture.meeting.id,
                sessionId: fixture.session.id,
                source: .microphone
            ))
            #expect(!FileManager.default.fileExists(atPath: managedURL.path))
            #expect(!FileManager.default.fileExists(atPath: managedURL.deletingLastPathComponent().path))
            #expect(FileManager.default.fileExists(atPath: fixture.managedRootURL.path))
            #expect(FileManager.default.fileExists(atPath: retainedURL.path))

            let repository = MeetingRepository(dbQueue: fixture.database.dbQueue)
            try repository.deleteMeeting(id: fixture.meeting.id)
            #expect(!FileManager.default.fileExists(atPath: retainedURL.path))
            #expect(!FileManager.default.fileExists(atPath: retainedURL.deletingLastPathComponent().path))
            #expect(FileManager.default.fileExists(atPath: fixture.vaultURL.path))
        }

        @Test
        func retainedAudioAcceptsRecoveredPartialCAF() throws {
            let now = Date(timeIntervalSince1970: 1_776_384_000)
            let fixture = try BatchAudioTestFixture(
                name: "PartialRetention",
                meetingStatus: .ready,
                endedAt: now.addingTimeInterval(0.02),
                duration: 0.02,
                retainAudioAfterBatch: true,
                batchCompletedAt: now
            )
            defer { fixture.removeFiles() }
            let audioRecord = fixture.makeAudioRecord(finalizedAt: nil, totalFrameCount: 320)
            try fixture.database.dbQueue.write { db in
                try audioRecord.insert(db)
            }

            let partialURL = BatchAudioStorage.partialURL(
                baseURL: fixture.managedRootURL,
                relativePath: fixture.managedRelativePath
            )
            try BatchAudioTestFixture.writeCAF(url: partialURL, frameCount: 320)

            try BatchAudioRetentionService.retainCompletedAudio(
                sessionId: fixture.session.id,
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL
            )

            let retainedRecord = try #require(
                fixture.database.dbQueue.read { db in
                    try RecordingAudioFileRecord.fetchOne(db, key: audioRecord.id)
                }
            )
            let retainedURL = BatchAudioStorage.finalURL(
                for: retainedRecord,
                managedRootURL: fixture.managedRootURL,
                vaultURL: fixture.vaultURL
            )
            #expect(retainedRecord.storageLocation == .vault)
            #expect(FileManager.default.fileExists(atPath: retainedURL.path))
            #expect(!FileManager.default.fileExists(atPath: partialURL.path))
            #expect(!FileManager.default.fileExists(atPath: partialURL.deletingLastPathComponent().path))
        }

        @Test
        func retainedAudioSurvivesVaultUnregistration() throws {
            let now = Date(timeIntervalSince1970: 1_776_384_000)
            let fixture = try BatchAudioTestFixture(
                name: "VaultUnregistration",
                meetingStatus: .ready,
                endedAt: now.addingTimeInterval(0.02),
                duration: 0.02,
                retainAudioAfterBatch: true,
                batchCompletedAt: now
            )
            defer { fixture.removeFiles() }
            let audioRecord = fixture.makeAudioRecord(finalizedAt: now, totalFrameCount: 320)
            try fixture.database.dbQueue.write { db in
                try audioRecord.insert(db)
            }
            let managedURL = BatchAudioStorage.finalURL(
                baseURL: fixture.managedRootURL,
                relativePath: fixture.managedRelativePath
            )
            try BatchAudioTestFixture.writeCAF(url: managedURL, frameCount: 320)
            try BatchAudioRetentionService.retainCompletedAudio(
                sessionId: fixture.session.id,
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL
            )
            let retainedRecord = try #require(
                fixture.database.dbQueue.read { db in
                    try RecordingAudioFileRecord.fetchOne(db, key: audioRecord.id)
                }
            )
            let retainedURL = BatchAudioStorage.finalURL(
                for: retainedRecord,
                managedRootURL: fixture.managedRootURL,
                vaultURL: fixture.vaultURL
            )

            let repository = MeetingRepository(dbQueue: fixture.database.dbQueue)
            try repository.deleteVault(id: fixture.meeting.vaultId)

            #expect(FileManager.default.fileExists(atPath: retainedURL.path))
        }
    }
#endif
