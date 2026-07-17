import Foundation
import RecaviaRuntimeSupport
@testable import Recavia

#if canImport(Testing)
    import Testing

    struct RecaviaApplicationSupportTests {
        private let baseURL = URL(filePath: "/Users/test/Library/Application Support", directoryHint: .isDirectory)

        @Test
        func productionUsesTheExistingApplicationSupportDirectory() {
            let directoryURL = RecaviaApplicationSupport.directoryURL(
                applicationSupportDirectory: baseURL,
                environment: [:]
            )

            #expect(directoryURL == baseURL.appending(path: "Recavia", directoryHint: .isDirectory))
        }

        @Test
        func developmentUsesOneSharedSeparateApplicationSupportDirectory() {
            let environment = [
                RecaviaApplicationSupport.profileEnvironmentKey: RecaviaRuntimeProfile.development.rawValue,
            ]
            let firstURL = RecaviaApplicationSupport.directoryURL(
                applicationSupportDirectory: baseURL,
                environment: environment
            )
            let secondURL = RecaviaApplicationSupport.directoryURL(
                applicationSupportDirectory: baseURL,
                environment: environment
            )

            #expect(firstURL == baseURL.appending(path: "Recavia-Development", directoryHint: .isDirectory))
            #expect(secondURL == firstURL)
        }

        @Test
        func unrecognizedProfileDoesNotRedirectTheProductionApp() {
            let directoryURL = RecaviaApplicationSupport.directoryURL(
                applicationSupportDirectory: baseURL,
                environment: [RecaviaApplicationSupport.profileEnvironmentKey: "preview"]
            )

            #expect(directoryURL == baseURL.appending(path: "Recavia", directoryHint: .isDirectory))
        }

        @Test
        func existingApplicationSupportDirectoryAndDatabaseAreMovedToRecavia() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appending(path: "recavia-application-support-\(UUID.v7())", directoryHint: .isDirectory)
            let legacyURL = rootURL.appending(path: "Dahlia", directoryHint: .isDirectory)
            let databaseURL = legacyURL.appending(path: "dahlia.sqlite")
            defer { try? FileManager.default.removeItem(at: rootURL) }

            try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
            try Data("existing database".utf8).write(to: databaseURL)
            try Data("existing wal".utf8).write(to: URL(filePath: databaseURL.path + "-wal"))
            try Data("existing shm".utf8).write(to: URL(filePath: databaseURL.path + "-shm"))

            let migratedDatabaseURL = RecaviaApplicationSupport.databaseURL(
                applicationSupportDirectory: rootURL,
                environment: [:]
            )

            #expect(migratedDatabaseURL == rootURL.appending(path: "Recavia/app.sqlite"))
            #expect(FileManager.default.fileExists(atPath: migratedDatabaseURL.path))
            #expect(FileManager.default.fileExists(atPath: migratedDatabaseURL.path + "-wal"))
            #expect(FileManager.default.fileExists(atPath: migratedDatabaseURL.path + "-shm"))
            #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        }

        @Test
        func databaseUsesGenericFilename() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appending(path: "recavia-database-name-\(UUID.v7())", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: rootURL) }
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let databaseURL = RecaviaApplicationSupport.databaseURL(
                applicationSupportDirectory: rootURL,
                environment: [:]
            )

            #expect(databaseURL == rootURL.appending(path: "Recavia/app.sqlite"))
        }

        @Test
        func databaseIsRenamedWhenRecaviaDirectoryAlreadyExists() throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appending(path: "recavia-existing-directory-\(UUID.v7())", directoryHint: .isDirectory)
            let directoryURL = rootURL.appending(path: "Recavia", directoryHint: .isDirectory)
            let legacyDatabaseURL = directoryURL.appending(path: "dahlia.sqlite")
            defer { try? FileManager.default.removeItem(at: rootURL) }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data("existing database".utf8).write(to: legacyDatabaseURL)

            let databaseURL = RecaviaApplicationSupport.databaseURL(
                applicationSupportDirectory: rootURL,
                environment: [:]
            )

            #expect(databaseURL == directoryURL.appending(path: "app.sqlite"))
            #expect(FileManager.default.fileExists(atPath: databaseURL.path))
            #expect(!FileManager.default.fileExists(atPath: legacyDatabaseURL.path))
        }
    }
#endif
