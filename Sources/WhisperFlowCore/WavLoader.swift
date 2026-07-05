import Foundation

public enum WavLoaderError: Error, LocalizedError {
    case notFound(String)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "WAV file not found: \(path)"
        case .invalidFormat(let msg): return "Invalid WAV format: \(msg)"
        }
    }
}

public struct WavLoader {
    public static func loadSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return try decodeWave(data: data)
    }

    static func decodeWave(data: Data) throws -> [Float] {
        guard data.count > 44 else {
            throw WavLoaderError.invalidFormat("File too small for WAV header")
        }

        let riff = String(decoding: data[0..<4], as: UTF8.self)
        guard riff == "RIFF" else {
            throw WavLoaderError.invalidFormat("Not a RIFF file")
        }

        let wave = String(decoding: data[8..<12], as: UTF8.self)
        guard wave == "WAVE" else {
            throw WavLoaderError.invalidFormat("Not a WAVE file")
        }

        guard data[12..<16] == "fmt ".data(using: .ascii) else {
            throw WavLoaderError.invalidFormat("Missing fmt chunk")
        }

        let audioFormat = data[20..<22].withUnsafeBytes { $0.load(as: UInt16.self) }
        guard audioFormat == 1 else {
            throw WavLoaderError.invalidFormat("Only PCM format supported, got \(audioFormat)")
        }

        let numChannels = data[22..<24].withUnsafeBytes { $0.load(as: UInt16.self) }
        let sampleRate = data[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }
        let bitsPerSample = data[34..<36].withUnsafeBytes { $0.load(as: UInt16.self) }

        guard sampleRate == 16000 else {
            throw WavLoaderError.invalidFormat("Expected 16 kHz sample rate, got \(sampleRate) Hz")
        }

        guard numChannels == 1 else {
            throw WavLoaderError.invalidFormat("Expected mono, got \(numChannels) channels")
        }

        var offset = 36
        while offset + 8 <= data.count {
            let chunkID = data[offset..<offset+4]
            let chunkSize = data[offset+4..<offset+8].withUnsafeBytes { $0.load(as: UInt32.self) }
            if chunkID == "data".data(using: .ascii) {
                let sampleData = data[offset+8..<offset+8+Int(chunkSize)]
                return decodePCM(sampleData, bitsPerSample: bitsPerSample)
            }
            offset += 8 + Int(chunkSize)
        }

        throw WavLoaderError.invalidFormat("No data chunk found")
    }

    static func decodePCM(_ data: Data, bitsPerSample: UInt16) -> [Float] {
        switch bitsPerSample {
        case 16:
            return data.withUnsafeBytes { buffer in
                let samples = buffer.bindMemory(to: Int16.self)
                return samples.map { Float($0) / Float(Int16.max) }
            }
        case 32:
            return data.withUnsafeBytes { buffer in
                let samples = buffer.bindMemory(to: Int32.self)
                return samples.map { Float($0) / Float(Int32.max) }
            }
        default:
            return []
        }
    }
}
