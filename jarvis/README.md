# J.A.R.V.I.S.

A voice assistant that listens to you, talks back, and can **build tools for you in
Python, Rust and C++** — it writes the code, compiles it, runs it, reads the errors
and fixes them until it works. The brain is Claude (Anthropic API).

```
You: Jarvis, make me a Rust tool that counts words in a file.
  ✎ writing wordcount/Cargo.toml
  ✎ writing wordcount/src/main.rs
  ⚙ building wordcount (rust)
J.A.R.V.I.S.: Done, sir. The word counter is in wordcount/ — run it with cargo run -- yourfile.txt.
```

## Setup

```bash
cd jarvis
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...                   # Windows: set ANTHROPIC_API_KEY=...
```

Audio prerequisites:

| OS | Install |
|---|---|
| Windows | nothing extra (`pip install PyAudio` ships wheels) |
| macOS | `brew install portaudio` before `pip install` |
| Linux | `sudo apt install portaudio19-dev espeak-ng` |

To build things it needs the compilers on your `PATH`: `python3`, Rust (`rustup` → `cargo`),
and a C++ compiler (`g++`/`clang++`, optionally `cmake`).

## Run

```bash
python -m jarvis              # talk to it through the microphone
python -m jarvis --wake       # only reacts to phrases starting with "Jarvis ..."
python -m jarvis --text       # type instead of speaking
python -m jarvis --stt whisper   # offline speech recognition (pip install openai-whisper)
python -m jarvis --lang en-GB --effort high --workspace ~/jarvis_projects
```

Say **"reset"** to clear its memory and **"goodbye"** to exit.

## Things to ask

- "Make a Python script that renames all photos in a folder by date taken."
- "Build a C++ command-line calculator and test it."
- "Write a Rust program that finds duplicate files, then run it on the workspace."
- "What's in my workspace?" / "Add a --json flag to the word counter."

## How it works

| File | Role |
|---|---|
| `jarvis/voice.py` | Microphone → text (SpeechRecognition: Google or offline Whisper), text → speech (pyttsx3, offline) |
| `jarvis/brain.py` | Conversation with Claude and the tool-use loop |
| `jarvis/tools.py` | `write_file`, `read_file`, `list_files`, `build_and_run` (Python / Rust / C++), `run_command` |
| `jarvis/__main__.py` | CLI, wake word, exit/reset commands |

**Safety:** all files are confined to the workspace folder (`jarvis_workspace/` by default).
`build_and_run` only runs the fixed build/run commands for the project; any other shell
command goes through `run_command`, which asks you to approve it in the console every time.
Programs run with a 120 s timeout.

## Tests

```bash
pip install pytest && python -m pytest tests
```
