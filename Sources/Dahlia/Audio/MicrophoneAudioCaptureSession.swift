/// AVAudioEngine captureをAudioSourcePipelineへ接続するadapter。
actor MicrophoneAudioCaptureSession: AudioCaptureSession {
    private let manager: AudioCaptureManager
    private let pipeline: AudioSourcePipeline
    private let onUnexpectedStop: AudioCaptureUnexpectedStopHandler
    private var isStopping = false

    init(
        pipeline: AudioSourcePipeline,
        onUnexpectedStop: @escaping AudioCaptureUnexpectedStopHandler
    ) {
        self.pipeline = pipeline
        self.onUnexpectedStop = onUnexpectedStop
        let manager = AudioCaptureManager()
        manager.onAudioBuffer = { [pipeline] buffer in
            pipeline.router.route(pipeline.capture(buffer))
        }
        self.manager = manager
        manager.onUnexpectedStop = { [weak self] in
            Task {
                await self?.captureStoppedUnexpectedly()
            }
        }
    }

    func start() throws {
        isStopping = false
        try manager.startCapture(
            targetFormat: pipeline.captureFormat,
            selectedDeviceID: pipeline.captureDeviceID,
            bufferSize: pipeline.captureBufferSize
        )
    }

    func stop() {
        isStopping = true
        manager.stopCapture()
    }

    private func captureStoppedUnexpectedly() {
        guard !isStopping else { return }
        onUnexpectedStop(nil)
    }
}
