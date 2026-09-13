import AppKit
import Foundation
import Observation
import TranscribeCore
import UniformTypeIdentifiers

/// One file moving through the pipeline.
@Observable
final class Job: Identifiable {
    enum State: Equatable {
        case queued
        case preparing
        case transcribing
        case identifyingSpeakers
        case done
        case failed(String)

        var label: String {
            switch self {
            case .queued: return "Queued"
            case .preparing: return "Preparing audio"
            case .transcribing: return "Transcribing"
            case .identifyingSpeakers: return "Identifying speakers"
            case .done: return "Done"
            case .failed(let why): return why
            }
        }

        var isTerminal: Bool {
            switch self {
            case .done, .failed: return true
            default: return false
            }
        }
    }

    let id = UUID()
    let url: URL
    var state: State = .queued
    var transcript: SpeakerTranscript?
    /// Maps the engine's label ("Speaker 1") to a name the user typed.
    var speakerNames: [String: String] = [:]
    /// Set when the file arrived from Finder (Quick Action / Open With): write this format
    /// beside the original the moment the job finishes, and say so with a notification.
    var autoSave: TranscriptFormat?

    init(url: URL) { self.url = url }

    var displayName: String { url.lastPathComponent }

    /// Distinct engine labels in order of first appearance.
    var speakerLabels: [String] {
        guard let transcript else { return [] }
        var seen: [String] = []
        for block in transcript.blocks {
            if let s = block.speaker, !seen.contains(s) { seen.append(s) }
        }
        return seen
    }

    func name(for label: String) -> String {
        speakerNames[label] ?? label
    }

    /// The transcript with user-supplied names substituted in.
    func renamedTranscript() -> SpeakerTranscript? {
        guard let transcript else { return nil }
        guard !speakerNames.isEmpty else { return transcript }
        let blocks = transcript.blocks.map { block in
            TranscriptBlock(
                speaker: block.speaker.map { name(for: $0) },
                text: block.text,
                start: block.start,
                end: block.end,
                minConfidence: block.minConfidence
            )
        }
        return SpeakerTranscript(blocks: blocks)
    }
}

@Observable
@MainActor
final class AppModel {
    var jobs: [Job] = []
    var selectedJobID: Job.ID?
    var identifySpeakers = true
    var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyActivationPolicy()
        }
    }

    let speakers = SpeakerStore()

    private var isDraining = false

    init() {
        // Default to showing the Dock icon on first launch.
        if UserDefaults.standard.object(forKey: "showDockIcon") == nil {
            showDockIcon = true
        } else {
            showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        }
    }

    var selectedJob: Job? {
        jobs.first { $0.id == selectedJobID }
    }

    /// Hiding the Dock icon turns the app into a menu-bar-only accessory.
    /// `.regular` is restored with an activate() so the window comes back to front.
    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func isSupportedMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    func add(urls: [URL], autoSave: TranscriptFormat? = nil) {
        let media = urls.filter(Self.isSupportedMedia)
        guard !media.isEmpty else { return }
        let new = media.map { url -> Job in
            let job = Job(url: url)
            job.autoSave = autoSave
            return job
        }
        jobs.append(contentsOf: new)
        if selectedJobID == nil { selectedJobID = new.first?.id }
        drain()
    }

    func remove(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id { selectedJobID = jobs.first?.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
        if selectedJob == nil { selectedJobID = jobs.first?.id }
    }

    /// Runs queued jobs one at a time. Both engines are heavy; running them
    /// concurrently across files makes every file slower rather than the batch faster.
    private func drain() {
        guard !isDraining else { return }
        isDraining = true
        Task { [weak self] in
            while let job = self?.jobs.first(where: { $0.state == .queued }) {
                await self?.run(job)
            }
            self?.isDraining = false
        }
    }

    private func run(_ job: Job) async {
        let wantsSpeakers = identifySpeakers
        job.state = .preparing
        do {
            let source = try await AudioSource.prepare(job.url)
            defer { source.cleanup() }

            let locale = try await Transcriber.resolveLocale(nil)

            job.state = .transcribing
            let chunks = try await Transcriber.transcribe(source: source, locale: locale)

            var spans: [SpeakerSpan] = []
            if wantsSpeakers {
                job.state = .identifyingSpeakers
                spans = try await SpeakerDiarizer.diarize(source: source)
            }

            job.transcript = TranscriptBuilder.build(chunks: chunks, spans: spans)
            job.state = .done
            if let format = job.autoSave {
                if let dest = save(job, format: format) {
                    notify("Transcript saved", dest.lastPathComponent)
                } else {
                    notify("Transcribe failed", "Could not write beside \(job.displayName)")
                }
            }
        } catch {
            job.state = .failed("\(error)")
            if job.autoSave != nil {
                notify("Transcribe failed", "\(job.displayName): \(error)")
            }
        }
    }

    /// A user notification via osascript. Hark is unsandboxed, so this is reliable and needs
    /// no notification-permission dance; the Finder Quick Action relies on it for feedback.
    private func notify(_ title: String, _ body: String) {
        let escape = { (s: String) in s.replacingOccurrences(of: "\"", with: "\\\"") }
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    // MARK: - Naming

    func rename(job: Job, label: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            job.speakerNames.removeValue(forKey: label)
        } else {
            job.speakerNames[label] = trimmed
            speakers.remember(trimmed)
        }
    }

    // MARK: - Export

    func copyToPasteboard(_ job: Job, format: TranscriptFormat = .txt) {
        guard let transcript = job.renamedTranscript() else { return }
        let text = TranscriptWriter.render(transcript, as: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes beside the original file. Sandboxing will change this later —
    /// see PLAN.md; for now the app is unsandboxed and this is the friction-free path.
    @discardableResult
    func save(_ job: Job, format: TranscriptFormat) -> URL? {
        guard let transcript = job.renamedTranscript() else { return nil }
        let text = TranscriptWriter.render(transcript, as: format)
        let dest = job.url.deletingPathExtension().appendingPathExtension(format.fileExtension)
        do {
            try text.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        } catch {
            return nil
        }
    }
}
