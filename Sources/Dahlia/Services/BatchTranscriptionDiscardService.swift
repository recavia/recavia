import Foundation
import GRDB

/// 復旧不能なバッチ録音を破棄し、文字起こし待ちの対象から外す。
enum BatchTranscriptionDiscardService {
    static func discardFailedSession(
        id: UUID,
        dbQueue: DatabaseQueue,
        managedRootURL: URL = BatchAudioStorage.managedRootURL
    ) throws -> Bool {
        let audioTargets = try BatchAudioCleanupService.deletionTargets(
            recordingSessionId: id,
            dbQueue: dbQueue,
            managedRootURL: managedRootURL
        )
        let discarded = try dbQueue.write { db in
            guard var session = try RecordingSessionRecord.fetchOne(db, key: id),
                  session.transcriptionMode == .batch,
                  session.batchCompletedAt == nil,
                  session.batchDiscardedAt == nil,
                  session.batchLastError?.nilIfBlank != nil else { return false }

            let now = Date.now
            session.batchDiscardedAt = now
            session.batchLastError = nil
            session.updatedAt = now
            try session.update(db)

            // 失敗時は通常セグメントが存在しないが、旧版等の部分結果も残さない。
            _ = try TranscriptSegmentRecord
                .filter(Column("sessionId") == id)
                .deleteAll(db)
            _ = try RecordingAudioFileRecord
                .filter(Column("recordingSessionId") == id)
                .deleteAll(db)
            return true
        }
        if discarded {
            BatchAudioCleanupService.deleteFiles(audioTargets)
        }
        return discarded
    }
}
