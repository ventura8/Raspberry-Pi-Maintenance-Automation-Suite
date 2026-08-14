#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/docker-utils.sh
source "$REPO_ROOT/scripts/docker-utils.sh"

DOCKER_BIN="${DOCKER_BIN:-docker}"
DOCKER_IMAGE="${DOCKER_LINT_IMAGE:-rpi-maintenance-lint:trixie}"
DOCKERFILE_PATH="${DOCKER_LINT_DOCKERFILE:-$REPO_ROOT/docker/images/lint/debian-trixie.Dockerfile}"
DOCKER_BUILD_CACHE_DIR="${DOCKER_BUILD_CACHE_DIR:-$REPO_ROOT/.cache/docker-buildx}"
LOG_DIR="$REPO_ROOT/reports/distro-logs"
mkdir -p "$LOG_DIR"

if ! command -v "$DOCKER_BIN" > /dev/null 2>&1; then
    echo "Docker is not installed or not on PATH." >&2
    exit 1
fi

docker_build_with_cache \
    "$DOCKERFILE_PATH" \
    "$DOCKER_IMAGE" \
    "$REPO_ROOT" \
    "$DOCKER_BUILD_CACHE_DIR" \
    "lint-debian-trixie" 2>&1 | tee "$LOG_DIR/lint-build.log"

"$DOCKER_BIN" run --rm \
    -v "$REPO_ROOT:/workspace:rw" \
    -w /workspace \
    "$DOCKER_IMAGE" \
    bash -lc 'git config --global --add safe.directory /workspace; STRICT_MODE=true ./tests/lint.sh' 2>&1 | tee "$LOG_DIR/lint-docker.log"
