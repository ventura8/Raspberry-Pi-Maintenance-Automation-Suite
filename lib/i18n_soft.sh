#!/usr/bin/env bash
# Soft gettext stubs used when lib/i18n.sh is not loaded yet.
# Real implementations in lib/i18n.sh replace these after source.
# shellcheck shell=bash

if declare -F _pi_gettext > /dev/null 2>&1; then
    return 0
fi

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
