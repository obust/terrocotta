#!/usr/bin/env python3
"""Find and update Terrocotta dependencies in example app headers."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_HEADER = re.compile(r"(?m)^\s*app\s*\[")
# Tokenize enough of an app header to ignore comments and quoted contents.
TOKENS = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9]*|[^\s]')


def read_alias(root: Path = ROOT) -> str:
    path = root / ".package-alias"
    try:
        alias = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        raise ValueError(f"Missing {path}; put the example package alias in this file.") from None
    if not re.fullmatch(r"[a-z][A-Za-z_0-9]*", alias) or alias in {"roc", "platform"}:
        raise ValueError(f"{path}: expected one package alias, such as tc.")
    return alias


def discover_entrypoints(examples_dir: Path = ROOT / "examples") -> list[Path]:
    return sorted(
        path
        for path in examples_dir.rglob("*.roc")
        if APP_HEADER.search(path.read_text(encoding="utf-8"))
    )


def dependency_token(source: str, alias: str) -> re.Match[str]:
    tokens = [match for match in TOKENS.finditer(source) if not match[0].startswith("#")]
    if len(tokens) < 3 or tokens[0][0] != "app" or tokens[1][0] != "[":
        raise ValueError("expected an app header")

    index = 2
    depth = 1
    while index < len(tokens) and depth:
        value = tokens[index][0]
        depth += (value == "[") - (value == "]")
        index += 1
    if index >= len(tokens) or tokens[index][0] != "{":
        raise ValueError("expected an app dependency record")

    index += 1
    depth = 1
    declarations: list[re.Match[str]] = []
    while index < len(tokens) and depth:
        value = tokens[index][0]
        if depth == 1 and value == alias and tokens[index - 1][0] in {"{", ","}:
            if index + 2 >= len(tokens) or tokens[index + 1][0] != ":":
                raise ValueError(f'expected {alias}: "package source"')
            declarations.append(tokens[index + 2])
        depth += (value == "{") - (value == "}")
        index += 1
    if depth:
        raise ValueError("unterminated app dependency record")
    if len(declarations) != 1:
        raise ValueError(
            f'expected exactly one {alias}: "package source" in the app header; found {len(declarations)}'
        )

    declaration = declarations[0]
    if re.fullmatch(r'"(?:\\.|[^"\\])*"', declaration[0]) is None or declaration[0].startswith('"""'):
        raise ValueError(f"{alias} must name a quoted package source, not a platform or expression")
    return declaration


def dependency_source(source: str, alias: str) -> str:
    return json.loads(dependency_token(source, alias)[0])


def replace_dependency(source: str, alias: str, target: str) -> str:
    declaration = dependency_token(source, alias)
    return source[: declaration.start()] + json.dumps(target, ensure_ascii=False) + source[declaration.end() :]


def update_entrypoints(entrypoints: list[Path], alias: str, target: str) -> None:
    rewritten: list[tuple[Path, str]] = []
    for path in entrypoints:
        try:
            source = path.read_text(encoding="utf-8")
            rewritten.append((path, replace_dependency(source, alias, target)))
        except ValueError as error:
            raise ValueError(f"{path}: {error}") from error

    # Validate every entrypoint before changing any file.
    for path, source in rewritten:
        if source != path.read_text(encoding="utf-8"):
            path.write_text(source, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entrypoint", type=Path, help="Print this app's configured package source")
    args = parser.parse_args()
    try:
        print(dependency_source(args.entrypoint.read_text(encoding="utf-8"), read_alias()))
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
