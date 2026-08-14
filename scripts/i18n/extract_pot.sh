#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
POT_PATH="$REPO_ROOT/po/pi-maintenance-suite.pot"
DOMAIN="pi-maintenance-suite"

_require_tool() {
    command -v "$1" > /dev/null 2>&1 || {
        printf 'Missing required gettext tool: %s\n' "$1" >&2
        return 1
    }
}

_collect_sources() {
    mapfile -t SHELL_SOURCES < <(
        cd "$REPO_ROOT"
        {
            find lib -type f -name '*.sh' -print
            find scripts -maxdepth 1 -type f -name '*.sh' -print
            printf '%s\n' install.sh uninstall.sh
        } | sort -u
    )
}

_normalize_pot() {
    local pot_file="$1"
    python3 - "$pot_file" << 'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = [
    '"POT-Creation-Date: 1970-01-01 00:00+0000\\n"'
    if line.startswith('"POT-Creation-Date:')
    else line
    for line in text.splitlines()
    if not line.startswith('"X-Generator:')
]
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

_extract_catalog() {
    local output_path="$1" temp_dir shell_pot
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN
    shell_pot="$temp_dir/shell.pot"

    xgettext --force-po --language=Shell --from-code=UTF-8 --add-comments=TRANSLATORS: \
        --directory="$REPO_ROOT" \
        --keyword= \
        --keyword=_pi_gettext:1 --keyword=_pi_gettextf:1 \
        --keyword=_pi_echo:1 --keyword=_pi_echof:1 \
        --keyword=_pi_pgettext:1c,2 --keyword=_pi_ngettext:1,2 \
        --flag=_pi_gettextf:1:sh-format --flag=_pi_echof:1:sh-format \
        --flag=_pi_ngettext:1:sh-format \
        --flag=_pi_ngettext:2:sh-format --package-name="$DOMAIN" \
        --msgid-bugs-address="https://github.com/ventura8/Raspberry-Pi-Maintenance-Automation-Suite/issues" \
        --output="$shell_pot" "${SHELL_SOURCES[@]}"

    msgcat --use-first --sort-output --output-file="$output_path" "$shell_pot"
    _normalize_pot "$output_path"
    trap - RETURN
    rm -rf "$temp_dir"
}

_git_in_repo() {
    git -C "$REPO_ROOT" -c "safe.directory=$REPO_ROOT" "$@"
}

_require_tracked_catalog() {
    if ! command -v git > /dev/null 2>&1; then
        printf 'Missing required tool: git (needed to verify catalog is tracked).\n' >&2
        return 1
    fi
    if ! _git_in_repo rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        printf 'Catalog check requires a git work tree so the template can be verified as tracked.\n' >&2
        return 1
    fi
    if ! _git_in_repo ls-files --error-unmatch \
        po/pi-maintenance-suite.pot > /dev/null 2>&1; then
        printf \
            'Catalog template is not tracked by git; commit po/pi-maintenance-suite.pot (see .gitignore ! exception).\n' \
            >&2
        return 1
    fi
}

_fail_catalog_msg() {
    printf '%s\n' "$1" >&2
    return 1
}

_compare_catalog_template() {
    local generated="$1"
    if [ ! -f "$POT_PATH" ]; then
        _fail_catalog_msg \
            'Catalog template missing; run scripts/i18n/extract_pot.sh and commit it.'
        return 1
    fi
    if ! cmp --silent "$generated" "$POT_PATH"; then
        _fail_catalog_msg 'Catalog template is stale; run scripts/i18n/extract_pot.sh.'
        return 1
    fi
    printf 'Catalog template is current.\n'
}

_check_current_catalog() {
    local generated status=0
    generated=$(mktemp) || return 1
    if ! _require_tracked_catalog; then
        rm -f "$generated"
        return 1
    fi
    if ! _extract_catalog "$generated"; then
        rm -f "$generated"
        return 1
    fi
    _compare_catalog_template "$generated" || status=$?
    rm -f "$generated"
    return "$status"
}

main() {
    local mode="${1:-}"
    _require_tool xgettext
    _require_tool msgcat
    _collect_sources
    if [ "$mode" = "--check" ]; then
        _check_current_catalog
        return $?
    fi
    if [ -n "$mode" ]; then
        printf 'Usage: %s [--check]\n' "$0" >&2
        return 2
    fi
    _extract_catalog "$POT_PATH"
    printf 'Updated %s\n' "$POT_PATH"
}

main "$@"
