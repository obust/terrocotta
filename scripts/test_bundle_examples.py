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

from example_dependencies import dependency_source, discover_entrypoints, read_alias


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass


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

    alias = read_alias()
    for entrypoint in entrypoints:
        try:
            dependency_source(entrypoint.read_text(encoding="utf-8"), alias)
        except ValueError as error:
            relative = entrypoint.relative_to(ROOT)
            raise SystemExit(f"{relative}: {error}") from error


def start_server(directory: Path) -> tuple[http.server.ThreadingHTTPServer, str]:
    handler = functools.partial(QuietHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_port}"


def run_check(entrypoint: Path, bundle_url: str, alias: str) -> None:
    source = entrypoint.read_text(encoding="utf-8")
    configured_dependency = dependency_source(source, alias)
    command = [
        ROC,
        "check",
        entrypoint.name,
        "--no-cache",
    ]
    if configured_dependency != bundle_url:
        command.extend(["--replace-dep", configured_dependency, bundle_url])
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
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--bundle-path", type=Path)
    source.add_argument("--bundle-url")
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

    if args.validate_entrypoints is not None and args.bundle_path is None and args.bundle_url is None:
        print(f"Validated {len(entrypoints)} example entrypoints.")
        return
    if args.bundle_path is None and args.bundle_url is None:
        parser.error("--bundle-path or --bundle-url is required unless --validate-entrypoints is used")

    alias = read_alias()
    if args.bundle_url is not None:
        if not re.fullmatch(r"https?://.+\.tar\.zst", args.bundle_url):
            parser.error("--bundle-url must be an HTTP(S) URL ending in .tar.zst")
        for entrypoint in entrypoints:
            run_check(entrypoint, args.bundle_url, alias)
        return

    assert args.bundle_path is not None
    bundle_path = args.bundle_path.resolve()
    if not bundle_path.is_file() or bundle_path.suffixes[-2:] != [".tar", ".zst"]:
        parser.error("--bundle-path must be an existing .tar.zst archive")

    server, base_url = start_server(bundle_path.parent)
    try:
        bundle_url = f"{base_url}/{quote(bundle_path.name)}"
        for entrypoint in entrypoints:
            run_check(entrypoint, bundle_url, alias)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
