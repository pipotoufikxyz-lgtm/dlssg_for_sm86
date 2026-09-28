"""Tools J.A.R.V.I.S. can use to build things.

Every path is confined to a workspace directory, so the model can only
create, read and run files inside it.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Callable

MAX_OUTPUT = 8000  # chars of stdout/stderr returned to the model
LANGUAGES = ("python", "rust", "cpp")


class ToolError(Exception):
    pass


class Toolbox:
    def __init__(self, workspace: Path, confirm: Callable[[str], bool], timeout: int = 120):
        self.workspace = workspace.resolve()
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.confirm = confirm
        self.timeout = timeout

    # ---- path safety -------------------------------------------------
    def _resolve(self, rel: str) -> Path:
        p = (self.workspace / rel).resolve()
        if p != self.workspace and self.workspace not in p.parents:
            raise ToolError(f"path escapes workspace: {rel}")
        return p

    # ---- tool implementations ---------------------------------------
    def write_file(self, path: str, content: str) -> str:
        p = self._resolve(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return f"wrote {len(content)} chars to {p.relative_to(self.workspace)}"

    def read_file(self, path: str) -> str:
        p = self._resolve(path)
        if not p.is_file():
            raise ToolError(f"no such file: {path}")
        return p.read_text(encoding="utf-8", errors="replace")[:MAX_OUTPUT * 4]

    def list_files(self, path: str = ".") -> str:
        root = self._resolve(path)
        if not root.exists():
            raise ToolError(f"no such directory: {path}")
        skip = {"target", "build", "__pycache__", ".git", ".venv"}
        out = []
        for f in sorted(root.rglob("*")):
            rel = f.relative_to(self.workspace)
            if skip & set(rel.parts):
                continue
            out.append(f"{rel}{'/' if f.is_dir() else ''}")
            if len(out) >= 300:
                out.append("... (truncated)")
                break
        return "\n".join(out) or "(empty)"

    def build_and_run(self, project_dir: str, language: str, args: list[str] | None = None,
                      stdin: str = "") -> str:
        """Build (if needed) and run a project. Returns build + run output."""
        if language not in LANGUAGES:
            raise ToolError(f"language must be one of {LANGUAGES}")
        d = self._resolve(project_dir)
        if not d.is_dir():
            raise ToolError(f"no such directory: {project_dir}")
        args = [str(a) for a in (args or [])]

        steps: list[tuple[str, list[str]]] = []
        if language == "python":
            entry = next((e for e in ("main.py", "app.py", "__main__.py") if (d / e).exists()), None)
            if entry is None:
                raise ToolError("python project needs main.py")
            steps.append(("run", [_which("python3", "python"), entry, *args]))
        elif language == "rust":
            if (d / "Cargo.toml").exists():
                steps.append(("run", [_which("cargo"), "run", "--quiet", "--", *args]))
            else:
                steps.append(("build", [_which("rustc"), "-O", "main.rs", "-o", "main_bin"]))
                steps.append(("run", [str(d / "main_bin"), *args]))
        else:  # cpp
            if (d / "CMakeLists.txt").exists():
                cmake = _which("cmake")
                steps.append(("configure", [cmake, "-S", ".", "-B", "build", "-DCMAKE_BUILD_TYPE=Release"]))
                steps.append(("build", [cmake, "--build", "build", "-j"]))
                steps.append(("run", []))  # executable path is known only after the build
            else:
                sources = sorted(str(p.relative_to(d)) for p in d.glob("*.cpp"))
                if not sources:
                    raise ToolError("c++ project needs .cpp files or CMakeLists.txt")
                cxx = _which("g++", "clang++")
                steps.append(("build", [cxx, "-std=c++20", "-O2", "-Wall", *sources, "-o", "main_bin"]))
                steps.append(("run", [str(d / "main_bin"), *args]))

        report = []
        for name, cmd in steps:
            if not cmd:
                cmd = [_find_cmake_exe(d), *args]
            code, out = self._exec(cmd, d, stdin if name == "run" else "")
            report.append(f"$ {' '.join(cmd)}\n[exit {code}]\n{out}")
            if code != 0:
                break
        return "\n\n".join(report)

    def run_command(self, command: str, cwd: str = ".") -> str:
        """Arbitrary shell command - always asks the user first."""
        d = self._resolve(cwd)
        if not self.confirm(f"J.A.R.V.I.S. wants to run: {command!r} in {d}"):
            return "user declined to run this command"
        code, out = self._exec(command, d, "", shell=True)
        return f"[exit {code}]\n{out}"

    # ---- plumbing ----------------------------------------------------
    def _exec(self, cmd, cwd: Path, stdin: str, shell: bool = False) -> tuple[int, str]:
        try:
            r = subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, text=True,
                               timeout=self.timeout, shell=shell)
        except subprocess.TimeoutExpired:
            return 124, f"timed out after {self.timeout}s"
        except FileNotFoundError as e:
            return 127, str(e)
        out = (r.stdout + ("\n[stderr]\n" + r.stderr if r.stderr else "")).strip()
        if len(out) > MAX_OUTPUT:
            out = out[:MAX_OUTPUT // 2] + "\n...[truncated]...\n" + out[-MAX_OUTPUT // 2:]
        return r.returncode, out

    def dispatch(self, name: str, tool_input: dict) -> tuple[str, bool]:
        """Run a tool by name. Returns (result_text, is_error)."""
        fn = getattr(self, name, None)
        if name not in TOOL_NAMES or fn is None:
            return f"unknown tool: {name}", True
        try:
            return fn(**tool_input), False
        except ToolError as e:
            return str(e), True
        except TypeError as e:  # bad/missing arguments
            return f"bad arguments for {name}: {e}; got {json.dumps(tool_input)[:500]}", True


def _which(*names: str) -> str:
    for n in names:
        if path := shutil.which(n):
            return path
    raise ToolError(f"none of {names} is installed")


def _find_cmake_exe(d: Path) -> str:
    build = d / "build"
    if build.is_dir():
        for f in sorted(build.rglob("*")):
            if f.is_file() and f.stat().st_mode & 0o111 and "CMakeFiles" not in f.parts \
                    and f.suffix not in (".so", ".a", ".dylib", ".sh", ".cmake"):
                return str(f)
    return str(build / "main")


TOOL_SCHEMAS = [
    {
        "name": "write_file",
        "description": "Create or overwrite a text file in the workspace. Use this to write source code, "
                       "Cargo.toml, CMakeLists.txt, READMEs etc. Paths are relative to the workspace.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative path, e.g. 'wordcount/src/main.rs'"},
                "content": {"type": "string", "description": "Full file contents"},
            },
            "required": ["path", "content"],
            "additionalProperties": False,
        },
    },
    {
        "name": "read_file",
        "description": "Read a text file from the workspace.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_files",
        "description": "List files (recursively) under a workspace directory.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "Relative directory, default '.'"}},
            "required": [],
            "additionalProperties": False,
        },
    },
    {
        "name": "build_and_run",
        "description": "Build and run a project directory. python: runs main.py. rust: 'cargo run' if "
                       "Cargo.toml exists, else rustc main.rs. cpp: CMake if CMakeLists.txt exists, else "
                       "g++ -std=c++20 on all *.cpp. Returns compiler and program output; use it to test "
                       "and fix what you build.",
        "input_schema": {
            "type": "object",
            "properties": {
                "project_dir": {"type": "string"},
                "language": {"type": "string", "enum": list(LANGUAGES)},
                "args": {"type": "array", "items": {"type": "string"}},
                "stdin": {"type": "string", "description": "Text piped to the program's stdin"},
            },
            "required": ["project_dir", "language"],
            "additionalProperties": False,
        },
    },
    {
        "name": "run_command",
        "description": "Run a shell command inside the workspace (e.g. 'pip install x', 'cargo add serde', "
                       "'cargo test'). The user must approve every command, so prefer build_and_run.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "cwd": {"type": "string", "description": "Relative directory, default '.'"},
            },
            "required": ["command"],
            "additionalProperties": False,
        },
    },
]
TOOL_NAMES = {t["name"] for t in TOOL_SCHEMAS}
