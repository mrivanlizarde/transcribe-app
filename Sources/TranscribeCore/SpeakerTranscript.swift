import Foundation

/// A contiguous run of speech from a single speaker.
public struct TranscriptBlock: Sendable {
    public let speaker: String?
    public let text: String
    public let start: Double
    public let end: Double
    /// Lowest confidence seen in this block, when the engine reported any.
    public let minConfidence: Double?

    public init(
        speaker: String?, text: String, start: Double, end: Double, minConfidence: Double?
    ) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
        self.minConfidence = minConfidence
    }
}

public struct SpeakerTranscript: Sendable {
    public let blocks: [TranscriptBlock]

    public init(blocks: [TranscriptBlock]) {
        self.blocks = blocks
    }

    public var speakerCount: Int {
        Set(blocks.compactMap(\.speaker)).count
    }
    public var plainText: String {
        blocks.map(\.text).joined(separator: " ")
    }
}

public enum TranscriptBuilder {

    /// Joins transcript chunks to speaker spans and groups the result into blocks.
    ///
    /// Each chunk is attributed to whichever span covers its midpoint — the midpoint
    /// is used rather than the start so a word straddling a speaker change lands with
    /// the speaker who said most of it. Chunks falling in a gap between spans (silence,
    /// or audio the diarizer declined to label) inherit the nearest span.
    ///
    /// Pass `spans: []` to build an unlabelled transcript.
    public static func build(
        chunks: [TimedText],
        spans: [SpeakerSpan],
        renameSpeakersInOrderOfAppearance: Bool = true
    ) -> SpeakerTranscript {
        guard !chunks.isEmpty else { return SpeakerTranscript(blocks: []) }

        let labels = spans.isEmpty ? [String?](repeating: nil, count: chunks.count)
            : chunks.map { chunk -> String? in
                if let hit = spans.first(where: { $0.contains(chunk.midpoint) }) {
                    return hit.speakerId
                }
                // Nearest span by distance from the chunk's midpoint.
                return spans.min(by: { a, b in
                    distance(from: chunk.midpoint, to: a) < distance(from: chunk.midpoint, to: b)
                })?.speakerId
            }

        // Stable, human-friendly names in the order speakers first talk.
        var display: [String: String] = [:]
        if renameSpeakersInOrderOfAppearance {
            var next = 1
            for case let label? in labels where display[label] == nil {
                display[label] = "Speaker \(next)"
                next += 1
            }
        }

        var blocks: [TranscriptBlock] = []
        var current: (speaker: String?, pieces: [String], start: Double, end: Double, conf: Double?)?

        for (chunk, rawLabel) in zip(chunks, labels) {
            let speaker = rawLabel.map { display[$0] ?? $0 }

            if var open = current, open.speaker == speaker {
                open.pieces.append(chunk.text)
                open.end = max(open.end, chunk.end)
                open.conf = minOptional(open.conf, chunk.confidence)
                current = open
            } else {
                if let open = current { blocks.append(finish(open)) }
                current = (speaker, [chunk.text], chunk.start, chunk.end, chunk.confidence)
            }
        }
        if let open = current { blocks.append(finish(open)) }

        return SpeakerTranscript(blocks: blocks)
    }

    private static func finish(
        _ open: (speaker: String?, pieces: [String], start: Double, end: Double, conf: Double?)
    ) -> TranscriptBlock {
        let joined = open.pieces.joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptBlock(
            speaker: open.speaker, text: joined,
            start: open.start, end: open.end, minConfidence: open.conf
        )
    }

    private static func distance(from time: Double, to span: SpeakerSpan) -> Double {
        if span.contains(time) { return 0 }
        return time < span.start ? span.start - time : time - span.end
    }

    private static func minOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (let x?, let y?): return Swift.min(x, y)
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (nil, nil): return nil
        }
    }
}

// MARK: - Output formats

public enum TranscriptFormat: String, CaseIterable, Sendable {
    case txt, srt, vtt, markdown, json

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        default: return rawValue
        }
    }
}

public enum TranscriptWriter {

    public static func render(
        _ transcript: SpeakerTranscript,
        as format: TranscriptFormat,
        includeSpeakers: Bool = true
    ) -> String {
        switch format {
        case .txt:      return renderText(transcript, includeSpeakers: includeSpeakers)
        case .markdown: return renderMarkdown(transcript, includeSpeakers: includeSpeakers)
        case .srt:      return renderSRT(transcript, includeSpeakers: includeSpeakers)
        case .vtt:      return renderVTT(transcript, includeSpeakers: includeSpeakers)
        case .json:     return renderJSON(transcript)
        }
    }

    private static func renderText(_ t: SpeakerTranscript, includeSpeakers: Bool) -> String {
        t.blocks.map { block in
            if includeSpeakers, let s = block.speaker {
                return "\(s): \(block.text)"
            }
            return block.text
        }.joined(separator: "\n\n") + "\n"
    }

    private static func renderMarkdown(_ t: SpeakerTranscript, includeSpeakers: Bool) -> String {
        t.blocks.map { block in
            let stamp = timestamp(block.start, separator: ".", includeMillis: false)
            if includeSpeakers, let s = block.speaker {
                return "**\(s)** · `\(stamp)`\n\n\(block.text)"
            }
            return "`\(stamp)`\n\n\(block.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    private static func renderSRT(_ t: SpeakerTranscript, includeSpeakers: Bool) -> String {
        t.blocks.enumerated().map { index, block in
            let body = includeSpeakers && block.speaker != nil
                ? "\(block.speaker!): \(block.text)" : block.text
            return """
                \(index + 1)
                \(timestamp(block.start, separator: ",")) --> \(timestamp(block.end, separator: ","))
                \(body)

                """
        }.joined(separator: "\n")
    }

    private static func renderVTT(_ t: SpeakerTranscript, includeSpeakers: Bool) -> String {
        let cues = t.blocks.map { block -> String in
            let body = includeSpeakers && block.speaker != nil
                ? "<v \(block.speaker!)>\(block.text)" : block.text
            return """
                \(timestamp(block.start, separator: ".")) --> \(timestamp(block.end, separator: "."))
                \(body)

                """
        }.joined(separator: "\n")
        return "WEBVTT\n\n" + cues
    }

    private static func renderJSON(_ t: SpeakerTranscript) -> String {
        let objects = t.blocks.map { block -> [String: Any] in
            var o: [String: Any] = [
                "text": block.text,
                "start": block.start,
                "end": block.end,
            ]
            if let s = block.speaker { o["speaker"] = s }
            if let c = block.minConfidence { o["minConfidence"] = c }
            return o
        }
        let payload: [String: Any] = ["blocks": objects, "speakerCount": t.speakerCount]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string + "\n"
    }

    /// HH:MM:SS<sep>mmm — `,` for SRT, `.` for VTT.
    public static func timestamp(
        _ seconds: Double, separator: String = ",", includeMillis: Bool = true
    ) -> String {
        let total = max(0, seconds)
        let whole = Int(total)
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        let base = String(format: "%02d:%02d:%02d", h, m, s)
        guard includeMillis else { return base }
        let ms = Int((total - Double(whole)) * 1000)
        return base + separator + String(format: "%03d", ms)
    }
}
