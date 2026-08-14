#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/docker-utils.sh
source "$REPO_ROOT/scripts/docker-utils.sh"
# shellcheck source=scripts/ensure_exec.sh
source "$REPO_ROOT/scripts/ensure_exec.sh"

DOCKER_BIN="${DOCKER_BIN:-docker}"
DOCKER_BUILD_CACHE_DIR="${DOCKER_BUILD_CACHE_DIR:-$REPO_ROOT/.cache/docker-buildx}"
MATRIX_RUN_ID="${MATRIX_RUN_ID:-$(date +%s)-$$}"
PARALLEL=1
COMPAT_ONLY=0
E2E_ONLY=0
RUN_COVERAGE_GATE=0
SELECTED_DISTROS=()
ACTIVE_PIDS=()
CLEANUP_RUNNING=0

# OS families with Raspberry Pi images (Pi 3/4 class; Pi 5 support varies by upstream).
# CI containers exercise apt/dnf/pacman paths used on Pi ARM installs.
DISTROS=(
    "debian:trixie"
    "ubuntu:26.04"
    "fedora:44"
    "rocky:9"
    "archlinux:latest"
)
COVERAGE_DISTRO="debian:trixie"

usage() {
    cat << 'EOF'
Usage: run_docker_matrix.sh [--serial|--parallel] [--compat-only|--e2e-only|--coverage-gate]
                            [--distro <image>] [--print-supported-distros]

Default matrix lane runs compat then e2e in the same container.
EOF
}

cleanup() {
    [[ "$CLEANUP_RUNNING" -eq 1 ]] && return
    CLEANUP_RUNNING=1
    local pid
    for pid in ${ACTIVE_PIDS[@]+"${ACTIVE_PIDS[@]}"}; do
        kill "$pid" 2> /dev/null || true
    done
}
trap cleanup INT TERM HUP EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --serial)
            PARALLEL=0
            shift
            ;;
        --parallel)
            PARALLEL=1
            shift
            ;;
        --compat-only)
            COMPAT_ONLY=1
            E2E_ONLY=0
            shift
            ;;
        --e2e-only)
            E2E_ONLY=1
            COMPAT_ONLY=0
            shift
            ;;
        --coverage-gate)
            RUN_COVERAGE_GATE=1
            shift
            ;;
        --print-supported-distros)
            printf '%s\n' "${DISTROS[@]}"
            exit 0
            ;;
        --distro)
            if [ $# -lt 2 ]; then
                echo "ERROR: --distro requires a value" >&2
                usage >&2
                exit 1
            fi
            SELECTED_DISTROS+=("$2")
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

mkdir -p "$REPO_ROOT/reports/distro-logs"

run_in_distro() {
    local image="$1"
    local mode="$2"
    local slug tag dockerfile log container_cmd host_uid host_gid
    slug=$(image_slug_from_ref "$image")
    tag=$(test_image_tag_for_slug "$slug")
    dockerfile="$REPO_ROOT/$(dockerfile_for_distro "$image")"
    log="$REPO_ROOT/reports/distro-logs/${slug}-${mode}.log"
    host_uid="$(id -u)"
    host_gid="$(id -g)"

    if [ ! -f "$dockerfile" ]; then
        echo "Missing Dockerfile for $image ($dockerfile)" >&2
        return 1
    fi

    echo "=== Building $tag ==="
    docker_build_with_cache "$dockerfile" "$tag" "$REPO_ROOT" "$DOCKER_BUILD_CACHE_DIR" "$slug"

    case "$mode" in
        coverage)
            # Prefer full gate when cobertura exists after suite
            container_cmd='set -euo pipefail; export COVERAGE=1 COVERAGE_OUTPUT=/home/pi/coverage; '
            container_cmd+='mkdir -p /home/pi/coverage; ./tests/run_suite.sh; '
            container_cmd+='if [ -f coverage/cobertura.xml ]; then '
            container_cmd+='python3 tests/transform_coverage.py coverage/cobertura.xml '
            container_cmd+='--fail-under 90 --fail-under-per-file 90 '
            container_cmd+='--max-complexity-overall 15 --max-complexity-per-file 15 '
            container_cmd+='--require-real-complexity; fi'
            ;;
        compat)
            container_cmd='set -euo pipefail; ./tests/run_suite.sh --maintenance-only; '
            container_cmd+='./scripts/run_distro_compat_smoke.sh'
            ;;
        e2e)
            container_cmd='set -euo pipefail; REAL_DEPS=1 ./scripts/run_e2e.sh'
            ;;
        full)
            container_cmd='set -euo pipefail; ./tests/run_suite.sh --maintenance-only; '
            container_cmd+='./scripts/run_distro_compat_smoke.sh; REAL_DEPS=1 ./scripts/run_e2e.sh'
            ;;
        *)
            echo "Unknown mode: $mode" >&2
            return 1
            ;;
    esac

    echo "=== Running $mode on $image ==="
    # Host must mark scripts +x before bind-mount (container USER may not own checkout).
    rpi_ensure_scripts_executable "$REPO_ROOT"
    # Bind-mount current sources so CI/local edits are tested without stale COPY layers.
    # Run as host UID/GID so writes into the mount work on GitHub Actions (runner ≠ image default 1000).
    "$DOCKER_BIN" run --rm \
        --name "rpi-matrix-${slug}-${MATRIX_RUN_ID}" \
        --user "${host_uid}:${host_gid}" \
        --security-opt seccomp=unconfined \
        --cap-add SYS_PTRACE \
        -e TEST_MODE=true \
        -e USER=pi \
        -e HOME=/home/pi \
        -v "$REPO_ROOT:/home/pi" \
        -v "$REPO_ROOT/reports:/home/pi/reports:rw" \
        -w /home/pi \
        "$tag" \
        bash -lc "$container_cmd" 2>&1 | tee "$log"
}

run_coverage_gate() {
    local slug tag dockerfile gate_cmd host_uid host_gid
    slug=$(image_slug_from_ref "$COVERAGE_DISTRO")
    tag=$(test_image_tag_for_slug "$slug")
    dockerfile="$REPO_ROOT/$(dockerfile_for_distro "$COVERAGE_DISTRO")"
    host_uid="$(id -u)"
    host_gid="$(id -g)"
    mkdir -p "$REPO_ROOT/coverage"
    chmod 777 "$REPO_ROOT/coverage" || true

    docker_build_with_cache "$dockerfile" "$tag" "$REPO_ROOT" "$DOCKER_BUILD_CACHE_DIR" "$slug"

    # Host must mark scripts +x before bind-mount (container USER may not own checkout).
    rpi_ensure_scripts_executable "$REPO_ROOT"

    gate_cmd='set -euo pipefail; ./tests/run_suite.sh; '
    gate_cmd+='python3 tests/transform_coverage.py coverage/cobertura.xml '
    gate_cmd+='--fail-under 90 --fail-under-per-file 90 '
    gate_cmd+='--max-complexity-overall 15 --max-complexity-per-file 15 '
    gate_cmd+='--require-real-complexity'

    "$DOCKER_BIN" run --rm \
        --user "${host_uid}:${host_gid}" \
        --security-opt seccomp=unconfined \
        --cap-add SYS_PTRACE \
        -e COVERAGE=1 \
        -e COVERAGE_OUTPUT=/home/pi/coverage \
        -e USER=pi \
        -e HOME=/home/pi \
        -v "$REPO_ROOT:/home/pi" \
        -v "$REPO_ROOT/coverage:/home/pi/coverage" \
        -w /home/pi \
        "$tag" \
        bash -lc "$gate_cmd" \
        2>&1 | tee "$REPO_ROOT/reports/distro-logs/coverage-gate.log"
    return "${PIPESTATUS[0]}"
}

if [ "$RUN_COVERAGE_GATE" -eq 1 ]; then
    run_coverage_gate
    status=$?
    CLEANUP_RUNNING=1
    exit "$status"
fi

targets=("${DISTROS[@]}")
if [ "${#SELECTED_DISTROS[@]}" -gt 0 ]; then
    targets=("${SELECTED_DISTROS[@]}")
fi

mode="full"
if [ "$COMPAT_ONLY" -eq 1 ]; then
    mode="compat"
elif [ "$E2E_ONLY" -eq 1 ]; then
    mode="e2e"
fi

failures=0
if [ "$PARALLEL" -eq 1 ] && [ "${#targets[@]}" -gt 1 ]; then
    for image in "${targets[@]}"; do
        run_in_distro "$image" "$mode" &
        ACTIVE_PIDS+=("$!")
    done
    for pid in "${ACTIVE_PIDS[@]}"; do
        if ! wait "$pid"; then
            failures=$((failures + 1))
        fi
    done
else
    for image in "${targets[@]}"; do
        if ! run_in_distro "$image" "$mode"; then
            failures=$((failures + 1))
        fi
    done
fi

CLEANUP_RUNNING=1
if [ "$failures" -gt 0 ]; then
    echo "$failures distro lane(s) failed." >&2
    exit 1
fi
echo "All requested distro lanes passed."
