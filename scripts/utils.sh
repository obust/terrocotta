#!/usr/bin/env bash

# Shared helpers for Terrocotta's Bash validation scripts.
#
# Source this file from a script using `set -euo pipefail`. The functions run
# commands in the caller's shell and write diagnostics directly to its output.

# Repository-relative paths to every runnable Roc example. `check.sh` verifies
# that each path exists and passes `roc check` against the working package.
example_entrypoints=(
	"examples/counter.roc"
	"examples/todos.roc"
	"examples/widgets.roc"
	"examples/tutorial/main.roc"
	"examples/ide/main.roc"
	"examples/screwbot/main.roc"
	"examples/game-sunnyland/main.roc"
)

# Run a Roc check command while streaming and inspecting its combined output.
#
# Usage: run_roc_check COMMAND [ARG ...]
#
# Roc returns status 2 when a check succeeds with warnings. This helper converts
# that status to success only when Roc also printed its explicit zero-error
# summary. It returns the command's original status in every other case.
run_roc_check() {
	local output_file status
	output_file=$(mktemp)
	set +e
	"$@" 2>&1 | tee "$output_file"
	status=${PIPESTATUS[0]}
	set -e
	if [[ $status -eq 2 ]] && grep -Eq '0 errors and [0-9]+ warning' "$output_file"; then
		status=0
	fi
	rm -f "$output_file"
	return "$status"
}

# Run a Roc test command while streaming and inspecting its combined output.
#
# Usage: run_roc_test COMMAND [ARG ...]
#
# Roc returns status 2 when tests pass with warnings. This helper converts that
# status to success only when Roc also printed its all-tests-passed summary. It
# returns the command's original status in every other case.
run_roc_test() {
	local output_file status
	output_file=$(mktemp)
	set +e
	"$@" 2>&1 | tee "$output_file"
	status=${PIPESTATUS[0]}
	set -e
	if [[ $status -eq 2 ]] && grep -Eq 'All \([0-9]+\) tests passed' "$output_file"; then
		status=0
	fi
	rm -f "$output_file"
	return "$status"
}

# Verify that the repository, package, and installed compiler use one Roc pin.
#
# Usage: validate_roc_version REPOSITORY_ROOT ROC_COMMAND
#
# Compares REPOSITORY_ROOT/.roc-version with the `roc:` field in
# package/main.roc and with the version reported by ROC_COMMAND. Returns success
# when all three match; otherwise prints a diagnostic and returns failure.
validate_roc_version() {
	local root_dir=$1
	local roc_command=$2
	local expected_version package_version installed_version

	expected_version=$(tr -d '\r\n' < "$root_dir/.roc-version")
	package_version=$(sed -nE 's/^[[:space:]]*roc: "([^"]+)",?$/\1/p' "$root_dir/package/main.roc")
	installed_version=$("$roc_command" version | awk '{print $NF}')

	if [[ $package_version != "$expected_version" ]]; then
		echo "Error: package/main.roc pins '$package_version'; expected '$expected_version' from .roc-version." >&2
		return 1
	fi
	if [[ $installed_version != "$expected_version" ]]; then
		echo "Error: expected Roc $expected_version, found $installed_version." >&2
		return 1
	fi
}
