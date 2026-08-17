#!/usr/bin/env bash
set -euo pipefail

STRICT_MODE="${STRICT_MODE:-false}"
MAX_LINE_LENGTH="${MAX_LINE_LENGTH:-140}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

warn() {
    echo "[lint][warn] $*"
}

fail() {
    echo "[lint][error] $*"
    return 1
}

run_or_warn() {
    local description="$1"
    shift

    if "$@"; then
        echo "[lint][ok] ${description}"
    elif [[ "$STRICT_MODE" == "true" ]]; then
        fail "${description}"
    else
        warn "${description}"
    fi
}

run_check() {
    local description="$1"
    shift

    if "$@"; then
        echo "[lint][ok] ${description}"
    elif [[ "$STRICT_MODE" == "true" ]]; then
        fail "${description} failed"
    else
        warn "${description} failed"
    fi
}

collect_files() {
    local pattern="$1"
    git -C "$ROOT_DIR" ls-files "$pattern"
}

check_line_length() {
    local file="$1"

    awk -v max_len="$MAX_LINE_LENGTH" '
        length($0) > max_len {
            printf("%s:%d exceeds %d characters\n", FILENAME, NR, max_len)
            failed=1
        }
        END { exit failed }
    ' "$file"
}

echo "--- Running lint and format checks ---"

mapfile -t shell_files < <(collect_files "*.sh")
mapfile -t yaml_files < <(
    collect_files "*.yml"
    collect_files "*.yaml"
)
mapfile -t markdown_files < <(collect_files "*.md")
mapfile -t workflow_files < <(
    collect_files ".github/workflows/*.yml"
    collect_files ".github/workflows/*.yaml"
)
mapfile -t docker_files < <(collect_files "Dockerfile*")

if [[ ${#shell_files[@]} -eq 0 ]]; then
    warn "No shell files found to lint."
else
    if command -v shellcheck > /dev/null 2>&1; then
        run_check "shellcheck" shellcheck -x -P SCRIPTDIR "${shell_files[@]}"
    else
        run_or_warn "shellcheck is required (install with: apt install shellcheck)" false
    fi

    if command -v shfmt > /dev/null 2>&1; then
        # -d checks formatting without writing; -sr simplifies shell constructs.
        run_check "shfmt" shfmt -d -i 4 -ci -sr "${shell_files[@]}"
    else
        run_or_warn "shfmt is required (install with: apt install shfmt)" false
    fi

    bash_n_failed=false
    for file in "${shell_files[@]}"; do
        if ! bash -n "$ROOT_DIR/$file"; then
            bash_n_failed=true
        fi
    done

    if [[ "$bash_n_failed" == "true" ]]; then
        run_or_warn "bash -n failed" false
    else
        echo "[lint][ok] bash -n"
    fi

    shell_len_failed=false
    for file in "${shell_files[@]}"; do
        if ! check_line_length "$ROOT_DIR/$file"; then
            shell_len_failed=true
        fi
    done

    if [[ "$shell_len_failed" == "true" ]]; then
        run_or_warn "shell line length <= ${MAX_LINE_LENGTH}" false
    else
        echo "[lint][ok] shell line length <= ${MAX_LINE_LENGTH}"
    fi
fi

if [[ ${#yaml_files[@]} -gt 0 ]]; then
    if command -v yamllint > /dev/null 2>&1; then
        run_check "yamllint" yamllint -c "$ROOT_DIR/.yamllint.yml" "${yaml_files[@]}"
    else
        run_or_warn "yamllint is required (install with: apt install yamllint)" false
    fi
fi

if [[ ${#workflow_files[@]} -gt 0 ]]; then
    if command -v actionlint > /dev/null 2>&1; then
        run_check "actionlint" actionlint -color "${workflow_files[@]}"
    elif command -v docker > /dev/null 2>&1; then
        run_check "actionlint (docker)" docker run --rm -v "$ROOT_DIR":/repo -w /repo rhysd/actionlint:latest -color
    else
        run_or_warn "actionlint or docker is required for GitHub workflow linting" false
    fi
fi

if [[ ${#docker_files[@]} -gt 0 ]]; then
    if command -v hadolint > /dev/null 2>&1; then
        run_check "hadolint" hadolint "${docker_files[@]}"
    elif command -v docker > /dev/null 2>&1; then
        run_check "hadolint (docker)" docker run --rm -v "$ROOT_DIR":/work -w /work hadolint/hadolint hadolint "${docker_files[@]}"
    else
        run_or_warn "hadolint or docker is required for Dockerfile linting" false
    fi

    docker_len_failed=false
    for file in "${docker_files[@]}"; do
        if ! check_line_length "$ROOT_DIR/$file"; then
            docker_len_failed=true
        fi
    done

    if [[ "$docker_len_failed" == "true" ]]; then
        run_or_warn "dockerfile line length <= ${MAX_LINE_LENGTH}" false
    else
        echo "[lint][ok] dockerfile line length <= ${MAX_LINE_LENGTH}"
    fi
fi

if [[ ${#markdown_files[@]} -gt 0 ]]; then
    if command -v mdformat > /dev/null 2>&1; then
        run_check "mdformat --check" mdformat --check "${markdown_files[@]}"
    else
        run_or_warn "mdformat is required for markdown linting (pip install mdformat)" false
    fi
fi

echo "[lint][done] Lint checks completed."
