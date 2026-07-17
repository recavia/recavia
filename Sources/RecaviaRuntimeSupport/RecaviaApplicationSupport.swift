import Foundation

public enum RecaviaRuntimeProfile: String, Sendable {
    case production
    case development
}

public enum RecaviaApplicationSupport {
    public static let profileEnvironmentKey = "RECAVIA_RUNTIME_PROFILE"

    public static func profile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RecaviaRuntimeProfile {
        #if DEBUG
            guard environment[profileEnvironmentKey] == RecaviaRuntimeProfile.development.rawValue else {
                return .production
            }
            return .development
        #else
            return .production
        #endif
    }

    public static func directoryURL(
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let profile = profile(environment: environment)
        let preferredURL = applicationSupportDirectory.appending(
            path: directoryName(for: profile),
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let legacyURL = applicationSupportDirectory.appending(
            path: legacyDirectoryName(for: profile),
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return preferredURL
        }

        do {
            try fileManager.moveItem(at: legacyURL, to: preferredURL)
            return preferredURL
        } catch {
            if fileManager.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
            // Continue using the existing directory if the branding migration cannot be completed.
            // Losing access to the database or recordings is worse than retaining the legacy path.
            return legacyURL
        }
    }

    public static var currentDirectoryURL: URL {
        directoryURL()
    }

    public static func databaseURL(
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let directoryURL = directoryURL(
            applicationSupportDirectory: applicationSupportDirectory,
            environment: environment,
            fileManager: fileManager
        )
        let preferredURL = directoryURL.appending(path: "app.sqlite")
        let legacyURL = directoryURL.appending(path: "dahlia.sqlite")
        guard !fileManager.fileExists(atPath: preferredURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return preferredURL
        }

        do {
            try migrateDatabaseFiles(
                from: legacyURL,
                to: preferredURL,
                fileManager: fileManager
            )
            return preferredURL
        } catch {
            return fileManager.fileExists(atPath: preferredURL.path) ? preferredURL : legacyURL
        }
    }

    public static var currentDatabaseURL: URL {
        databaseURL()
    }

    private static func directoryName(for profile: RecaviaRuntimeProfile) -> String {
        switch profile {
        case .production:
            "Recavia"
        case .development:
            "Recavia-Development"
        }
    }

    private static func legacyDirectoryName(for profile: RecaviaRuntimeProfile) -> String {
        switch profile {
        case .production:
            "Dahlia"
        case .development:
            "Dahlia-Development"
        }
    }

    private static func migrateDatabaseFiles(
        from legacyURL: URL,
        to preferredURL: URL,
        fileManager: FileManager
    ) throws {
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let sourceURL = URL(filePath: legacyURL.path + suffix)
            let destinationURL = URL(filePath: preferredURL.path + suffix)
            guard !fileManager.fileExists(atPath: sourceURL.path)
                || !fileManager.fileExists(atPath: destinationURL.path) else {
                throw DatabaseMigrationError.destinationExists(destinationURL)
            }
        }

        var movedSuffixes: [String] = []

        do {
            for suffix in suffixes {
                let sourceURL = URL(filePath: legacyURL.path + suffix)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
                let destinationURL = URL(filePath: preferredURL.path + suffix)
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                movedSuffixes.append(suffix)
            }
        } catch {
            for suffix in movedSuffixes.reversed() {
                let sourceURL = URL(filePath: preferredURL.path + suffix)
                let destinationURL = URL(filePath: legacyURL.path + suffix)
                try? fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            throw error
        }
    }

    private enum DatabaseMigrationError: Error {
        case destinationExists(URL)
    }
}
