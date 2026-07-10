@preconcurrency import AVFoundation
import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchAudioRecordingSessionTests {
        @Test
        func localeChangesCreateRangesInOneCAF() async throws {
            let fixture = try BatchAudioTestFixture(name: "Batch")
            defer { fixture.removeFiles() }

            let recorder = try BatchAudioRecordingSession(
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL,
                meetingId: fixture.meeting.id,
                recordingSessionId: fixture.session.id,
                recordingStartTime: fixture.now,
                sampleRate: 16000
            )
            let firstWriter = try await recorder.beginRange(
                source: .microphone,
                locale: Locale(identifier: "ja_JP"),
                at: fixture.now
            )
            try firstWriter.appendBuffer(makeBuffer(format: recorder.targetFormat, frameCount: 160))
            try await recorder.endActiveRanges()

            let secondWriter = try await recorder.beginRange(
                source: .microphone,
                locale: Locale(identifier: "en_US"),
                at: fixture.now.addingTimeInterval(1)
            )
            #expect(firstWriter === secondWriter)
            try secondWriter.appendBuffer(makeBuffer(format: recorder.targetFormat, frameCount: 160))
            try await recorder.finish()

            let result = try await fixture.database.dbQueue.read { db in
                let files = try RecordingAudioFileRecord
                    .filter(Column("recordingSessionId") == fixture.session.id)
                    .fetchAll(db)
                let ranges = try RecordingAudioRangeRecord.order(Column("startFrame").asc).fetchAll(db)
                return (files, ranges)
            }
            let file = try #require(result.0.first)
            #expect(result.0.count == 1)
            #expect(file.storageLocation == .managed)
            #expect(file.totalFrameCount == 320)
            #expect(result.1.count == 2)
            #expect(result.1.map(\.localeIdentifier) == ["ja_JP", "en_US"])
            #expect(result.1.map(\.startFrame) == [0, 160])
            #expect(result.1.map(\.frameCount) == [160, 160])

            let finalURL = BatchAudioStorage.finalURL(baseURL: fixture.managedRootURL, relativePath: file.relativePath)
            let partialURL = BatchAudioStorage.partialURL(baseURL: fixture.managedRootURL, relativePath: file.relativePath)
            #expect(FileManager.default.fileExists(atPath: finalURL.path))
            #expect(!FileManager.default.fileExists(atPath: partialURL.path))
            let vaultAudioURL = BatchAudioStorage.finalURL(
                baseURL: fixture.vaultURL,
                relativePath: BatchAudioStorage.vaultRelativePath(
                    meetingId: fixture.meeting.id,
                    sessionId: fixture.session.id,
                    source: .microphone
                )
            )
            #expect(!FileManager.default.fileExists(atPath: vaultAudioURL.path))
            let audioFile = try AVAudioFile(forReading: finalURL)
            #expect(audioFile.length == 320)
        }

        private func makeBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
            buffer.frameLength = frameCount
            let channel = try #require(buffer.int16ChannelData?[0])
            for index in 0 ..< Int(frameCount) {
                channel[index] = Int16(index % 100)
            }
            return buffer
        }
    }
#endif
