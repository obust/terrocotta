#!/usr/bin/env python3
"""Update every example to use a published Terrocotta package archive."""

from __future__ import annotations

import argparse
from urllib.parse import urlsplit

from example_dependencies import discover_entrypoints, read_alias, update_entrypoints


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-url", required=True)
    args = parser.parse_args()

    parsed = urlsplit(args.bundle_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc or not parsed.path.endswith(".tar.zst"):
        parser.error("--bundle-url must be an HTTP(S) package URL ending in .tar.zst")

    try:
        alias = read_alias()
        entrypoints = discover_entrypoints()
        if not entrypoints:
            raise ValueError("No example entrypoints found under examples/")
        update_entrypoints(entrypoints, alias, args.bundle_url)
    except ValueError as error:
        parser.error(str(error))
    print(f'Updated {len(entrypoints)} examples to use {alias}: "{args.bundle_url}"')


if __name__ == "__main__":
    main()
