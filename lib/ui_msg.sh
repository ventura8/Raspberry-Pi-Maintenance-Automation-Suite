#!/bin/bash
# English-only UI message helpers (no gettext / no catalogs).
# Sequential %s substitution matches the former soft-stub contract (not printf formats).

_pi_gettext() {
    printf '%s' "$1"
}

_pi_gettextf() {
    local format="$1" argument prefix suffix
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

_pi_echo() {
    printf '%s\n' "$1"
}

_pi_echof() {
    local format
    format=$(_pi_gettextf "$@")
    printf '%s\n' "$format"
}
