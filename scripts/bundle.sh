#!/usr/bin/env bash

# Create a content-addressed archive containing every package module.
# Usage: scripts/bundle.sh [--output-dir DIR] [ROC BUNDLE ARGUMENTS ...]
# Set ROC to override the compiler command; output defaults to dist/.

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$root_dir/dist"
roc_command="${ROC:-roc}"
extra_args=()

while (($# > 0)); do
	case "$1" in
		--output-dir)
			if (($# < 2)) || [[ -z $2 ]]; then
				echo "Error: --output-dir requires a directory." >&2
				exit 2
			fi
			output_dir=$2
			shift 2
			;;
		--output-dir=*)
			output_dir=${1#--output-dir=}
			shift
			;;
		*)
			extra_args+=("$1")
			shift
			;;
	esac
done

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
cd "$root_dir/package"

# Include every package module, including internal modules and widgets. Keep the
# package entrypoint first so consumers resolve the archive correctly.
roc_files=(main.roc)
while IFS= read -r roc_file; do
	roc_files+=("${roc_file#./}")
done < <(find . -type f -name '*.roc' ! -path './main.roc' -print | LC_ALL=C sort)

if ((${#extra_args[@]} > 0)); then
	"$roc_command" bundle "${roc_files[@]}" --output-dir "$output_dir" "${extra_args[@]}"
else
	"$roc_command" bundle "${roc_files[@]}" --output-dir "$output_dir"
fi
