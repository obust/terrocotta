#!/usr/bin/env python3
"""Run, query, and validate the bundled text-ui benchmark."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BENCHMARK = "text-ui"
ENTRYPOINT = HERE / "text-ui.roc"
BASELINE = HERE / "baseline.json"
REPORTER = ROOT / "bench" / "report.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="capture directory (default: bench/text-ui/results/<UTC timestamp>)",
    )
    parser.add_argument(
        "--compare",
        type=Path,
        help="another text-ui .rrstats capture to compare",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="replace baseline.json after a successful capture and SQL validation",
    )
    parser.add_argument(
        "--roc",
        default=os.environ.get("ROC", "roc"),
        help="Roc executable (default: $ROC or roc)",
    )
    return parser.parse_args()


def resolve_from_root(path: Path) -> Path:
    return path if path.is_absolute() else ROOT / path


def run_capture(roc: str, capture: Path) -> None:
    command = [
        roc,
        "--no-cache",
        str(ENTRYPOINT.relative_to(ROOT)),
        "--",
        "--host-headless",
        "--host-headless-frames=1",
        "--host-stats-record",
        "--host-stats-detail=full",
        "--host-stats-max-mib=256",
        f"--host-stats-output={capture}",
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    print(completed.stdout, end="", flush=True)

    warning_only = (
        completed.returncode == 2
        and re.search(r"0 errors and [0-9]+ warning", completed.stdout) is not None
        and capture.is_file()
        and capture.stat().st_size > 0
    )
    if completed.returncode != 0 and not warning_only:
        raise RuntimeError(f"benchmark exited with status {completed.returncode}")


def run_report(capture: Path, report: Path, args: argparse.Namespace) -> None:
    command = [
        sys.executable,
        str(REPORTER),
        BENCHMARK,
        str(capture),
        "--json-out",
        str(report),
    ]
    if args.update_baseline:
        command.extend(("--write-baseline", str(BASELINE)))
    else:
        command.extend(("--baseline", str(BASELINE)))
    if args.compare:
        command.extend(("--compare", str(resolve_from_root(args.compare))))

    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    args = parse_args()
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    output_dir = (
        resolve_from_root(args.output_dir)
        if args.output_dir
        else HERE / "results" / stamp
    )
    capture = output_dir / f"{BENCHMARK}.rrstats"
    report = output_dir / f"{BENCHMARK}.json"

    output_dir.mkdir(parents=True, exist_ok=True)
    existing = [path for path in (capture, report) if path.exists()]
    if existing:
        joined = ", ".join(str(path) for path in existing)
        raise RuntimeError(f"refusing to overwrite existing output: {joined}")

    print(f"==> {BENCHMARK}", flush=True)
    run_capture(args.roc, capture)
    run_report(capture, report, args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
