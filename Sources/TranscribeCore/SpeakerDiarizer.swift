import FluidAudio
import Foundation

/// A stretch of audio attributed to one speaker.
public struct SpeakerSpan: Sendable {
    public let speakerId: String
    public let start: Double
    public let end: Double

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

/// Wraps FluidAudio's offline diarization pipeline (Pyannote models on CoreML).
///
/// Models are downloaded once into FluidAudio's cache directory on first run;
/// they are not bundled with the app.
public enum SpeakerDiarizer {

    public static func diarize(
        source: AudioSource,
        onModelDownload: (@Sendable () -> Void)? = nil,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [SpeakerSpan] {
        let manager = OfflineDiarizerManager(config: .default)
        onModelDownload?()
        try await manager.prepareModels()

        let result = try await manager.process(source.url, progressCallback: progress)

        return result.segments
            .map {
                SpeakerSpan(
                    speakerId: $0.speakerId,
                    start: Double($0.startTimeSeconds),
                    end: Double($0.endTimeSeconds)
                )
            }
            .sorted { $0.start < $1.start }
    }
}
