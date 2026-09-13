# PLAN

## What this is

A macOS app that transcribes audio and video **with speaker labels**, entirely on-device.
The wedge against MacWhisper and the rest of the local-transcription field:

1. **No multi-gigabyte model download.** Apple's speech models are already on the machine;
   the diarization models are Pyannote-sized, not Whisper-sized.
2. **Zero friction.** Right-click in Finder, or drop on a menu-bar target. You never open
   an app.
3. **Speaker labels without the cloud.** Otter-grade output with nothing uploaded.

## Built and verified

- [x] Audio/video input, with audio extracted from video containers
- [x] Transcription via `SpeechAnalyzer`, word-level time ranges and confidence
- [x] Speaker diarization via FluidAudio (CoreML / ANE)
- [x] Time-based merge into speaker-attributed blocks
- [x] Output: txt, srt, vtt, markdown, json
- [x] CLI prototype (`diarize-proto`)

- [x] **App shell** — drop zone, queue sidebar, transcript view, menu bar item,
      runtime Dock-icon toggle, app icon
- [x] **Speaker naming** with persisted, clearable recents

## Next

- [ ] **Look at the UI.** Screen capture was declined during the build, so the layout has
      never actually been reviewed. Do this before anything else — spacing, the empty
      state, and the speaker popover are all unverified guesses.
- [x] **Finder Quick Action**, done 2026-09-13 as `open -g -a Hark` from an Automator
      workflow (`install-quick-action.sh`), not as an Action Extension. The CLI version
      could not decode video inside Automator's inherited sandbox; handing the file to the
      app escapes it, and no `.xcodeproj` is needed. Verified via `open` and `automator`;
      the literal right-click is confirmed by Ivan.
- [ ] **Audio player** synced to the transcript — click a block to hear it. The single
      biggest gap versus Otter/Sana, and the timestamps are already there.
- [ ] **Sandbox entitlements.** Required for App Store. The extension gets read access to
      the selected file; writing a sibling `.txt` is *not* automatically granted. Needs a
      save panel or a security-scoped bookmark. This changes the "file just appears next
      to the original" behaviour and is the main UX decision to make.
- [ ] **Confidence highlighting.** `minConfidence` is already carried on every block.
      Surfacing low-confidence words for proofreading is the differentiator nobody else
      ships.
- [ ] **Translation.** 41 languages on-device; needs the SwiftUI app to trigger language
      pack downloads.
- [ ] **App Intents / Shortcuts support.** Also strengthens the Guideline 4.2 argument
      that this is a real app, not an API wrapper.
- [ ] Quiet FluidAudio's stderr logging in release builds.

## Open questions

- **Name.** "Transcribe" is a placeholder. Needs an App Store name-availability and
  trademark check before any branding work — this bit us recently on another project.
- **Price.** Market comparables: MacWhisper €59 lifetime; Whisper Transcription
  $6.99/mo · $29.99/yr · $99.99 lifetime. $0.99 was considered and rejected — the
  margin cannot work against a macOS 26-only audience. Working assumption:
  $14.99–$19.99 one-time. Not yet decided.
- **Free tier?** MacWhisper has one, so competing without one is hard. Undecided.
- **Manual speaker renaming.** Diarization gives "Speaker 1/2"; letting users rename to
  real names is obvious value but adds an editing surface.

## Explicitly not doing

- **Cloud APIs.** Whisper API has no diarization at all; `gpt-4o-transcribe-diarize`
  does, but per-minute billing plus an API key destroys the positioning that makes this
  product worth building.
