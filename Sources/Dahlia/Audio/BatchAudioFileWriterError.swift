import Foundation

enum BatchAudioFileWriterError: LocalizedError {
    case incompatibleBuffer
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompatibleBuffer:
            L10n.batchAudioBufferInvalid
        case let .writeFailed(message):
            L10n.batchAudioWriteFailed(message)
        }
    }
}
