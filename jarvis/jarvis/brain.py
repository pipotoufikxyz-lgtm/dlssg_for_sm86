"""Claude-powered brain: keeps the conversation and runs the tool loop."""

from __future__ import annotations

from typing import Callable

import anthropic

from .tools import TOOL_SCHEMAS, Toolbox

SYSTEM_PROMPT = """You are J.A.R.V.I.S., a witty, loyal, highly capable AI assistant in the style of \
Tony Stark's butler. Address the user as "sir" (or "ma'am" if they ask).

Your replies are spoken aloud by a text-to-speech engine, so:
- Keep spoken answers short and conversational: one to three sentences unless asked for detail.
- Never read out code, file contents, markdown, bullet lists or URLs. Summarise instead \
("I've written a Rust CLI in wordcount/ and it passes a quick test, sir.").

You can build software. When asked to make a tool, script or program in Python, Rust or C++:
1. Pick a short project folder name and write all files with write_file \
(Rust: Cargo.toml + src/main.rs; C++: main.cpp or CMakeLists.txt; Python: main.py).
2. Test it with build_and_run, read the errors, and fix until it works.
3. Report back briefly what you built, where it is, and how to run it.
Only use the standard library unless the user asks otherwise; if a dependency is needed, \
use run_command (the user approves each command). All paths are relative to the workspace."""

MODEL = "claude-opus-5"
MAX_TOOL_ROUNDS = 25


class Brain:
    def __init__(self, toolbox: Toolbox, on_status: Callable[[str], None] = print,
                 model: str = MODEL, effort: str = "medium"):
        self.client = anthropic.Anthropic()
        self.toolbox = toolbox
        self.on_status = on_status
        self.model = model
        self.effort = effort
        self.messages: list = []

    def reset(self) -> None:
        self.messages = []

    def ask(self, user_text: str) -> str:
        """Send a user turn, run tools until Claude is done, return the spoken reply."""
        self.messages.append({"role": "user", "content": user_text})
        for _ in range(MAX_TOOL_ROUNDS):
            try:
                response = self._call()
            except anthropic.RateLimitError:
                self.messages.pop()
                return "I'm being rate limited at the moment, sir. Give me a few seconds."
            except anthropic.APIConnectionError:
                self.messages.pop()
                return "I can't reach my servers, sir. Please check the network connection."
            except anthropic.APIStatusError as e:
                self.messages.pop()
                return f"My servers returned an error, sir: {e.status_code}."

            if response.stop_reason == "refusal":
                self.messages.pop()  # drop the refused turn so the history stays valid
                return "I'm afraid I can't help with that one, sir."

            self.messages.append({"role": "assistant", "content": response.content})

            if response.stop_reason == "pause_turn":
                continue
            if response.stop_reason != "tool_use":
                text = " ".join(b.text for b in response.content if b.type == "text").strip()
                if response.stop_reason == "max_tokens":
                    text += " (I ran out of room mid-thought, sir.)"
                return text or "Done, sir."

            results = []
            for block in response.content:
                if block.type != "tool_use":
                    continue
                self.on_status(_describe(block.name, block.input))
                output, is_error = self.toolbox.dispatch(block.name, block.input)
                results.append({"type": "tool_result", "tool_use_id": block.id,
                                "content": output, "is_error": is_error})
            self.messages.append({"role": "user", "content": results})

        return "That took more steps than I'm allowed, sir. Shall I continue?"

    def _call(self):
        return self.client.beta.messages.create(
            model=self.model,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            tools=TOOL_SCHEMAS,
            messages=self.messages,
            thinking={"type": "adaptive"},
            output_config={"effort": self.effort},
            cache_control={"type": "ephemeral"},
            # If the model declines, let the API retry on a fallback model automatically.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )


def _describe(name: str, tool_input: dict) -> str:
    if name == "write_file":
        return f"  ✎ writing {tool_input.get('path')}"
    if name == "build_and_run":
        return f"  ⚙ building {tool_input.get('project_dir')} ({tool_input.get('language')})"
    if name == "run_command":
        return f"  $ {tool_input.get('command')}"
    return f"  • {name} {tool_input.get('path', '')}".rstrip()
