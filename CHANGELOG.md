# Changelog

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
