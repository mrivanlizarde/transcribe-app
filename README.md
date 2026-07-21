# Transcribe (working name)

Turns any audio or video file on your Mac into a transcript **with speaker labels** —
who said what, not just what was said.

Everything runs on your machine. No account, no API key, no subscription, no per-minute
cost, and nothing is uploaded. After a one-time model download it works offline.

## Status

Core pipeline built and verified. No app UI yet — there's a command-line prototype.

## Try it

```sh
cd ~/Code/transcribe-app
swift build
./.build/debug/diarize-proto ~/Desktop/interview.m4a 2>/dev/null
```

```
Speaker 1: Hi Daniel, thanks for joining the call today.
Speaker 2: Happy to be here. I've looked at the report and I have a few questions.
```

Options:

| Flag | Effect |
|---|---|
| `--format txt\|srt\|vtt\|markdown\|json` | Output format (default `txt`) |
| `--locale en-US` | Force a language (defaults to your system language) |
| `--no-speakers` | Skip diarization — plain transcript, faster |

`2>/dev/null` hides the diarization engine's debug logging.

## How it works

Apple's `SpeechAnalyzer` transcribes with word-level timestamps. FluidAudio works out
which speaker is talking when. The two are merged on the timeline into speaker-attributed
blocks.

Apple's speech framework cannot identify speakers on its own — that's why the second
engine is here.

## Requirements

macOS 26 or later, Apple Silicon. Both are hard requirements: `SpeechAnalyzer` doesn't
exist on earlier versions, and the speech models aren't available on Intel.

---

For development details see `START_HERE.md`. For roadmap and open questions see `PLAN.md`.
