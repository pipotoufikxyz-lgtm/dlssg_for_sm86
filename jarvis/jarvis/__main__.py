"""Entry point: python -m jarvis [--text] [--wake] [--stt whisper] ..."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from .brain import MODEL, Brain
from .tools import Toolbox
from .voice import Speaker

WAKE_WORD = re.compile(r"\b(hey |ok |okay )?jarvis\b[,.!]?\s*", re.I)
EXIT_WORDS = {"exit", "quit", "goodbye", "goodbye jarvis", "shut down", "power down"}


def main() -> None:
    ap = argparse.ArgumentParser(prog="jarvis", description="J.A.R.V.I.S. voice assistant")
    ap.add_argument("--text", action="store_true", help="type instead of speaking into a microphone")
    ap.add_argument("--mute", action="store_true", help="don't speak replies aloud")
    ap.add_argument("--wake", action="store_true", help="only respond when a phrase starts with 'Jarvis'")
    ap.add_argument("--stt", choices=["google", "whisper"], default="google", help="speech-to-text engine")
    ap.add_argument("--lang", default="en-US", help="speech recognition language, e.g. en-GB, id-ID")
    ap.add_argument("--workspace", default="jarvis_workspace", help="folder where projects are created")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "xhigh", "max"])
    args = ap.parse_args()

    speaker = Speaker(muted=args.mute)
    listener = None
    if not args.text:
        try:
            from .voice import Listener

            listener = Listener(engine=args.stt, language=args.lang)
        except Exception as e:
            print(f"[microphone unavailable ({e}); falling back to text mode]")

    def confirm(prompt: str) -> bool:
        speaker.say("I need your approval for a command, sir. Please check the console.")
        return input(f"{prompt}\nAllow? [y/N] ").strip().lower() in ("y", "yes")

    workspace = Path(args.workspace)
    brain = Brain(Toolbox(workspace, confirm), model=args.model, effort=args.effort)
    speaker.say("J.A.R.V.I.S. online. How may I help you, sir?")
    print(f"(workspace: {workspace.resolve()}  |  say 'goodbye' to exit, 'reset' to clear memory)")

    while True:
        if listener:
            print("🎙  listening...")
            heard = listener.listen()
            if not heard:
                continue
            print(f"You: {heard}")
        else:
            try:
                heard = input("You: ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not heard:
                continue

        if args.wake:
            m = WAKE_WORD.match(heard)
            if not m:
                continue
            heard = heard[m.end():].strip() or "Hello"

        cmd = heard.lower().strip(" .!?")
        if cmd in EXIT_WORDS:
            break
        if cmd in ("reset", "forget everything", "new conversation"):
            brain.reset()
            speaker.say("Memory cleared, sir.")
            continue

        try:
            reply = brain.ask(heard)
        except KeyboardInterrupt:
            reply = "Stopping, sir."
        speaker.say(reply)

    speaker.say("Powering down. Goodbye, sir.")


if __name__ == "__main__":
    main()
