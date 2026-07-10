import Foundation
import GRDB

/// 単一CAF内の音声区間と録音セッション時刻・ロケールの対応。
struct RecordingAudioRangeRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "recording_audio_ranges"

    var id: UUID
    var audioFileId: UUID
    var startFrame: Int64
    var frameCount: Int64?
    var sessionOffsetSeconds: TimeInterval
    var localeIdentifier: String
    var createdAt: Date
    var updatedAt: Date
}
