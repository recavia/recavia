@preconcurrency import AVFoundation
import Foundation
import GRDB

/// 文字起こし完了後、保持対象のCAFをアプリ管理領域からVaultへ安全に移管する。
enum BatchAudioRetentionService {
    private struct Job {
        let session: RecordingSessionRecord
        let meetingId: UUID
        let vaultURL: URL
        let files: [RecordingAudioFileRecord]
    }

    static func retainCompletedAudio(
        sessionId: UUID,
        dbQueue: DatabaseQueue,
        managedRootURL: URL = BatchAudioStorage.managedRootURL
    ) throws {
        let job = try fetchJob(sessionId: sessionId, dbQueue: dbQueue)
        guard job.session.retainAudioAfterBatch,
              job.session.batchCompletedAt != nil else { return }

        let retainedFiles = try job.files.map { file in
            try prepareForRetention(file, job: job, managedRootURL: managedRootURL)
        }

        // 全ファイルのコピーが確定してから、DB上の参照先を一括でVaultへ切り替える。
        try dbQueue.write { db in
            for file in retainedFiles {
                try file.update(db)
            }
        }

        // DBコミット後に管理領域を掃除する。失敗しても起動時の再評価で再試行できる。
        BatchAudioStorage.removeFiles(
            baseURL: managedRootURL,
            relativePaths: job.files.map {
                BatchAudioStorage.managedRelativePath(
                    meetingId: job.meetingId,
                    sessionId: job.session.id,
                    source: $0.source
                )
            }
        )
    }

    private static func prepareForRetention(
        _ originalFile: RecordingAudioFileRecord,
        job: Job,
        managedRootURL: URL
    ) throws -> RecordingAudioFileRecord {
        let vaultRelativePath = BatchAudioStorage.vaultRelativePath(
            meetingId: job.meetingId,
            sessionId: job.session.id,
            source: originalFile.source
        )
        let vaultURL = BatchAudioStorage.finalURL(baseURL: job.vaultURL, relativePath: vaultRelativePath)

        guard originalFile.storageLocation == .managed else {
            guard try isExpectedCAF(at: vaultURL, frameCount: originalFile.totalFrameCount) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return originalFile
        }

        guard let sourceURL = BatchAudioStorage.existingURL(
            for: originalFile,
            managedRootURL: managedRootURL,
            vaultURL: job.vaultURL
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try ensureRetainedCopy(
            sourceURL: sourceURL,
            destinationURL: vaultURL,
            expectedFrameCount: originalFile.totalFrameCount
        )
        var retainedFile = originalFile
        retainedFile.storageLocation = .vault
        retainedFile.relativePath = vaultRelativePath
        retainedFile.updatedAt = .now
        return retainedFile
    }

    private static func ensureRetainedCopy(
        sourceURL: URL,
        destinationURL: URL,
        expectedFrameCount: Int64?
    ) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            guard try isExpectedCAF(at: destinationURL, frameCount: expectedFrameCount) else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stagingURL = destinationURL
            .deletingPathExtension()
            .appendingPathExtension("retaining.caf")
        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try FileManager.default.removeItem(at: stagingURL)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
            guard try isExpectedCAF(at: stagingURL, frameCount: expectedFrameCount) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func isExpectedCAF(at url: URL, frameCount: Int64?) throws -> Bool {
        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0 else { return false }
        return frameCount.map { audioFile.length == $0 } ?? true
    }

    private static func fetchJob(sessionId: UUID, dbQueue: DatabaseQueue) throws -> Job {
        try dbQueue.read { db in
            guard let session = try RecordingSessionRecord.fetchOne(db, key: sessionId),
                  let meeting = try MeetingRecord.fetchOne(db, key: session.meetingId),
                  let vault = try VaultRecord.fetchOne(db, key: meeting.vaultId) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let files = try RecordingAudioFileRecord
                .filter(Column("recordingSessionId") == sessionId)
                .order(Column("source").asc)
                .fetchAll(db)
            guard !files.isEmpty else {
                throw CocoaError(.fileNoSuchFile)
            }
            return Job(
                session: session,
                meetingId: meeting.id,
                vaultURL: vault.url,
                files: files
            )
        }
    }
}
