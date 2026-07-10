import Foundation
import GRDB

enum RecordingAudioSource: String, Codable, DatabaseValueConvertible {
    case microphone
    case system

    var speakerLabel: String {
        switch self {
        case .microphone: "mic"
        case .system: "system"
        }
    }

    var fileName: String { "\(rawValue).caf" }
}
