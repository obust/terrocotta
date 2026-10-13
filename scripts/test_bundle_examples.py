#!/usr/bin/env python3
"""Check every example against a real Terrocotta package archive."""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import re
import subprocess
import sys
import threading
from pathlib import Path
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
APP_HEADER = re.compile(r"(?m)^\s*app\s*\[")
PACKAGE_DEPENDENCY = re.compile(r'(?m)^\s*tc:\s*"([^"]+)"\s*,?\s*$')


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass


def discover_entrypoints() -> list[Path]:
    return sorted(
        path
        for path in (ROOT / "examples").rglob("*.roc")
        if APP_HEADER.search(path.read_text(encoding="utf-8"))
    )


def resolve_entrypoints(relative_paths: list[str]) -> list[Path]:
    entries: list[Path] = []
    for relative in relative_paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"Invalid example entrypoint path: {relative}")
        full_path = ROOT / path
        if not full_path.is_file():
            raise SystemExit(f"Example entrypoint does not exist: {relative}")
        entries.append(full_path)
    if len(entries) != len(set(entries)):
        raise SystemExit("Duplicate example entrypoint")
    return entries


def validate_entrypoints(entrypoints: list[Path], discovered: list[Path]) -> None:
    listed = set(entrypoints)
    discovered_set = set(discovered)
    if discovered_set != listed:
        missing = sorted(path.relative_to(ROOT).as_posix() for path in discovered_set - listed)
        stale = sorted(path.relative_to(ROOT).as_posix() for path in listed - discovered_set)
        details = []
        if missing:
            details.append(f"missing from utils.sh: {', '.join(missing)}")
        if stale:
            details.append(f"not an app entrypoint: {', '.join(stale)}")
        raise SystemExit("Example entrypoint array is out of date; " + "; ".join(details))

    for entrypoint in entrypoints:
        matches = PACKAGE_DEPENDENCY.findall(entrypoint.read_text(encoding="utf-8"))
        if len(matches) != 1:
            relative = entrypoint.relative_to(ROOT)
            raise SystemExit(f"Expected exactly one tc dependency in {relative}; found {len(matches)}")


def start_server(directory: Path) -> tuple[http.server.ThreadingHTTPServer, str]:
    handler = functools.partial(QuietHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_port}"


def run_check(entrypoint: Path, bundle_url: str) -> None:
    source = entrypoint.read_text(encoding="utf-8")
    local_dependency = PACKAGE_DEPENDENCY.findall(source)[0]
    command = [
        ROC,
        "check",
        entrypoint.name,
        "--no-cache",
        "--replace-dep",
        local_dependency,
        bundle_url,
    ]
    print("+", " ".join(command), flush=True)
    completed = subprocess.run(
        command,
        cwd=entrypoint.parent,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if completed.stdout:
        print(completed.stdout, end="")
    warning_success = completed.returncode == 2 and re.search(
        r"0 errors and [0-9]+ warning", completed.stdout
    )
    if completed.returncode != 0 and not warning_success:
        raise SystemExit(
            f"Roc check failed with exit code {completed.returncode}: {entrypoint.relative_to(ROOT)}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path)
    parser.add_argument("--validate-entrypoints", nargs="+")
    args = parser.parse_args()

    discovered = discover_entrypoints()
    if not discovered:
        raise SystemExit("No example entrypoints found under examples/")
    entrypoints = discovered
    if args.validate_entrypoints is not None:
        entrypoints = resolve_entrypoints(args.validate_entrypoints)
        validate_entrypoints(entrypoints, discovered)
    else:
        validate_entrypoints(discovered, discovered)

    if args.validate_entrypoints is not None and args.bundle_path is None:
        print(f"Validated {len(entrypoints)} example entrypoints.")
        return
    if args.bundle_path is None:
        parser.error("--bundle-path is required unless --validate-entrypoints is used")

    bundle_path = args.bundle_path.resolve()
    if not bundle_path.is_file() or bundle_path.suffixes[-2:] != [".tar", ".zst"]:
        parser.error("--bundle-path must be an existing .tar.zst archive")

    server, base_url = start_server(bundle_path.parent)
    try:
        bundle_url = f"{base_url}/{quote(bundle_path.name)}"
        for entrypoint in entrypoints:
            run_check(entrypoint, bundle_url)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
