import shutil
from pathlib import Path

import pytest

from jarvis.tools import Toolbox


@pytest.fixture
def tb(tmp_path: Path) -> Toolbox:
    return Toolbox(tmp_path / "ws", confirm=lambda _: False, timeout=120)


def test_write_read_list(tb):
    tb.write_file("demo/hello.txt", "hi")
    assert tb.read_file("demo/hello.txt") == "hi"
    assert "demo/hello.txt" in tb.list_files()


def test_path_escape_blocked(tb):
    out, err = tb.dispatch("write_file", {"path": "../evil.txt", "content": "x"})
    assert err and "escapes" in out


def test_unknown_tool_and_bad_args(tb):
    assert tb.dispatch("rm_rf", {})[1]
    assert tb.dispatch("write_file", {"path": "a"})[1]


def test_run_command_requires_approval(tb):
    out, err = tb.dispatch("run_command", {"command": "echo hi"})
    assert not err and "declined" in out


def test_python_project(tb):
    tb.write_file("py/main.py", "import sys\nprint('sum', sum(map(int, sys.argv[1:])))")
    out = tb.build_and_run("py", "python", ["2", "3"])
    assert "[exit 0]" in out and "sum 5" in out


@pytest.mark.skipif(not shutil.which("g++"), reason="g++ not installed")
def test_cpp_project(tb):
    tb.write_file("cpp/main.cpp", '#include <iostream>\nint main(){std::string s;std::cin>>s;std::cout<<"got "<<s;}')
    out = tb.build_and_run("cpp", "cpp", stdin="jarvis")
    assert "got jarvis" in out


@pytest.mark.skipif(not shutil.which("cargo"), reason="cargo not installed")
def test_rust_cargo_project(tb):
    tb.write_file("rs/Cargo.toml", '[package]\nname = "rs"\nversion = "0.1.0"\nedition = "2021"\n')
    tb.write_file("rs/src/main.rs", 'fn main(){ println!("hello from rust"); }')
    out = tb.build_and_run("rs", "rust")
    assert "hello from rust" in out


@pytest.mark.skipif(not shutil.which("g++"), reason="g++ not installed")
def test_compile_error_reported(tb):
    tb.write_file("bad/main.cpp", "int main(){ return x; }")
    out = tb.build_and_run("bad", "cpp")
    assert "[exit 0]" not in out and "error" in out
