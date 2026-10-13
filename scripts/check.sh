#!/usr/bin/env bash

# Validate compiler pins, formatting, and every example application.
# Usage: scripts/check.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/utils.sh"
cd "$root_dir"
roc_command="${ROC:-roc}"

validate_roc_version "$root_dir" "$roc_command"
"$roc_command" fmt --check package examples
python3 -m unittest discover -s scripts -p 'test_*.py'

for entrypoint in "${example_entrypoints[@]}"; do
	if [[ ! -f $entrypoint ]]; then
		echo "Error: example entrypoint does not exist: $entrypoint" >&2
		exit 1
	fi
	configured_dependency=$(python3 scripts/example_dependencies.py "$entrypoint")
	entrypoint_dir=$(dirname "$entrypoint")
	entrypoint_file=$(basename "$entrypoint")
	if [[ $configured_dependency == http://* || $configured_dependency == https://* ]]; then
		(
			cd "$entrypoint_dir"
			run_roc_check "$roc_command" check "$entrypoint_file" \
				--replace-dep "$configured_dependency" "$root_dir/package/main.roc"
		)
	else
		dependency_path="$entrypoint_dir/$configured_dependency"
		dependency_dir=$(cd "$(dirname "$dependency_path")" && pwd -P)
		dependency_path="$dependency_dir/$(basename "$dependency_path")"
		if [[ $dependency_path != "$root_dir/package/main.roc" ]]; then
			echo "Error: $entrypoint uses unexpected local tc dependency: $configured_dependency" >&2
			exit 1
		fi
		run_roc_check "$roc_command" check "$entrypoint"
	fi
done

python3 scripts/test_bundle_examples.py --validate-entrypoints "${example_entrypoints[@]}"
