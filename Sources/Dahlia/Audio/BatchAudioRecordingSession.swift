@preconcurrency import AVFoundation
import Foundation
import GRDB

/// ひとつのバッチ録音セッションで、音源ごとの単一CAFとrangeを管理する。
@MainActor
final class BatchAudioRecordingSession {
    let targetFormat: AVAudioFormat

    private let dbQueue: DatabaseQueue
    private let managedRootURL: URL
    private let meetingId: UUID
    private let recordingSessionId: UUID
    private let recordingStartTime: Date
    private var writers: [RecordingAudioSource: BatchAudioFileWriter] = [:]
    private var fileRecords: [RecordingAudioSource: RecordingAudioFileRecord] = [:]
    private var activeRanges: [RecordingAudioSource: RecordingAudioRangeRecord] = [:]

    init(
        dbQueue: DatabaseQueue,
        managedRootURL: URL = BatchAudioStorage.managedRootURL,
        meetingId: UUID,
        recordingSessionId: UUID,
        recordingStartTime: Date,
        sampleRate: Double
    ) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidHardwareFormat
        }
        self.dbQueue = dbQueue
        self.managedRootURL = managedRootURL
        self.meetingId = meetingId
        self.recordingSessionId = recordingSessionId
        self.recordingStartTime = recordingStartTime
        self.targetFormat = format
    }

    func beginRange(source: RecordingAudioSource, locale: Locale, at date: Date = .now) async throws -> BatchAudioFileWriter {
        try await endRange(source: source)
        let writer = try await writer(for: source)
        let audioFile = try fileRecord(for: source)
        let now = Date.now
        let range = RecordingAudioRangeRecord(
            id: .v7(),
            audioFileId: audioFile.id,
            startFrame: writer.appendedFrameCount,
            frameCount: nil,
            sessionOffsetSeconds: max(0, date.timeIntervalSince(recordingStartTime)),
            localeIdentifier: locale.identifier,
            createdAt: now,
            updatedAt: now
        )
        try await dbQueue.write { db in
            try range.insert(db)
        }
        activeRanges[source] = range
        return writer
    }

    func endActiveRanges() async throws {
        for source in Array(activeRanges.keys) {
            try await endRange(source: source)
        }
    }

    func finish() async throws {
        try await endActiveRanges()
        for (source, writer) in writers {
            let totalFrames = try await writer.finish()
            guard var fileRecord = fileRecords[source] else { continue }
            let now = Date.now
            fileRecord.finalizedAt = now
            fileRecord.totalFrameCount = totalFrames
            fileRecord.updatedAt = now
            let updatedRecord = fileRecord
            try await dbQueue.write { db in
                try updatedRecord.update(db)
            }
            fileRecords[source] = fileRecord
        }
    }

    func cancelAndDelete() async {
        for writer in writers.values {
            await writer.cancelAndDelete()
        }
        try? await dbQueue.write { db in
            _ = try RecordingAudioFileRecord
                .filter(Column("recordingSessionId") == recordingSessionId)
                .deleteAll(db)
        }
    }

    private func writer(for source: RecordingAudioSource) async throws -> BatchAudioFileWriter {
        if let writer = writers[source] {
            return writer
        }

        let relativePath = BatchAudioStorage.managedRelativePath(
            meetingId: meetingId,
            sessionId: recordingSessionId,
            source: source
        )
        let now = Date.now
        let record = RecordingAudioFileRecord(
            id: .v7(),
            recordingSessionId: recordingSessionId,
            source: source,
            storageLocation: .managed,
            relativePath: relativePath,
            sampleRate: targetFormat.sampleRate,
            channelCount: Int(targetFormat.channelCount),
            finalizedAt: nil,
            totalFrameCount: nil,
            createdAt: now,
            updatedAt: now
        )
        try await dbQueue.write { db in
            try record.insert(db)
        }

        let writer = BatchAudioFileWriter(
            partialURL: BatchAudioStorage.partialURL(baseURL: managedRootURL, relativePath: relativePath),
            finalURL: BatchAudioStorage.finalURL(baseURL: managedRootURL, relativePath: relativePath),
            format: targetFormat
        )
        do {
            try await writer.start()
        } catch {
            try? await dbQueue.write { db in
                _ = try RecordingAudioFileRecord.deleteOne(db, key: record.id)
            }
            throw error
        }
        writers[source] = writer
        fileRecords[source] = record
        return writer
    }

    private func fileRecord(for source: RecordingAudioSource) throws -> RecordingAudioFileRecord {
        guard let record = fileRecords[source] else {
            throw BatchAudioFileWriterError.incompatibleBuffer
        }
        return record
    }

    private func endRange(source: RecordingAudioSource) async throws {
        guard var range = activeRanges.removeValue(forKey: source),
              let writer = writers[source] else { return }
        range.frameCount = max(0, writer.appendedFrameCount - range.startFrame)
        range.updatedAt = .now
        let updatedRange = range
        try await dbQueue.write { db in
            try updatedRange.update(db)
        }
    }
}
