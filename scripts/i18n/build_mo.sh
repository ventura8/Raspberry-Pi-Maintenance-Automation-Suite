#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PO_DIR="$REPO_ROOT/po"
DOMAIN="pi-maintenance-suite"
OUTPUT_ROOT="${1:-$REPO_ROOT/locale}"

command -v msgfmt > /dev/null 2>&1 || {
    printf 'Missing required gettext tool: msgfmt\n' >&2
    exit 1
}

python3 "$SCRIPT_DIR/check_catalog_quality.py"
while IFS= read -r language; do
    [ -n "$language" ] || continue
    target_dir="$OUTPUT_ROOT/$language/LC_MESSAGES"
    mkdir -p "$target_dir"
    msgfmt --check --check-format \
        --output-file="$target_dir/$DOMAIN.mo" "$PO_DIR/$language.po"
done < "$PO_DIR/SUPPORTED_LANGUAGES"

# Whisper uses jw while modern libc locales generally use jv.
jv_dir="$OUTPUT_ROOT/jv/LC_MESSAGES"
mkdir -p "$jv_dir"
cp "$OUTPUT_ROOT/jw/LC_MESSAGES/$DOMAIN.mo" "$jv_dir/$DOMAIN.mo"

printf 'Built catalogs under %s\n' "$OUTPUT_ROOT"
