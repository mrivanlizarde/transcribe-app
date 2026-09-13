# Changelog

## 2026-09-13 — Hark takes over the Finder Quick Action

The CLI-based Quick Actions ("Transcribe to Text File / Clipboard / SRT") failed on video from
a Finder right-click and worked from a Terminal, through four rounds of fixes. The instrumented
run on 04 Aug settled it: inside Automator's Run Shell Script the child process inherits
Automator's sandbox, and AVFoundation's decode fails there with a bare `_GenericObjCError` —
AVAssetExportSession and AVAssetReader alike — while the raw file reads fine. Nothing that
decodes media should run as a child of that action.

**The fix is a different launch path, not a different API.** The single new Quick Action,
"Transcribe with Hark", runs `open -g -a ~/Applications/Hark.app "$@"`. LaunchServices launches
Hark as a normal user app, outside the sandbox; Hark receives the file as a document, transcribes
it with speaker labels, writes `<file>.txt` beside it, and posts a notification. `open` returns
at once, so the action never blocks and never shows "Run Shell Script encountered an error".

**Added**
- `AppDelegate.application(_:open:)` — files from "Open With", drag-to-icon, or the Quick
  Action. URLs that arrive before the window has handed over the model are held, not dropped.
- `Job.autoSave` and `AppModel.add(urls:autoSave:)` — Finder-opened jobs write their format
  beside the original on completion and notify via osascript.
- `CFBundleDocumentTypes` for public.audio / public.movie / public.audiovisual-content,
  Alternate rank so Hark never becomes the default app.
- `make-app.sh release --install` → `~/Applications/Hark.app`.
- `install-quick-action.sh` — installs the one action, removes the three old ones, absolute
  app path baked in (a runtime `$HOME` broke once under a redirected home).

**Verified**, in the two contexts that can be driven from here: `open -g -a Hark` on a `.mov`
on the Desktop wrote `.txt` beside it in ~12 s; the installed workflow run through
`automator -i` wrote it in ~6 s. Both speaker-labeled. The literal Finder right-click is the one
context not driven from here; Ivan does that once.

**Retired**: the three CLI actions and the `transcribe` binary as a Finder path. The CLI still
works from a Terminal, and its repo notes why it was superseded.

## 2026-07-21 (later) — Hark: the app

Named the product **Hark** and built the real macOS app around the proven core.

**Why a SwiftPM target plus a bundle script, not an .xcodeproj.** No project generator
(XcodeGen/Tuist) is installed, and a hand-written `.pbxproj` is long, fragile, and
impossible to verify without opening Xcode. `make-app.sh` assembles a genuine `.app` that
can be launched and tested immediately. Xcode opens `Package.swift` directly for
development. A real project becomes necessary when the Action Extension lands, since
extensions can't be expressed in SwiftPM.

**Added**
- SwiftUI app: drop zone, sidebar queue with per-file status, transcript view.
- Speaker naming — click any speaker chip to name them. Names apply across the whole
  transcript and flow into every export.
- Recent speaker names, persisted in UserDefaults, matched case-insensitively so "johan"
  doesn't shadow "Johan". Removable individually on hover, or cleared entirely from
  Settings behind a confirmation.
- `MenuBarExtra` — open, add files, jump to a recent job, toggle speakers, quit.
- Dock icon toggle via `NSApp.setActivationPolicy`, switched at runtime rather than
  through `LSUIElement`, so it takes effect without relaunching.
- App icon drawn in code (`Sources/make-icon`) — two rows of bars, amber over blue, for
  the two voices Hark separates.
- Jobs run one at a time. Both engines are heavy; running them concurrently across files
  makes every file slower rather than the batch faster.

**Icon fix caught by looking at it.** The first draft used eight bars per row, which
turned to an unreadable smudge at 32pt. Reduced to five, wider and taller. Rendering the
icon and viewing it at target size is the only way this surfaces.

**Verified**: builds clean, bundle assembles with the icon, app launches and stays
resident, and it accepted a real recording and rendered its transcript view. Screen
capture was declined, so the visual layout has not been inspected — the interface is
built to spec but unreviewed.

**Made public** `TranscriptBlock.init` and `SpeakerTranscript.init` so the app can rebuild
a transcript with user-supplied speaker names.

## 2026-07-21 — Core pipeline proven

First working build. Transcription with speaker labels, fully on-device.

**Why this shape.** The project started as a Finder Quick Action wrapping Apple's
`SpeechAnalyzer`. Speaker identification was the feature that made it worth turning into
a product, and the obvious route — the OpenAI Whisper API — turns out not to do
diarization at all. Whisper is a transcription model; diarization is a separate model
family. Cloud would have cost the privacy positioning and delivered nothing.

FluidAudio (Apache 2.0, Pyannote on CoreML) does it locally instead, so the app keeps
Apple's fast free transcription *and* gains speaker labels with nothing leaving the
machine.

**Added**
- `AudioSource` — resolves any media file to readable audio, extracting from video.
- `Transcriber` — `SpeechAnalyzer` wrapper. Requests `.audioTimeRange` and
  `.transcriptionConfidence` unconditionally; the time ranges are what make the speaker
  merge possible and cost nothing when unused.
- `SpeakerDiarizer` — FluidAudio `OfflineDiarizerManager` wrapper.
- `TranscriptBuilder` — merges the two by time, groups into speaker blocks, renames
  speakers in order of first appearance for stable output.
- Output formats: txt, srt, vtt, markdown, json.
- `diarize-proto` CLI, to prove the pipeline before any UI exists.

**Verified**, not just compiled: a 6-turn, 2-speaker, 29.5s conversation produced 6
speaker spans, 2 speakers, and correct attribution on every turn. 2.3s warm (~13×
real-time for transcription *and* diarization). All five output formats checked.
`minConfidence` populates (0.604, 0.866), so confidence highlighting is viable.

**Decisions**
- Attribute each text chunk by its **midpoint**, not start time, so a word straddling a
  speaker change lands with whoever said most of it.
- Repo lives in `~/Code` with a symlink into `Documents/Claude/Projects`. Desktop &
  Documents iCloud sync is on for this account and iCloud corrupts Xcode builds.
- Deployment target pinned to macOS 26. The toolchain defaults to macOS 28, which
  produces a binary that runs locally but fails on every other machine.
