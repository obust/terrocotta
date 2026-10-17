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
"$python_command" -m py_compile bench/report.py bench/*/main.py
for benchmark_runner in bench/*/main.py; do
	"$python_command" "$benchmark_runner" --check
done

for entrypoint in "${example_entrypoints[@]}"; do
	if [[ ! -f $entrypoint ]]; then
		echo "Error: example entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	run_roc_check "$roc_command" check "$entrypoint"
done

while IFS= read -r entrypoint; do
	filename=${entrypoint##*/}
	parent=${entrypoint%/*}
	if [[ $parent != bench && ( $filename != main.roc || ${parent%/*} != bench ) ]]; then
		continue
	fi
	if [[ ! -f $entrypoint ]]; then
		echo "Error: benchmark entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	run_roc_check "$roc_command" check "$entrypoint"
done < <(find bench -maxdepth 2 -type f -name '*.roc' -print | LC_ALL=C sort)
