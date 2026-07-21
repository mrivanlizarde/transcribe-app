import SwiftUI
import TranscribeCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            JobSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            Group {
                if model.jobs.isEmpty {
                    DropZone(isTargeted: isTargeted)
                } else if let job = model.selectedJob {
                    JobDetail(job: job)
                } else {
                    ContentUnavailableView("No file selected", systemImage: "waveform")
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted && !model.jobs.isEmpty {
                DropOverlay()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $model.identifySpeakers) {
                    Label("Identify speakers", systemImage: "person.2.wave.2")
                }
                .help("Separate and label each speaker (slower)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseFiles()
                } label: {
                    Label("Add files", systemImage: "plus")
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        if panel.runModal() == .OK {
            model.add(urls: panel.urls)
        }
    }
}

// MARK: - Drop zone

struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [7, 6])
                    )
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
                    )

                VStack(spacing: 12) {
                    Image(systemName: isTargeted ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))

                    Text("Drop audio or video here")
                        .font(.system(size: 15, weight: .medium))

                    Text("Transcribed on your Mac. Nothing is uploaded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420, maxHeight: 260)
            .animation(.easeOut(duration: 0.15), value: isTargeted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            )
            .overlay(
                Label("Drop to transcribe", systemImage: "waveform.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
            )
            .padding(8)
            .allowsHitTesting(false)
    }
}

// MARK: - Sidebar

struct JobSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedJobID) {
            ForEach(model.jobs) { job in
                JobRow(job: job)
                    .tag(job.id)
                    .contextMenu {
                        Button("Remove") { model.remove(job) }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([job.url])
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.jobs.contains(where: { $0.state.isTerminal }) {
                Button("Clear finished") { model.clearFinished() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 9) {
            statusIcon
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 12))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if case .done = job.state, let t = job.transcript {
            let speakers = t.speakerCount
            return speakers > 0
                ? "\(speakers) speaker\(speakers == 1 ? "" : "s") · \(t.blocks.count) blocks"
                : "\(t.blocks.count) blocks"
        }
        return job.state.label
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .queued:
            Image(systemName: "clock").foregroundStyle(.tertiary)
        default:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        }
    }
}

// MARK: - Transcript

struct JobDetail: View {
    let job: Job
    @Environment(AppModel.self) private var model
    @State private var savedTo: URL?

    var body: some View {
        Group {
            switch job.state {
            case .failed(let why):
                ContentUnavailableView {
                    Label("Couldn't transcribe", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(why).font(.system(size: 12))
                }
            case .done:
                transcriptBody
            default:
                VStack(spacing: 10) {
                    ProgressView()
                    Text(job.state.label).foregroundStyle(.secondary)
                    Text(job.displayName).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(job.displayName)
        .toolbar {
            if case .done = job.state {
                ToolbarItem {
                    Button {
                        model.copyToPasteboard(job)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                ToolbarItem {
                    Menu {
                        ForEach(TranscriptFormat.allCases, id: \.self) { format in
                            Button(format.rawValue.uppercased()) {
                                savedTo = model.save(job, format: format)
                            }
                        }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let savedTo {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Saved \(savedTo.lastPathComponent)").font(.system(size: 11))
                    Button("Show") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedTo])
                    }
                    .font(.system(size: 11))
                }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }

    private var transcriptBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array((job.transcript?.blocks ?? []).enumerated()), id: \.offset) {
                    _, block in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            if let label = block.speaker {
                                SpeakerChip(label: label, job: job)
                            }
                            Text(TranscriptWriter.timestamp(
                                block.start, separator: ".", includeMillis: false))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Text(block.text)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
