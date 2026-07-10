import Foundation

enum BatchAudioStorage {
    /// クラッシュ復旧対象のCAFは、OSの自動削除対象にならないApplication Supportへ置く。
    static var managedRootURL: URL {
        AppDatabaseManager.databaseURL
            .deletingLastPathComponent()
            .appending(path: "BatchAudio", directoryHint: .isDirectory)
    }

    static func managedRelativePath(meetingId: UUID, sessionId: UUID, source: RecordingAudioSource) -> String {
        "\(meetingId.uuidString)/\(sessionId.uuidString)/\(source.fileName)"
    }

    static func vaultRelativePath(meetingId: UUID, sessionId: UUID, source: RecordingAudioSource) -> String {
        "_dahlia/audio/\(managedRelativePath(meetingId: meetingId, sessionId: sessionId, source: source))"
    }

    static func finalURL(baseURL: URL, relativePath: String) -> URL {
        baseURL.appending(path: relativePath)
    }

    static func partialURL(baseURL: URL, relativePath: String) -> URL {
        finalURL(baseURL: baseURL, relativePath: relativePath)
            .deletingPathExtension()
            .appendingPathExtension("partial.caf")
    }

    static func finalURL(
        for file: RecordingAudioFileRecord,
        managedRootURL: URL = managedRootURL,
        vaultURL: URL
    ) -> URL {
        finalURL(
            baseURL: baseURL(for: file.storageLocation, managedRootURL: managedRootURL, vaultURL: vaultURL),
            relativePath: file.relativePath
        )
    }

    static func partialURL(
        for file: RecordingAudioFileRecord,
        managedRootURL: URL = managedRootURL,
        vaultURL: URL
    ) -> URL {
        partialURL(
            baseURL: baseURL(for: file.storageLocation, managedRootURL: managedRootURL, vaultURL: vaultURL),
            relativePath: file.relativePath
        )
    }

    static func existingURL(
        for file: RecordingAudioFileRecord,
        managedRootURL: URL = managedRootURL,
        vaultURL: URL
    ) -> URL? {
        let finalURL = finalURL(for: file, managedRootURL: managedRootURL, vaultURL: vaultURL)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            return finalURL
        }
        let partialURL = partialURL(for: file, managedRootURL: managedRootURL, vaultURL: vaultURL)
        return FileManager.default.fileExists(atPath: partialURL.path) ? partialURL : nil
    }

    static func removeFiles(baseURL: URL, relativePaths: [String]) {
        for relativePath in relativePaths {
            guard let finalURL = safeURL(baseURL: baseURL, relativePath: relativePath) else { continue }
            try? FileManager.default.removeItem(at: finalURL)
            try? FileManager.default.removeItem(
                at: finalURL.deletingPathExtension().appendingPathExtension("partial.caf")
            )
            removeEmptyParentDirectories(of: finalURL, stoppingAt: baseURL)
        }
    }

    static func removeFiles(
        _ files: [RecordingAudioFileRecord],
        managedRootURL: URL = managedRootURL,
        vaultURL: URL
    ) {
        for location in RecordingAudioStorageLocation.allCases {
            let relativePaths = files
                .filter { $0.storageLocation == location }
                .map(\.relativePath)
            removeFiles(
                baseURL: baseURL(for: location, managedRootURL: managedRootURL, vaultURL: vaultURL),
                relativePaths: relativePaths
            )
        }
    }

    static func baseURL(
        for location: RecordingAudioStorageLocation,
        managedRootURL: URL = managedRootURL,
        vaultURL: URL
    ) -> URL {
        switch location {
        case .managed:
            managedRootURL
        case .vault:
            vaultURL
        }
    }

    private static func safeURL(baseURL: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let standardizedBaseURL = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = standardizedBaseURL
            .appending(path: relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let directoryPrefix = standardizedBaseURL.path.hasSuffix("/")
            ? standardizedBaseURL.path
            : standardizedBaseURL.path + "/"
        guard candidateURL.path.hasPrefix(directoryPrefix) else { return nil }
        return candidateURL
    }

    private static func removeEmptyParentDirectories(of fileURL: URL, stoppingAt baseURL: URL) {
        let standardizedBaseURL = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        let directoryPrefix = standardizedBaseURL.path.hasSuffix("/")
            ? standardizedBaseURL.path
            : standardizedBaseURL.path + "/"
        var directoryURL = fileURL.deletingLastPathComponent()

        while directoryURL.path.hasPrefix(directoryPrefix) {
            do {
                guard try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).isEmpty else { return }
                try FileManager.default.removeItem(at: directoryURL)
                directoryURL = directoryURL.deletingLastPathComponent()
            } catch {
                return
            }
        }
    }
}
