#!/usr/bin/env bash

# Run the package and example Roc expect tests with the pinned compiler.
# Usage: scripts/test.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/utils.sh"
cd "$root_dir"
roc_command="${ROC:-roc}"

validate_roc_version "$root_dir" "$roc_command"
run_roc_test "$roc_command" test package/main.roc

for entrypoint in "${example_entrypoints[@]}"; do
	if [[ ! -f $entrypoint ]]; then
		echo "Error: example entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	run_roc_test "$roc_command" test "$entrypoint"
done
