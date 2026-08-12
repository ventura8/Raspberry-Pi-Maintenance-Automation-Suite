#!/usr/bin/env bash
# GNU gettext helpers for user-facing Raspberry Pi Maintenance Suite text.
# shellcheck shell=bash

PI_TEXTDOMAIN="pi-maintenance-suite"

_pi_i18n_repo_root() {
    if [ -n "${PI_I18N_REPO_ROOT_OVERRIDE:-}" ]; then
        printf '%s\n' "$PI_I18N_REPO_ROOT_OVERRIDE"
        return 0
    fi
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    (cd "$lib_dir/.." && pwd)
}

_pi_resolve_textdomain_dir() {
    local repo_root candidate install_locale
    if [ -n "${TEXTDOMAINDIR:-}" ]; then
        printf '%s\n' "$TEXTDOMAINDIR"
        return 0
    fi
    install_locale="${INSTALL_DIR:-$HOME/pi-scripts}/locale"
    repo_root=$(_pi_i18n_repo_root 2> /dev/null || true)
    [ "${PI_I18N_SKIP_REPO_LOCALE:-0}" = "1" ] && repo_root=""
    system_locale="/usr/share/locale"
    [ "${PI_I18N_SKIP_SYSTEM_LOCALE:-0}" = "1" ] && system_locale=""
    for candidate in \
        "${repo_root:+${repo_root}/locale}" \
        "$install_locale" \
        "${PREFIX:-}/usr/local/share/locale" \
        "$system_locale"; do
        [ -n "$candidate" ] || continue
        [ -d "$candidate" ] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    printf '%s\n' "${PREFIX:-}/usr/local/share/locale"
}

_pi_normalize_ui_language() {
    local value="${1:-}"
    value="${value%%:*}"
    value="${value%%.*}"
    value="${value%%@*}"
    value="${value%%_*}"
    value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    case "$value" in
        jv) value="jw" ;;
    esac
    case "$value" in
        [a-z][a-z] | [a-z][a-z][a-z]) printf '%s\n' "$value" ;;
        *) return 1 ;;
    esac
}

_pi_test_ui_language() {
    [ "${TEST_MODE:-}" = "true" ] || [ "${TEST_MODE:-0}" = "1" ] || return 1
    [ -n "${PI_UI_LANG:-}" ] || return 1
    printf '%s\n' "$PI_UI_LANG"
}

_pi_resolve_ui_locale() {
    local value
    if value=$(_pi_test_ui_language 2> /dev/null); then
        printf '%s\n' "$value"
        return 0
    fi
    value="${LC_MESSAGES:-${LANG:-${LANGUAGE:-en}}}"
    printf '%s\n' "$value"
}

_pi_gettext_env() {
    local locale language locale_for_lookup lang_upper
    locale=$(_pi_resolve_ui_locale)
    language=$(_pi_normalize_ui_language "$locale" 2> /dev/null || true)
    [ -n "$language" ] || language="en"
    locale_for_lookup="$locale"
    case "$locale_for_lookup" in
        *.* | *@* | *_*) ;;
        *)
            lang_upper=$(printf '%s' "$language" | tr '[:lower:]' '[:upper:]')
            locale_for_lookup="${language}_${lang_upper}.UTF-8"
            ;;
    esac
    printf '%s\n%s\n' "$language" "$locale_for_lookup"
}

# GNU gettext ignores LANGUAGE when the process locale is C/POSIX (incl. C.UTF-8).
# Force a non-C LANG for catalog lookup; override with PI_GETTEXT_BASE_LANG if needed.
# Do not set LC_MESSAGES to the UI locale here — an ungenerated locale (e.g. ro_RO.UTF-8)
# can make the process fall back to C and ignore LANGUAGE again.
_pi_gettext_lookup_env() {
    local language="$1" textdomain_dir="$2"
    local base_lang="${PI_GETTEXT_BASE_LANG:-en_US.UTF-8}"
    shift 2
    env -u LC_ALL \
        LANG="$base_lang" \
        LC_MESSAGES="$base_lang" \
        LANGUAGE="$language" \
        TEXTDOMAIN="$PI_TEXTDOMAIN" \
        TEXTDOMAINDIR="$textdomain_dir" \
        "$@"
}

_pi_gettext() {
    local msgid="$1" language translated textdomain_dir
    command -v gettext > /dev/null 2>&1 || {
        printf '%s' "$msgid"
        return 0
    }
    {
        read -r language
        read -r _ui_locale
    } < <(_pi_gettext_env)
    textdomain_dir=$(_pi_resolve_textdomain_dir)
    translated=$(
        _pi_gettext_lookup_env "$language" "$textdomain_dir" \
            gettext "$msgid" 2> /dev/null
    ) || translated="$msgid"
    printf '%s' "${translated:-$msgid}"
}

_pi_gettextf() {
    local format argument prefix suffix
    format=$(_pi_gettext "$1")
    shift
    for argument in "$@"; do
        case "$format" in
            *%s*)
                prefix=${format%%\%s*}
                suffix=${format#*%s}
                format="${prefix}${argument}${suffix}"
                ;;
        esac
    done
    printf '%s' "$format"
}

_pi_pgettext() {
    local context="$1" msgid="$2" key translated
    key="${context}"$'\004'"${msgid}"
    translated=$(_pi_gettext "$key")
    [ "$translated" = "$key" ] && translated="$msgid"
    printf '%s' "$translated"
}

_pi_ngettext() {
    local singular="$1" plural="$2" count="$3"
    local language translated textdomain_dir
    if ! command -v ngettext > /dev/null 2>&1; then
        _pi_source_plural "$singular" "$plural" "$count"
        return 0
    fi
    {
        read -r language
        read -r _ui_locale
    } < <(_pi_gettext_env)
    textdomain_dir=$(_pi_resolve_textdomain_dir)
    if ! translated=$(
        _pi_gettext_lookup_env "$language" "$textdomain_dir" \
            ngettext "$singular" "$plural" "$count" 2> /dev/null
    ); then
        translated=""
    fi
    if [ -z "$translated" ]; then
        translated=$(_pi_source_plural "$singular" "$plural" "$count")
    fi
    printf '%s' "$translated"
}

_pi_source_plural() {
    local singular="$1" plural="$2" count="$3"
    if [ "$count" -eq 1 ]; then
        printf '%s' "$singular"
        return 0
    fi
    printf '%s' "$plural"
}

# Print a translated line (avoids shellcheck SC2005 on echo "$(gettext ...)").
_pi_echo() {
    printf '%s\n' "$(_pi_gettext "$1")"
}

_pi_echof() {
    printf '%s\n' "$(_pi_gettextf "$@")"
}
