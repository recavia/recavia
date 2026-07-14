import Foundation

enum CodexAppServerInput {
    case text(String)
    case imageDataURI(String)

    var isImage: Bool {
        if case .imageDataURI = self { true } else { false }
    }
}
