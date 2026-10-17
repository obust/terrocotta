#!/usr/bin/env python3
"""Validate and summarize a Terrocotta Observatory benchmark capture."""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any


SUPPORTED_SCHEMA = 1
SQL_DIR = Path(__file__).resolve().parent / "sql"
REQUIRED_TABLES = {
    "allocation_events",
    "annotations",
    "measurement_status",
    "metadata",
    "recorder_health",
}
BASELINE_METADATA = (
    "schema_version",
    "app_name",
    "target_profile",
    "backend",
    "roc_compiler_pin",
    "effective_detail",
)
COMPARISON_METADATA = BASELINE_METADATA + ("host_os", "host_arch")


class ReportError(Exception):
    """The capture cannot support an honest benchmark report."""


def benchmark_query(benchmark: str, purpose: str) -> Path:
    if re.fullmatch(r"[a-z0-9][a-z0-9-]*", benchmark) is None:
        raise ReportError(f"invalid benchmark name: {benchmark!r}")
    bundled = SQL_DIR.parent / benchmark / "sql" / f"{purpose}.sql"
    if bundled.is_file():
        return bundled
    return SQL_DIR / f"{benchmark}-{purpose}.sql"


def open_readonly(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ReportError(f"capture does not exist: {path}")
    try:
        connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only=ON")
        connection.execute("PRAGMA trusted_schema=OFF")
        return connection
    except sqlite3.Error as error:
        raise ReportError(f"cannot open capture read-only: {error}") from error


def read_query(name: str | Path) -> str:
    path = Path(name)
    if not path.is_absolute():
        path = SQL_DIR / path
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise ReportError(f"cannot read query {path}: {error}") from error


def query(connection: sqlite3.Connection, name: str | Path) -> list[dict[str, Any]]:
    try:
        return [dict(row) for row in connection.execute(read_query(name))]
    except sqlite3.Error as error:
        raise ReportError(f"query {name} failed: {error}") from error


def metadata(connection: sqlite3.Connection) -> dict[str, str]:
    return dict(connection.execute("SELECT key, value FROM metadata"))


def validate(
    connection: sqlite3.Connection, benchmark: str
) -> tuple[dict[str, str], list[dict[str, Any]]]:
    tables = {
        row[0]
        for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    missing_tables = sorted(REQUIRED_TABLES - tables)
    if missing_tables:
        raise ReportError(f"capture is missing tables: {', '.join(missing_tables)}")

    facts = metadata(connection)
    if facts.get("schema_version") != str(SUPPORTED_SCHEMA):
        raise ReportError(
            f"unsupported schema version {facts.get('schema_version')!r}; "
            f"expected {SUPPORTED_SCHEMA}"
        )
    bundled_entrypoint = SQL_DIR.parent / benchmark / "main.roc"
    expected_app = benchmark if bundled_entrypoint.is_file() else f"{benchmark}.roc"
    if facts.get("app_name") != expected_app:
        raise ReportError(
            f"capture belongs to {facts.get('app_name')!r}, expected {expected_app!r}"
        )

    health = query(connection, "capture_health.sql")
    if not health or any(row["evidence_status"] != "complete" for row in health):
        reason = health[0]["evidence_reason"] if health else "capture health is missing"
        raise ReportError(f"capture is incomplete: {reason}")

    statuses = {row["measurement"]: row["measurement_status"] for row in health}
    for measurement in ("allocation_lifecycle", "annotations"):
        if statuses.get(measurement) != "complete":
            raise ReportError(
                f"{measurement} evidence is {statuses.get(measurement, 'missing')}, not complete"
            )

    bad_zones = query(connection, benchmark_query(benchmark, "required-zones"))
    if bad_zones:
        details = ", ".join(
            f"{row['name']} (completed={row['completed']}, aborted={row['aborted']})"
            for row in bad_zones
        )
        raise ReportError(f"required benchmark zones are invalid: {details}")

    return facts, health


def format_value(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.3f}"
    return str(value)


def print_table(title: str, rows: list[dict[str, Any]], columns: tuple[str, ...]) -> None:
    print(f"\n{title}")
    if not rows:
        print("(no rows)")
        return
    rendered = [[format_value(row.get(column)) for column in columns] for row in rows]
    widths = [
        max(len(column), *(len(row[index]) for row in rendered))
        for index, column in enumerate(columns)
    ]
    print("  ".join(column.ljust(widths[index]) for index, column in enumerate(columns)))
    print("  ".join("-" * width for width in widths))
    for row in rendered:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))


def baseline_document(
    facts: dict[str, str], zones: list[dict[str, Any]]
) -> dict[str, Any]:
    return {
        "format_version": 1,
        "metadata": {key: facts.get(key) for key in BASELINE_METADATA},
        "zones": {
            row["zone_name"]: {
                "max_allocation_calls": row["allocation_calls"],
                "max_allocated_bytes": row["allocated_bytes"],
            }
            for row in zones
        },
    }


def check_baseline(
    path: Path, facts: dict[str, str], zones: list[dict[str, Any]]
) -> None:
    try:
        baseline = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReportError(f"cannot read baseline {path}: {error}") from error
    if baseline.get("format_version") != 1:
        raise ReportError("unsupported benchmark baseline format")

    expected_metadata = baseline.get("metadata", {})
    mismatches = [
        key
        for key in BASELINE_METADATA
        if expected_metadata.get(key) != facts.get(key)
    ]
    if mismatches:
        raise ReportError(
            "capture and baseline metadata differ for: " + ", ".join(mismatches)
        )

    current = {row["zone_name"]: row for row in zones}
    expected_zones = baseline.get("zones", {})
    if set(current) != set(expected_zones):
        missing = sorted(set(expected_zones) - set(current))
        added = sorted(set(current) - set(expected_zones))
        raise ReportError(
            f"capture and baseline zones differ; missing={missing}, added={added}"
        )

    regressions: list[str] = []
    for name, limits in expected_zones.items():
        row = current[name]
        if row["allocation_calls"] > limits["max_allocation_calls"]:
            regressions.append(
                f"{name}: calls {row['allocation_calls']} > {limits['max_allocation_calls']}"
            )
        if row["allocated_bytes"] > limits["max_allocated_bytes"]:
            regressions.append(
                f"{name}: bytes {row['allocated_bytes']} > {limits['max_allocated_bytes']}"
            )
    if regressions:
        raise ReportError("allocation baseline regressed:\n  " + "\n  ".join(regressions))


def compare_captures(
    benchmark: str, current_path: Path, baseline_path: Path
) -> list[dict[str, Any]]:
    baseline_connection = open_readonly(baseline_path)
    try:
        baseline_facts, _ = validate(baseline_connection, benchmark)
    finally:
        baseline_connection.close()

    current_connection = open_readonly(current_path)
    try:
        current_facts, _ = validate(current_connection, benchmark)
        mismatches = [
            key
            for key in COMPARISON_METADATA
            if current_facts.get(key) != baseline_facts.get(key)
        ]
        if mismatches:
            raise ReportError(
                "captures are not comparable; metadata differs for: "
                + ", ".join(mismatches)
            )
    finally:
        current_connection.close()

    try:
        connection = sqlite3.connect(
            current_path.resolve().as_uri() + "?mode=ro", uri=True
        )
        connection.row_factory = sqlite3.Row
        connection.execute(
            "ATTACH DATABASE ? AS baseline",
            (baseline_path.resolve().as_uri() + "?mode=ro",),
        )
        connection.execute("PRAGMA query_only=ON")
        connection.execute("PRAGMA trusted_schema=OFF")
        return query(connection, "compare.sql")
    except sqlite3.Error as error:
        raise ReportError(f"cannot compare captures: {error}") from error
    finally:
        if "connection" in locals():
            connection.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("benchmark", help="benchmark name without the .roc suffix")
    parser.add_argument("capture", type=Path)
    parser.add_argument("--baseline", type=Path, help="fail on allocation regression")
    parser.add_argument("--compare", type=Path, help="report deltas from another capture")
    parser.add_argument("--json-out", type=Path, help="write the structured report")
    parser.add_argument(
        "--write-baseline", type=Path, help="write allocation limits from this capture"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        connection = open_readonly(args.capture)
        try:
            facts, health = validate(connection, args.benchmark)
            zones = query(connection, "zone_allocations.sql")
            benchmark_report = query(
                connection, benchmark_query(args.benchmark, "report")
            )
        finally:
            connection.close()

        if any(row["evidence_status"] != "complete" for row in zones):
            raise ReportError("zone allocation evidence is incomplete")

        if args.baseline:
            check_baseline(args.baseline, facts, zones)

        comparison = (
            compare_captures(args.benchmark, args.capture, args.compare)
            if args.compare
            else []
        )
        report = {
            "format_version": 1,
            "capture": str(args.capture),
            "metadata": facts,
            "capture_health": health,
            "zone_allocations": zones,
            "benchmark": args.benchmark,
            "benchmark_report": benchmark_report,
            "comparison": comparison,
        }

        print(f"Capture: {args.capture}")
        print(
            "Evidence: complete "
            f"(schema={facts['schema_version']}, detail={facts.get('effective_detail', 'unknown')})"
        )
        report_columns = (
            tuple(benchmark_report[0]) if benchmark_report else ("benchmark_report",)
        )
        print_table("Benchmark report", benchmark_report, report_columns)
        print_table(
            "Zone allocations",
            zones,
            ("zone_name", "allocation_calls", "allocated_bytes", "active_ns"),
        )
        if comparison:
            print_table(
                "Capture comparison",
                comparison,
                (
                    "zone_name",
                    "baseline_calls",
                    "current_calls",
                    "calls_delta",
                    "baseline_bytes",
                    "current_bytes",
                    "bytes_delta",
                ),
            )

        if args.json_out:
            args.json_out.parent.mkdir(parents=True, exist_ok=True)
            args.json_out.write_text(
                json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
            print(f"\nStructured report: {args.json_out}")

        if args.write_baseline:
            args.write_baseline.parent.mkdir(parents=True, exist_ok=True)
            args.write_baseline.write_text(
                json.dumps(baseline_document(facts, zones), indent=2, sort_keys=True)
                + "\n",
                encoding="utf-8",
            )
            print(f"Allocation baseline: {args.write_baseline}")

        if args.baseline:
            print(f"Allocation baseline: passed ({args.baseline})")
        return 0
    except (ReportError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
