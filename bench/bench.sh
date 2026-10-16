#!/usr/bin/env bash

# Capture and validate one or more Terrocotta performance benchmarks.
# Usage: bench/bench.sh [OPTIONS] [BENCHMARK ...]

set -euo pipefail

bench_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "$bench_dir/.." && pwd)
source "$root_dir/scripts/utils.sh"
roc_command=${ROC:-roc}
python_command=${PYTHON:-python3}
output_dir=""
compare_dir=""
update_baselines=0
list_only=0
check_only=0
selected=()
discovered=()

usage() {
	cat >&2 <<'EOF'
Usage: bench/bench.sh [OPTIONS] [BENCHMARK ...]

With no BENCHMARK arguments, run every top-level bench/*.roc entrypoint.

Options:
  --list                  List discovered benchmark names.
  --check                 Validate benchmark companion files without running.
  --output-dir DIR        Write captures and reports under DIR.
  --compare-dir DIR       Compare each run with DIR/BENCHMARK.rrstats.
  --update-baselines      Replace committed allocation limits after validation.
  -h, --help              Show this help.
EOF
	exit "${1:-2}"
}

while (($# > 0)); do
	case "$1" in
	--list)
		list_only=1
		shift
		;;
	--check)
		check_only=1
		shift
		;;
	--output-dir)
		[[ $# -ge 2 ]] || usage
		output_dir=$2
		shift 2
		;;
	--compare-dir)
		[[ $# -ge 2 ]] || usage
		compare_dir=$2
		shift 2
		;;
	--update-baselines | --update-baseline)
		update_baselines=1
		shift
		;;
	-h | --help)
		usage 0
		;;
	--*)
		usage
		;;
	*)
		selected+=("${1%.roc}")
		shift
		;;
	esac
done

while IFS= read -r entrypoint; do
	filename=${entrypoint##*/}
	parent=${entrypoint%/*}
	name=${filename%.roc}
	# A bundled benchmark is bench/NAME/NAME.roc. Other nested Roc files are
	# support material rather than independently runnable entrypoints.
	if [[ $parent == "$bench_dir" || ${parent##*/} == "$name" ]]; then
		discovered+=("$name")
	fi
done < <(find "$bench_dir" -maxdepth 2 -type f -name '*.roc' -print | LC_ALL=C sort)

if ((${#discovered[@]} == 0)); then
	echo "Error: no top-level benchmark entrypoints found under bench/" >&2
	exit 1
fi

if [[ $list_only -eq 1 ]]; then
	printf '%s\n' "${discovered[@]}"
	exit 0
fi

if ((${#selected[@]} == 0)); then
	selected=("${discovered[@]}")
fi

for name in "${selected[@]}"; do
	if [[ ! $name =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
		echo "Error: invalid benchmark name: $name" >&2
		exit 2
	fi
	if [[ -f $bench_dir/$name.roc ]]; then
		benchmark_dir=$bench_dir
	elif [[ -f $bench_dir/$name/$name.roc ]]; then
		benchmark_dir=$bench_dir/$name
	else
		echo "Error: benchmark does not exist: $name" >&2
		exit 1
	fi
	for purpose in required-zones report; do
		if [[ $benchmark_dir == "$bench_dir" ]]; then
			query="$bench_dir/queries/$name-$purpose.sql"
		else
			query="$benchmark_dir/sql/$purpose.sql"
		fi
		if [[ ! -f $query ]]; then
			echo "Error: benchmark query does not exist: $query" >&2
			exit 1
		fi
	done
	if [[ $benchmark_dir == "$bench_dir" ]]; then
		baseline="$bench_dir/baselines/$name.json"
	else
		baseline="$benchmark_dir/baseline.json"
	fi
	if [[ $update_baselines -eq 0 && ! -f $baseline ]]; then
		echo "Error: allocation baseline does not exist: $baseline" >&2
		echo "Run with --update-baselines after reviewing the benchmark." >&2
		exit 1
	fi
done

if [[ $check_only -eq 1 ]]; then
	printf 'Validated %s benchmark definition(s).\n' "${#selected[@]}"
	exit 0
fi

default_output_dir=0
if [[ -z $output_dir ]]; then
	stamp=$(date -u +%Y%m%dT%H%M%SZ)
	default_output_dir=1
elif [[ $output_dir != /* ]]; then
	output_dir="$root_dir/$output_dir"
fi
if [[ -n $compare_dir && $compare_dir != /* ]]; then
	compare_dir="$root_dir/$compare_dir"
fi

log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT

cd "$root_dir"
validate_roc_version "$root_dir" "$roc_command"

for name in "${selected[@]}"; do
	if [[ -f $bench_dir/$name.roc ]]; then
		entrypoint="bench/$name.roc"
		baseline="$bench_dir/baselines/$name.json"
		if [[ $default_output_dir -eq 1 ]]; then
			benchmark_output_dir="$bench_dir/results/$stamp"
		else
			benchmark_output_dir=$output_dir
		fi
	else
		entrypoint="bench/$name/$name.roc"
		baseline="$bench_dir/$name/baseline.json"
		if [[ $default_output_dir -eq 1 ]]; then
			benchmark_output_dir="$bench_dir/$name/results/$stamp"
		else
			benchmark_output_dir=$output_dir
		fi
	fi
	mkdir -p "$benchmark_output_dir"
	capture="$benchmark_output_dir/$name.rrstats"
	report="$benchmark_output_dir/$name.json"

	if [[ -e $capture || -e $report ]]; then
		echo "Error: refusing to overwrite benchmark output for $name under $benchmark_output_dir" >&2
		exit 1
	fi
	echo "==> $name"
	: >"$log_file"
	set +e
	"$roc_command" --no-cache "$entrypoint" -- \
		--host-headless \
		--host-headless-frames=1 \
		--host-stats-record \
		--host-stats-detail=full \
		--host-stats-max-mib=256 \
		--host-stats-output="$capture" 2>&1 | tee "$log_file"
	roc_status=${PIPESTATUS[0]}
	set -e

	# Roc uses status 2 for successful checks/runs that emitted warnings.
	if [[ $roc_status -eq 2 ]] \
		&& grep -Eq '0 errors and [0-9]+ warning' "$log_file" \
		&& [[ -s $capture ]]; then
		roc_status=0
	fi
	if [[ $roc_status -ne 0 ]]; then
		echo "Error: benchmark $name failed with status $roc_status" >&2
		exit "$roc_status"
	fi

	report_args=("$name" "$capture" --json-out "$report")
	if [[ $update_baselines -eq 1 ]]; then
		report_args+=(--write-baseline "$baseline")
	else
		report_args+=(--baseline "$baseline")
	fi
	if [[ -n $compare_dir ]]; then
		comparison="$compare_dir/$name.rrstats"
		if [[ ! -f $comparison ]]; then
			echo "Error: comparison capture does not exist: $comparison" >&2
			exit 1
		fi
		report_args+=(--compare "$comparison")
	fi

	"$python_command" "$bench_dir/report.py" "${report_args[@]}"
done
