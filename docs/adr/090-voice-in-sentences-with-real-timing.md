# ADR-090: Voice in sentences, with real word timing

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** the maintainer
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (voice from separate packs) · [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (Register.lua format 2, the audio record) · [ADR-063](063-the-voice-panel.md) (the voice panel) · [ADR-082](082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md) (the engine's own text) · [Voice over](../systems/voice.md) · [Voice runbook](../operations/voice.md#timing)

## Context

Every voiced line shipped as one recording. The voice panel did not know where the voice was in it: it turned its pages by the share of characters read so far. On long lines the page turned seconds early or late. Pausing a line stopped the file, and the client cannot resume a file part way, so resume started the line again from the top.

A player on Discord asked for a saved word's sentence to be playable on the study card and in an Anki export. Both need the audio of one sentence on its own.

So the pipeline needs to know, for every recording, when each part of its Japanese is spoken and where the pauses between sentences are, and the packs need a way to give the addon one file per sentence.

What was measured before deciding (a 1,000-line trial on the maintainer's M1 Pro):

- **Pause detection alone** (quiet stretches in the waveform, matched to the sentence ends in the text) put a cut in the right pause for only 32% of the lines checked. The voices pause inside sentences and run some sentences together.
- **ReazonSpeech** (`reazon-research/japanese-wav2vec2-large-rs35kh`, Apache-2.0) fitted to the known text with torchaudio's `forced_align` gives a start for every character. **Qwen3-ForcedAligner-0.6B** (Apache-2.0) gives a start and an end for every word, in 80 ms steps. Both run at about 30 times real time on the GPU, so the whole archive takes about 7 hours with both.
- The two models' word starts agree within 200 ms on 97.8% of words, and 99.6% of 3,008 cuts were confirmed.

## Decision

1. **Two models time every recorded voice file.** `wfj voice time` (`make voice-time`) runs ReazonSpeech per character and Qwen's aligner per word. Qwen's start is used where a word starts; ReazonSpeech fills in between. The models run in their own interpreters through two helper scripts (`pipeline/wfj/dev/align_reazon.py`, `align_qwen.py`), never imported by the pipeline. The source is the archived WAV when there is one, else the stored MP3 decoded, with its times moved back by the MP3 lead (55 ms).
2. **A cut only where both models agree.** A recording is cut in the middle of the pause before a sentence when that pause is at least 150 ms long, every Qwen word of the earlier sentence ends by the cut (80 ms allowed), and the next sentence's first word starts after it (80 ms allowed). Otherwise those sentences stay in one file. Cuts are seconds on the recording's own clock.
3. **The timing string.** Each record also gets the line's timing: the shipped Japanese, in order, as parts `n:dt` (n characters, hundredths of a second since the previous part started) or `n:-` for what the voice never says (a stage direction it skips, a blank line). A part starts at each Qwen word, each word-card word, each player token and wherever the text turns from said to unsaid. It holds numbers only.
4. **The record keeps the timing; the store keeps whole files.** `data/voice/audio.jsonl` gains `cuts`, `timing` and `timing_of` (the fingerprint it was timed from) per record. The audio store keeps the whole-line MP3s. Timing writes no audio.
5. **Packs snip at pack time.** `wfj voice pack` cuts each stored MP3 at the MP3 frame nearest each cut into `<stem>-<n>.mp3`. The pieces are copied byte for byte (`pipeline/wfj/core/mp3_frames.py`), so played back to back they are the original file. A line with no cut ships its whole file.
6. **Register.lua format 3.** A line is `[key] = { false, jaHash, s = { { file, seconds }, ... }, m = "timing", v = { ... } }`. The first field is `false` because the line's whole file is not in the pack. Voice variants carry their own `s` and `m`.
7. **The addon keeps reading formats 1 and 2.** A whole-file pack plays as before: the addon keeps every line as its list of files, a whole file being a list of one. Where two packs carry the same line, the one in the newer format keeps it, whatever order they load in.
8. **Notices.** At login the addon names every pack in an older format, with its version. The first time a pack's line stays quiet because its audio is older than the Japanese, the addon names that pack. An addon too old for format 3 takes none of a new pack's lines, and the pack itself prints one line at login asking for a newer addon. Every pack's name, version, format and line count goes to the addon log and the bug report.
9. **A gate.** `tests/python/test_voice.py::test_every_voiced_line_is_timed_from_its_own_recording` fails while a voiced line's record has no timing, was timed from another fingerprint, has a timing that does not cover its Japanese, or has cuts out of order or outside the recording. `make voice-generate` and `make voice-run` end with the timing step, so a remade line is timed in the same round.

### The aligner environments

The project rules require an ADR for a new pipeline dependency. The aligners are not one: the pipeline imports neither model's library, and runs the helper scripts with their own interpreters (`ALIGN_REAZON_PY`, default `build/tts-venv/bin/python`; `ALIGN_QWEN_PY`, default `build/aligner-venv/bin/python`), the way it already runs the cloned voices in `build/qwen/venv`. `build/tts-venv` holds torch, torchaudio, transformers, pykakasi and soundfile. `build/aligner-venv` holds `qwen-asr` and soundfile. Both are gitignored local tools in the main checkout, and the models download to the Hugging Face cache on first run. `pipeline/pyproject.toml` leaves the two scripts out of coverage for that reason.

## Rationale

- One model alone misplaces a word now and then, and a cut in the wrong place splits a word between two files. Two models that agree, inside a measured pause, cut only where it is safe; where they do not, a longer file costs nothing but a later page turn.
- Snipping between MP3 frames changes no sample, so the audio is encoded once and the store does not grow. Re-timing never touches audio.
- The cut sits in the middle of a pause of at least 150 ms. A piece's first frame may lean on the frame before it (the MP3 bit reservoir), but that frame is silence either way.
- Keeping the old formats readable lets the addon and the packs be updated in any order without wrong audio.

## Consequences

- The voice panel turns its pages when a sentence starts and marks what is being said. Pause and resume pick up at the sentence.
- Players download every voice pack once more when the first format 3 packs ship. The packs are the same size: the pieces add up to the stored files byte for byte. They hold about four times as many files.
- A player who updates the packs and not the addon hears nothing from them until the addon is updated; the pack says so at login.
- The pipeline needs the two interpreters and the model downloads on the machine that times. A full run takes about 7 hours (overnight); it resumes where it stopped.
- The audio record carries three more fields per file, and every remade line is timed before it ships.
- A line where the models disagree (bad audio, a line read wrong) still ships its timing; the run report lists those lines for a listen.

## Alternatives considered

- **Pause detection alone.** 32% of cuts in the right place in the trial.
- **One model.** No second opinion on where a sentence ends, so a cut could split a word.
- **Cut the WAVs and encode each sentence into the store.** The audio is encoded twice, and the store grows by about 1.4 GB.
- **Ship the whole files beside the sentence files.** About 1.4 GB more for every player, for files only an old addon could use.
