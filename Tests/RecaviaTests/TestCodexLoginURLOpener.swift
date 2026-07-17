import Foundation
@testable import Recavia

@MainActor
final class TestCodexLoginURLOpener: CodexLoginURLOpening {
    private let result: Bool
    private(set) var openedURLs: [URL] = []

    init(result: Bool = true) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}
