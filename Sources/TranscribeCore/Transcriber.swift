import AVFoundation
import Foundation
import Speech

/// One timed chunk of transcribed text, as emitted by SpeechAnalyzer.
/// `confidence` is nil when the engine didn't attach one.
public struct TimedText: Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let confidence: Double?

    public var midpoint: Double { (start + end) / 2 }
}

/// Wraps Apple's on-device SpeechAnalyzer.
public enum Transcriber {

    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    /// Resolves a requested locale to one the transcriber actually supports.
    public static func resolveLocale(_ requested: String?) async throws -> Locale {
        let candidate = requested.map { Locale(identifier: $0) } ?? Locale.current
        guard let match = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) else {
            let all = await SpeechTranscriber.supportedLocales
            throw TranscribeError.unsupportedLocale(
                candidate.identifier, supported: all.map(\.identifier).sorted()
            )
        }
        return match
    }

    /// Transcribes `source`, returning timed chunks in audio order.
    ///
    /// Word-level time ranges are always requested — they're what makes the
    /// speaker merge possible, and they cost nothing when unused.
    public static func transcribe(
        source: AudioSource,
        locale: Locale,
        onModelDownload: (@Sendable () -> Void)? = nil
    ) async throws -> [TimedText] {
        guard SpeechTranscriber.isAvailable else {
            throw TranscribeError.transcriberUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )

        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            onModelDownload?()
            try await request.downloadAndInstall()
        }

        let file = try AVAudioFile(forReading: source.url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Results stream while the analyzer runs, so collect concurrently.
        let collector = Task {
            var chunks: [TimedText] = []
            for try await result in transcriber.results {
                let attributed = result.text
                // Prefer per-run timings; fall back to the result's own range.
                var sawRun = false
                for run in attributed.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let piece = String(attributed[run.range].characters)
                    guard !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { continue }
                    sawRun = true
                    chunks.append(
                        TimedText(
                            text: piece,
                            start: range.start.seconds,
                            end: range.end.seconds,
                            confidence: run.transcriptionConfidence
                        )
                    )
                }
                if !sawRun {
                    let whole = String(attributed.characters)
                    if !whole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chunks.append(
                            TimedText(
                                text: whole,
                                start: result.range.start.seconds,
                                end: result.range.end.seconds,
                                confidence: nil
                            )
                        )
                    }
                }
            }
            return chunks
        }

        _ = try await analyzer.analyzeSequence(from: file)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let chunks = try await collector.value
        guard !chunks.isEmpty else {
            throw TranscribeError.noSpeechDetected(source.url.lastPathComponent)
        }
        return chunks.sorted { $0.start < $1.start }
    }
}
