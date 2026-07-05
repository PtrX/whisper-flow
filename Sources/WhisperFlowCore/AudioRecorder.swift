@preconcurrency import AVFoundation

public protocol AudioRecorder: Sendable {
    func startRecording()
    func stopRecording() -> [Float]
}

public final class FakeAudioRecorder: AudioRecorder, @unchecked Sendable {
    private var buffer: [Float] = []

    public init() {}

    public func startRecording() {
        buffer = []
    }

    public func feed(samples: [Float]) {
        buffer.append(contentsOf: samples)
    }

    public func stopRecording() -> [Float] {
        let result = buffer
        buffer = []
        return result
    }
}

public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    public init() {}

    public func startRecording() {
        buffer = []
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }
            let outputFrames = AVAudioFrameCount(
                targetFormat.sampleRate * Double(pcmBuffer.frameLength) / inputFormat.sampleRate
            )
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputFrames) else { return }
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            if error == nil, let channelData = outBuffer.floatChannelData {
                let count = Int(outBuffer.frameLength)
                self.buffer.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: count))
            }
        }

        try? engine.start()
    }

    public func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let result = buffer
        buffer = []
        return result
    }
}
