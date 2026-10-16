# Voice recitation (push-to-talk)

**Hold Shift, say a verse, let go of Shift.** What you said appears in the
verse box and is recited exactly as if you had typed it and pressed Enter
(same verse matching and battle-turn rules). Shift doesn't do this while
you're typing in the verse box, because there it's used for capital letters.

It works **offline** in English and Spanish (it follows the game's language).

## What's already included (nothing to install)

* `addons/godot_whisper/`: the **Godot Whisper** addon v2.0.3 (MIT license,
  https://github.com/appsinacup/godot-whisper). It runs OpenAI's Whisper
  speech recognition (whisper.cpp) on your own PC. Only the 64-bit Windows
  DLL is included. It's a CPU-only build that doesn't need Vulkan (the
  official one does and fails on many PCs); see
  `addons/godot_whisper/BUILD_NOTES.md`.
* `models/ggml-tiny-q5_1.bin` (32 MB): the smallest multilingual model.
  It's fast, but not very accurate, especially in Spanish.

The first time you open the project after pulling, Godot registers the addon.
If it asks you to restart the editor, do it once.

## Optional: better accuracy (one download, recommended for Spanish)

Download **ggml-base-q5_1.bin** (60 MB) and put it in the project's `models/` folder:

https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin

The game picks the best model it finds automatically (small > base > tiny);
see `model_paths` in `speech_recognizer.gd`. `ggml-small-q5_1.bin` (190 MB,
same link with "small") is even better, but slower. Big models aren't
committed to git (see .gitignore).

## If it doesn't work

The game tells you the exact reason in the verse box when you press Shift.
Godot's **Output** panel also shows a report when the game starts. Every
line starts with `[Voice]`, for example:

    [Voice] library loaded: true  SpeechToText class: true
    [Voice] model: res://models/ggml-tiny-q5_1.bin
    [Voice] microphones: ["Default", ...]  using: Default
    [Voice] READY - hold Shift and speak

If it says NOT READY, the line explains why: the addon didn't load, a file is
missing, there's no model, audio input is off, or no microphone was found.
If the recording is empty or silent, it says that too.

Close Godot before pulling new versions of the addon (Windows locks loaded
DLL files).


* Windows Settings > Privacy & security > Microphone: turn on
  "Let desktop apps access your microphone". The default input device is used.
* "Enable Input" must stay on (Project Settings > Audio > Driver).
* A line like `ggml_opencl: platform IDs not available` in the Output panel is
  harmless: it just means there's no OpenCL, so it uses the CPU.

## Exporting the game

In the Export window > Resources tab, add `*.bin` to
"Filters to export non-resource files/folders" so the model goes into the export.

## For programmers

Everything lives in `speech_recognizer.gd` (autoload). To use another
speech-to-text system, replace `_backend_transcribe()` and `is_available()`.
For tests, `SpeechRecognizer.inject_transcript("...")` pretends something was heard.
