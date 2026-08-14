#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mapfile -t shell_files < <(git -C "$ROOT_DIR" ls-files "*.sh")

if [[ ${#shell_files[@]} -eq 0 ]]; then
    echo "No shell files found to format."
    exit 0
fi

if ! command -v shfmt > /dev/null 2>&1; then
    echo "shfmt is required (install with: apt install shfmt)."
    exit 1
fi

shfmt -w -i 4 -ci -sr "${shell_files[@]}"
echo "Formatting complete."
