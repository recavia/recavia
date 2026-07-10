import Foundation
import GRDB

/// 録音セッションで使用する文字起こし方式。
enum TranscriptionMode: String, CaseIterable, Codable, DatabaseValueConvertible, Identifiable {
    case realtime
    case batch

    nonisolated static let userDefaultsKey = "transcriptionMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realtime:
            L10n.realtimeTranscription
        case .batch:
            L10n.batchTranscription
        }
    }

    var description: String {
        switch self {
        case .realtime:
            L10n.realtimeTranscriptionDescription
        case .batch:
            L10n.batchTranscriptionDescription
        }
    }
}
