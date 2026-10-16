#!/usr/bin/env bash

# Validate compiler pins, formatting, and every example application.
# Usage: scripts/check.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/utils.sh"
cd "$root_dir"
roc_command="${ROC:-roc}"
python_command="${PYTHON:-python3}"

validate_roc_version "$root_dir" "$roc_command"
"$roc_command" fmt --check package examples bench
"$python_command" -m py_compile bench/report.py
bench/bench.sh --check

for entrypoint in "${example_entrypoints[@]}"; do
	if [[ ! -f $entrypoint ]]; then
		echo "Error: example entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	run_roc_check "$roc_command" check "$entrypoint"
done

while IFS= read -r entrypoint; do
	if [[ ! -f $entrypoint ]]; then
		echo "Error: benchmark entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	run_roc_check "$roc_command" check "$entrypoint"
done < <(find bench -maxdepth 1 -type f -name '*.roc' -print | LC_ALL=C sort)
