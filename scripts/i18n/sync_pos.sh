#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PO_DIR="$REPO_ROOT/po"
POT_PATH="$PO_DIR/pi-maintenance-suite.pot"

command -v msgmerge > /dev/null 2>&1 || {
    printf 'Missing required gettext tool: msgmerge\n' >&2
    exit 1
}

python3 "$SCRIPT_DIR/seed_whisper_languages.py"
while IFS= read -r language; do
    [ -n "$language" ] || continue
    msgmerge --update --backup=none --no-fuzzy-matching \
        "$PO_DIR/$language.po" "$POT_PATH"
done < "$PO_DIR/SUPPORTED_LANGUAGES"

printf 'Synchronized all catalogs with %s\n' "$POT_PATH"
