import SwiftUI
import TranscribeCore

/// The speaker chip shown at the top of each transcript block.
/// Clicking it opens a popover to name that speaker, with previously used
/// names one click away.
struct SpeakerChip: View {
    let label: String
    let job: Job
    @Environment(AppModel.self) private var model
    @State private var showingEditor = false

    private var displayName: String { job.name(for: label) }
    private var isNamed: Bool { job.speakerNames[label] != nil }

    var body: some View {
        Button {
            showingEditor = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Self.color(for: label))
                    .frame(width: 7, height: 7)
                Text(displayName)
                    .font(.system(size: 12, weight: .semibold))
                if !isNamed {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Self.color(for: label).opacity(0.12), in: Capsule())
            .foregroundStyle(isNamed ? Self.color(for: label) : .secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingEditor, arrowEdge: .bottom) {
            SpeakerNameEditor(label: label, job: job, isPresented: $showingEditor)
                .environment(model)
        }
    }

    /// Stable per-speaker colour derived from the engine's label.
    static func color(for label: String) -> Color {
        let palette: [Color] = [.blue, .orange, .purple, .teal, .pink, .green, .indigo, .brown]
        let digits = label.compactMap(\.wholeNumberValue)
        let index = digits.isEmpty ? abs(label.hashValue) : digits.reduce(0, +)
        return palette[index % palette.count]
    }
}

struct SpeakerNameEditor: View {
    let label: String
    let job: Job
    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name this speaker")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(label, text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focused($focused)
                .onSubmit(commit)

            if !model.speakers.recents.isEmpty {
                Divider()
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.speakers.recents, id: \.self) { name in
                            RecentNameRow(name: name) {
                                draft = name
                                commit()
                            } onDelete: {
                                model.speakers.forget(name)
                            }
                        }
                    }
                }
                .frame(maxHeight: 132)
            }

            Divider()
            HStack {
                if job.speakerNames[label] != nil {
                    Button("Reset") {
                        model.rename(job: job, label: label, to: "")
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                }
                Spacer()
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 224)
        .onAppear {
            draft = job.speakerNames[label] ?? ""
            focused = true
        }
    }

    private func commit() {
        model.rename(job: job, label: label, to: draft)
        isPresented = false
    }
}

private struct RecentNameRow: View {
    let name: String
    let onPick: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Button(action: onPick) {
                Text(name)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from recents")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            hovering ? Color.secondary.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .onHover { hovering = $0 }
    }
}
