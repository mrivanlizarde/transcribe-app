import AVFoundation
import Foundation

/// Resolves an arbitrary media file into a plain audio file that both
/// SpeechAnalyzer and FluidAudio can read.
///
/// Video containers (and any audio format AVAudioFile can't open directly)
/// are exported to a temporary .m4a. Call `cleanup()` when finished.
public struct AudioSource: Sendable {
    public let url: URL
    private let temporary: URL?

    public init(url: URL, temporary: URL?) {
        self.url = url
        self.temporary = temporary
    }

    public func cleanup() {
        if let temporary {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    /// Prepares `input` for analysis, extracting an audio track if needed.
    public static func prepare(_ input: URL) async throws -> AudioSource {
        if (try? AVAudioFile(forReading: input)) != nil {
            return AudioSource(url: input, temporary: nil)
        }

        let asset = AVURLAsset(url: input)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw TranscribeError.noAudioTrack(input.lastPathComponent)
        }

        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscribeError.exportFailed(input.lastPathComponent)
        }

        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
        try await session.export(to: temp, as: .m4a)

        guard (try? AVAudioFile(forReading: temp)) != nil else {
            throw TranscribeError.exportFailed(input.lastPathComponent)
        }
        return AudioSource(url: temp, temporary: temp)
    }
}

public enum TranscribeError: Error, CustomStringConvertible {
    case noAudioTrack(String)
    case exportFailed(String)
    case unsupportedLocale(String, supported: [String])
    case transcriberUnavailable
    case noSpeechDetected(String)

    public var description: String {
        switch self {
        case .noAudioTrack(let f):
            return "no audio track found in \(f)"
        case .exportFailed(let f):
            return "could not extract audio from \(f)"
        case .unsupportedLocale(let l, let supported):
            return "locale \(l) is not supported.\nsupported: \(supported.joined(separator: ", "))"
        case .transcriberUnavailable:
            return "SpeechTranscriber is not available on this machine"
        case .noSpeechDetected(let f):
            return "no speech was detected in \(f)"
        }
    }
}
