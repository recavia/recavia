@preconcurrency import AVFoundation
import Foundation
import os

/// 音声コールバックをブロックせず、CAFへ直列に追記するWriter。
actor BatchAudioFileWriter {
    private struct AudioChunk {
        let data: Data
        let frameCount: AVAudioFrameCount
    }

    // SwiftFormatのmodifier順と、無効なSwiftLint modifier_order設定のfallbackが競合する。
    // swiftlint:disable modifier_order
    private nonisolated let continuation: AsyncStream<AudioChunk>.Continuation
    private nonisolated let frameCounter = OSAllocatedUnfairLock(initialState: Int64(0))
    private nonisolated let callbackError = OSAllocatedUnfairLock<String?>(initialState: nil)
    // swiftlint:enable modifier_order

    private let stream: AsyncStream<AudioChunk>
    private let partialURL: URL
    private let finalURL: URL
    private let format: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var writerTask: Task<Void, Never>?
    private var writeError: Error?

    nonisolated var appendedFrameCount: Int64 {
        frameCounter.withLock { $0 }
    }

    init(partialURL: URL, finalURL: URL, format: AVAudioFormat) {
        let pair = AsyncStream.makeStream(of: AudioChunk.self)
        stream = pair.stream
        continuation = pair.continuation
        self.partialURL = partialURL
        self.finalURL = finalURL
        self.format = format
    }

    func start() throws {
        try FileManager.default.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try FileManager.default.removeItem(at: partialURL)
        }
        audioFile = try AVAudioFile(
            forWriting: partialURL,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )

        writerTask = Task { [weak self, stream] in
            for await chunk in stream {
                await self?.consume(chunk)
            }
        }
    }

    nonisolated func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              buffer.format.channelCount == 1,
              let channelData = buffer.int16ChannelData else {
            callbackError.withLock { $0 = BatchAudioFileWriterError.incompatibleBuffer.localizedDescription }
            return
        }

        let frameCount = buffer.frameLength
        guard frameCount > 0 else { return }
        let byteCount = Int(frameCount) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        frameCounter.withLock { $0 += Int64(frameCount) }
        continuation.yield(AudioChunk(data: data, frameCount: frameCount))
    }

    func finish() async throws -> Int64 {
        await closeWriter()

        if let callbackMessage = callbackError.withLock({ $0 }) {
            throw BatchAudioFileWriterError.writeFailed(callbackMessage)
        }
        if let writeError {
            throw BatchAudioFileWriterError.writeFailed(writeError.localizedDescription)
        }

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        return appendedFrameCount
    }

    func cancelAndDelete() async {
        await closeWriter()
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: finalURL)
    }

    private func closeWriter() async {
        continuation.finish()
        await writerTask?.value
        writerTask = nil
        audioFile = nil
    }

    private func write(_ chunk: AudioChunk) throws {
        guard writeError == nil, let audioFile else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk.frameCount),
              let channelData = buffer.int16ChannelData else {
            throw BatchAudioFileWriterError.incompatibleBuffer
        }

        let destination = UnsafeMutableRawBufferPointer(
            start: channelData[0],
            count: chunk.data.count
        )
        chunk.data.copyBytes(to: destination)
        buffer.frameLength = chunk.frameCount
        try audioFile.write(from: buffer)
    }

    private func consume(_ chunk: AudioChunk) {
        do {
            try write(chunk)
        } catch {
            writeError = error
        }
    }
}
