# START HERE

On-device transcription with speaker labels for macOS. Audio or video in, a
speaker-attributed transcript out. Everything runs locally — no API key, no network
after the one-time model downloads, no per-minute cost.

Two engines are combined, and that combination is the whole point of the project:

- **Apple `SpeechAnalyzer`** (`Speech.framework`, macOS 26+) does the transcription. Fast,
  free, Neural Engine, no bundled model weights.
- **FluidAudio** (Apache 2.0, Pyannote models on CoreML) does the speaker diarization,
  because **Apple's Speech framework has no diarization at all** — verified against the
  SDK, there is no speaker or diarization symbol in it.

`TranscriptBuilder` joins the two by time. That merge is the core idea.

## Run it and verify

```sh
cd ~/Code/transcribe-app
swift build
./.build/debug/diarize-proto <audio-or-video-file>
```

Useful flags: `--format txt|srt|vtt|markdown|json`, `--locale en-US`, `--no-speakers`.

FluidAudio logs heavily to stderr. Append `2>/dev/null` for clean output.

**Verification means running it on real two-speaker audio and reading the transcript.**
Reading the code does not tell you whether attribution is correct. To build a test file:

```sh
cd /tmp
say -v Samantha -o t1.aiff "First speaker line."
say -v Daniel   -o t2.aiff "Second speaker line."
printf "file '/tmp/t1.aiff'\nfile '/tmp/t2.aiff'\n" > list.txt
ffmpeg -y -f concat -safe 0 -i list.txt -ar 16000 -ac 1 call.wav
```

Last verified 2026-07-21 on a 6-turn, 2-speaker, 29.5s conversation: 6 spans, 2 speakers,
every turn correctly attributed, 2.3s warm.

## Rules of engagement

- **Pin the deployment target to macOS 26.** Any manual `swiftc` invocation needs
  `-target arm64-apple-macos26.0`. The toolchain here defaults to **macOS 28**, a
  version that does not exist publicly — the binary then fails on every other machine
  with "requires a newer version of macOS" while still running fine locally. This
  already bit us once.
- **This repo lives in `~/Code`, not `~/Documents`.** Desktop & Documents iCloud sync is
  ON for this account, and iCloud corrupts Xcode build directories and stalls dev
  servers. `~/Documents/Claude/Projects/transcribe-app` is a symlink. Do not move the
  real directory into Documents.
- **Do not remove FluidAudio to "simplify".** It is the only source of speaker labels.
  Apple's framework cannot do this.
- **The merge attributes by chunk midpoint, not start time** — deliberate, so a word
  straddling a speaker change lands with whoever said most of it. See
  `TranscriptBuilder.build`.

## Known constraints

- **macOS 26+, Apple Silicon.** `SpeechAnalyzer` does not exist below macOS 26, and the
  speech models are unavailable on Intel. This meaningfully limits the audience.
- **Translation is possible but needs SwiftUI.** `Translation.framework` supports 41
  languages on-device, but a headless `TranslationSession(installedSource:target:)`
  throws `.notInstalled` until the language pack is downloaded, and only a SwiftUI
  app can trigger that download. Verified 2026-07-21.
- **Diarization models download on first run** into
  `~/Library/Application Support/FluidAudio/Models`. They are not bundled.

## Layout

```
Sources/TranscribeCore/
  AudioSource.swift        media in → readable audio file (extracts from video)
  Transcriber.swift        SpeechAnalyzer wrapper → timed text chunks
  SpeakerDiarizer.swift    FluidAudio wrapper → speaker spans
  SpeakerTranscript.swift  the merge + all output formats
Sources/diarize-proto/     CLI driver used to prove the pipeline
```

See `PLAN.md` for what is built and what is next, `CHANGELOG.md` for why things changed.
