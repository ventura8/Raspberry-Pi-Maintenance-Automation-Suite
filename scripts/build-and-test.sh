#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/ensure_exec.sh
source "$REPO_ROOT/scripts/ensure_exec.sh"

MODE="full"
DISTRO_IMAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            MODE="full"
            shift
            ;;
        --lints-only)
            MODE="lint"
            shift
            ;;
        --coverage-only)
            MODE="coverage"
            shift
            ;;
        --compat-only)
            MODE="compat"
            shift
            ;;
        --e2e-only)
            MODE="e2e"
            shift
            ;;
        --distro)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --distro requires an image ref (e.g. debian:trixie)" >&2
                exit 1
            fi
            MODE="distro"
            DISTRO_IMAGE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

rpi_ensure_scripts_executable "$REPO_ROOT"

case "$MODE" in
    lint)
        ./scripts/lint-in-docker.sh
        ;;
    coverage)
        ./scripts/run_docker_matrix.sh --coverage-gate
        ;;
    compat)
        ./scripts/run_docker_matrix.sh --compat-only --parallel
        ;;
    e2e)
        ./scripts/run_docker_matrix.sh --e2e-only --parallel
        ;;
    distro)
        ./scripts/run_docker_matrix.sh --distro "$DISTRO_IMAGE" --serial
        ;;
    full)
        ./scripts/lint-in-docker.sh
        ./scripts/run_docker_matrix.sh --coverage-gate
        ./scripts/run_docker_matrix.sh --parallel
        ;;
esac
