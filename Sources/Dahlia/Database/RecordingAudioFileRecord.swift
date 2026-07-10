import Foundation
import GRDB

/// バッチ文字起こし用CAFファイルの永続メタデータ。
struct RecordingAudioFileRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "recording_audio_files"

    var id: UUID
    var recordingSessionId: UUID
    var source: RecordingAudioSource
    var storageLocation: RecordingAudioStorageLocation = .managed
    var relativePath: String
    var sampleRate: Double
    var channelCount: Int
    var finalizedAt: Date?
    var totalFrameCount: Int64?
    var createdAt: Date
    var updatedAt: Date
}
