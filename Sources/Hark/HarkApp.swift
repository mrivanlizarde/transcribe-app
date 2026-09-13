import AppKit
import SwiftUI
import TranscribeCore

@main
struct HarkApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Hark", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear {
                    delegate.model = model
                    model.applyActivationPolicy()
                }
        }
        .defaultSize(width: 940, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Hark", systemImage: "waveform") {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Kept so the app stays alive with the Dock icon hidden, so closing the window
/// doesn't terminate a menu-bar-only app, and to receive files from Finder.
///
/// Files arrive here when Hark is opened with a document: "Open With", a drag onto the
/// icon, or the Finder Quick Action, which runs `open -g -a Hark <file>`. That path is the
/// whole fix for the Quick Action: LaunchServices launches Hark unsandboxed, so the media
/// decode that failed inside Automator's inherited sandbox succeeds here. Files opened this
/// way auto-save a .txt beside the original and post a notification.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// On a cold launch the open-files call can arrive before the window has handed us the
    /// model; hold the URLs until it does rather than drop them.
    private var pendingOpenURLs: [URL] = []
    var model: AppModel? {
        didSet { flushPendingOpens() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingOpenURLs.append(contentsOf: urls)
        flushPendingOpens()
    }

    private func flushPendingOpens() {
        guard let model, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        model.add(urls: urls, autoSave: .txt)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    @MainActor func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        Button("Open Hark") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut("o")

        Button("Transcribe Files…") {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK {
                model.add(urls: panel.urls)
                openWindow(id: "main")
            }
        }

        Divider()

        if model.jobs.isEmpty {
            Text("No files yet")
        } else {
            ForEach(model.jobs.suffix(6)) { job in
                Button {
                    model.selectedJobID = job.id
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Text("\(job.displayName) — \(job.state.label)")
                }
            }
        }

        Divider()

        Toggle("Identify speakers", isOn: $model.identifySpeakers)
        Toggle("Show Dock icon", isOn: $model.showDockIcon)

        Divider()

        Button("Quit Hark") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Show Dock icon", isOn: $model.showDockIcon)
                Text("With this off, Hark lives only in the menu bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Identify speakers by default", isOn: $model.identifySpeakers)
                Text("Separates each voice and labels it. Adds a few seconds per file.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Recent speaker names") {
                if model.speakers.recents.isEmpty {
                    Text("No saved names yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.speakers.recents.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Clear recent speakers", role: .destructive) {
                        confirmingClear = true
                    }
                    .confirmationDialog(
                        "Clear all saved speaker names?",
                        isPresented: $confirmingClear,
                        titleVisibility: .visible
                    ) {
                        Button("Clear", role: .destructive) { model.speakers.clear() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Names already applied to transcripts are kept.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
