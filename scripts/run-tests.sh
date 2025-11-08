#!/usr/bin/env bash
# Local testing harness for Phantom
#
# Runs `zig build` followed by `zig build test`, with optional flags for release builds
# or skipping stages. Designed to keep all verification local per project policy.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

usage() {
	cat <<'EOF'
Usage: scripts/run-tests.sh [options]

Options:
  --skip-build        Skip the initial `zig build` step.
  --skip-tests        Skip running `zig build test`.
  --release-safe      Build and test using -Drelease-safe.
  --release-fast      Build and test using -Drelease-fast.
  --release-small     Build and test using -Drelease-small.
  --zig-flag <flag>   Pass an arbitrary flag through to both build and test commands.
  --help              Show this message and exit.

All other arguments are forwarded to the `zig build test` step.
EOF
}

RUN_BUILD=true
RUN_TESTS=true
RELEASE_FLAG=""
FORWARDED_FLAGS=()
TEST_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-build)
			RUN_BUILD=false
			shift
			;;
		--skip-tests)
			RUN_TESTS=false
			shift
			;;
		--release-safe|--release-fast|--release-small)
			if [[ -n "${RELEASE_FLAG}" ]]; then
				echo "Only one release flag may be specified" >&2
				exit 1
			fi
			RELEASE_FLAG="-D${1#--}"
			shift
			;;
		--zig-flag)
			if [[ $# -lt 2 ]]; then
				echo "--zig-flag requires an argument" >&2
				exit 1
			fi
			FORWARDED_FLAGS+=("$2")
			shift 2
			;;
		--help)
			usage
			exit 0
			;;
		--*)
			echo "Unknown option: $1" >&2
			exit 1
			;;
		*)
			TEST_EXTRA_ARGS+=("$1")
			shift
			continue
			;;
	 esac
 done

ZIG_BIN="${ZIG:-zig}"

if ! command -v "${ZIG_BIN}" >/dev/null 2>&1; then
	echo "zig executable not found in PATH (checked \"${ZIG_BIN}\")" >&2
	exit 1
fi

ZIG_VERSION="$("${ZIG_BIN}" version)"
echo "Using ${ZIG_BIN} ${ZIG_VERSION}"

COMMON_FLAGS=()
if [[ -n "${RELEASE_FLAG}" ]]; then
	COMMON_FLAGS+=("${RELEASE_FLAG}")
fi
if [[ ${#FORWARDED_FLAGS[@]} -gt 0 ]]; then
	COMMON_FLAGS+=("${FORWARDED_FLAGS[@]}")
fi

if [[ "${RUN_BUILD}" == true ]]; then
	echo "==> ${ZIG_BIN} build ${COMMON_FLAGS[*]}"
	"${ZIG_BIN}" build "${COMMON_FLAGS[@]}"
fi

if [[ "${RUN_TESTS}" == true ]]; then
	echo "==> ${ZIG_BIN} build test ${COMMON_FLAGS[*]} ${TEST_EXTRA_ARGS[*]}"
	"${ZIG_BIN}" build test "${COMMON_FLAGS[@]}" "${TEST_EXTRA_ARGS[@]}"
fi
