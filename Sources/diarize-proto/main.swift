import Foundation
import TranscribeCore

// Prototype driver: proves transcription + diarization + merge before any UI exists.
//
//   diarize-proto <file> [--format txt|srt|vtt|markdown|json] [--locale en-US] [--no-speakers]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("diarize-proto: \(message)\n".utf8))
    exit(1)
}

func note(_ s: String) { FileHandle.standardError.write(Data("\(s)\n".utf8)) }

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    fail("usage: diarize-proto <file> [--format txt|srt|vtt|markdown|json] [--locale en-US] [--no-speakers]")
}

var inputPath: String?
var format = TranscriptFormat.txt
var localeID: String?
var speakers = true

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--format":
        guard let v = args.first, let f = TranscriptFormat(rawValue: v) else {
            fail("--format must be one of: \(TranscriptFormat.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        args.removeFirst()
        format = f
    case "--locale":
        guard let v = args.first else { fail("--locale needs a value") }
        args.removeFirst()
        localeID = v
    case "--no-speakers":
        speakers = false
    default:
        guard inputPath == nil else { fail("unexpected argument: \(arg)") }
        inputPath = arg
    }
}

guard let inputPath else { fail("no input file given") }
let input = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath).standardizedFileURL
guard FileManager.default.fileExists(atPath: input.path) else {
    fail("file not found: \(input.path)")
}

let started = Date()
do {
    let source = try await AudioSource.prepare(input)
    defer { source.cleanup() }

    let locale = try await Transcriber.resolveLocale(localeID)
    note("locale: \(locale.identifier)")

    let chunks = try await Transcriber.transcribe(
        source: source, locale: locale,
        onModelDownload: { note("downloading speech model (one time)...") }
    )
    note("transcript chunks: \(chunks.count)")

    var spans: [SpeakerSpan] = []
    if speakers {
        spans = try await SpeakerDiarizer.diarize(
            source: source,
            onModelDownload: { note("preparing diarization models (first run downloads them)...") }
        )
        note("speaker spans: \(spans.count)")
    }

    let transcript = TranscriptBuilder.build(chunks: chunks, spans: spans)
    note("speakers detected: \(transcript.speakerCount)")
    note("elapsed: \(String(format: "%.1fs", Date().timeIntervalSince(started)))")
    note("---")

    print(TranscriptWriter.render(transcript, as: format, includeSpeakers: speakers), terminator: "")
} catch {
    fail("\(error)")
}
