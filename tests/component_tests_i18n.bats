#!/usr/bin/env bats

setup() {
    export TEST_MODE=true
    export PI_UI_LANG=en
    unset TEXTDOMAINDIR || true
    unset INSTALL_DIR || true
    unset PREFIX || true
    # shellcheck source=../lib/i18n.sh
    source ./lib/i18n.sh
}

@test "i18n: English msgid passthrough without catalogs" {
    run _pi_gettext "Checking dependencies..."
    [ "$status" -eq 0 ]
    [ "$output" = "Checking dependencies..." ]
}

@test "i18n: PI_UI_LANG override under TEST_MODE" {
    export TEST_MODE=true
    export PI_UI_LANG=ro
    run _pi_normalize_ui_language "$(_pi_resolve_ui_locale)"
    [ "$status" -eq 0 ]
    [ "$output" = "ro" ]
}

@test "i18n: TEST_MODE=1 also enables PI_UI_LANG" {
    export TEST_MODE=1
    export PI_UI_LANG=de
    run _pi_resolve_ui_locale
    [ "$status" -eq 0 ]
    [ "$output" = "de" ]
}

@test "i18n: session locale used when test override absent" {
    unset PI_UI_LANG || true
    export TEST_MODE=false
    export LC_MESSAGES=fr_FR.UTF-8
    unset LANG LANGUAGE || true
    run _pi_resolve_ui_locale
    [ "$status" -eq 0 ]
    [ "$output" = "fr_FR.UTF-8" ]
}

@test "i18n: gettextf substitutes sequential %s" {
    run _pi_gettextf "Daily @ %s:%s" "03" "00"
    [ "$status" -eq 0 ]
    [ "$output" = "Daily @ 03:00" ]
}

@test "i18n: gettextf ignores args without %s" {
    run _pi_gettextf "No placeholders" "extra"
    [ "$status" -eq 0 ]
    [ "$output" = "No placeholders" ]
}

@test "i18n: translated canary with built locale fixture" {
    local tmp domain="pi-maintenance-suite" out
    command -v msgfmt > /dev/null 2>&1 || skip "msgfmt missing"
    command -v gettext > /dev/null 2>&1 || skip "gettext missing"
    [ -f ./po/ro.po ] || skip "po/ro.po missing"

    tmp=$(mktemp -d)
    mkdir -p "$tmp/ro/LC_MESSAGES"
    msgfmt --check --check-format -o "$tmp/ro/LC_MESSAGES/$domain.mo" ./po/ro.po

    export TEXTDOMAINDIR="$tmp"
    export TEST_MODE=true
    export PI_UI_LANG=ro
    # Even if the host session is C.UTF-8, lookup must still translate.
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
    out=$(_pi_gettext "Checking dependencies...")
    rm -rf "$tmp"
    [ -n "$out" ]
    [ "$out" != "Checking dependencies..." ]
}

@test "i18n: ngettext English fallback without ngettext binary path" {
    run _pi_source_plural "one task" "%s tasks" 1
    [ "$output" = "one task" ]
    run _pi_source_plural "one task" "%s tasks" 3
    [ "$output" = "%s tasks" ]
}

@test "i18n: pgettext falls back to msgid when context missing" {
    run _pi_pgettext "button" "Continue"
    [ "$status" -eq 0 ]
    [ "$output" = "Continue" ]
}

@test "i18n: ngettext uses ngettext binary when available" {
    command -v ngettext > /dev/null 2>&1 || skip "ngettext missing"
    run _pi_ngettext "one file" "%s files" 1
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    run _pi_ngettext "one file" "%s files" 4
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "i18n: echo helpers print newline" {
    run _pi_echo "Checking dependencies..."
    [ "$status" -eq 0 ]
    [ "$output" = "Checking dependencies..." ]
    run _pi_echof "Daily @ %s:%s" "01" "02"
    [ "$status" -eq 0 ]
    [ "$output" = "Daily @ 01:02" ]
}

@test "i18n: normalize rejects garbage language tags" {
    run _pi_normalize_ui_language "!!!"
    [ "$status" -ne 0 ]
}

@test "i18n: jv normalizes to Whisper jw catalog code" {
    run _pi_normalize_ui_language "jv_ID.UTF-8"
    [ "$status" -eq 0 ]
    [ "$output" = "jw" ]
}

@test "i18n: three-letter language codes accepted" {
    run _pi_normalize_ui_language "haw"
    [ "$status" -eq 0 ]
    [ "$output" = "haw" ]
}

@test "i18n: resolve textdomain dir respects TEXTDOMAINDIR" {
    export TEXTDOMAINDIR="/tmp/pi-i18n-fixture-domain"
    run _pi_resolve_textdomain_dir
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/pi-i18n-fixture-domain" ]
}

@test "i18n: resolve textdomain dir finds repo locale when present" {
    unset TEXTDOMAINDIR || true
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/locale"
    export PI_I18N_REPO_ROOT_OVERRIDE="$tmp"
    export INSTALL_DIR="/tmp/pi-i18n-missing-install-$$"
    run _pi_resolve_textdomain_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp/locale" ]
    rm -rf "$tmp"
    unset PI_I18N_REPO_ROOT_OVERRIDE
}

@test "i18n: resolve textdomain dir uses INSTALL_DIR locale" {
    unset TEXTDOMAINDIR || true
    unset PI_I18N_REPO_ROOT_OVERRIDE || true
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/locale"
    export INSTALL_DIR="$tmp"
    export PI_I18N_SKIP_REPO_LOCALE=1
    run _pi_resolve_textdomain_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp/locale" ]
    rm -rf "$tmp"
    unset PI_I18N_SKIP_REPO_LOCALE
}

@test "i18n: resolve textdomain dir falls back to PREFIX share locale" {
    unset TEXTDOMAINDIR || true
    unset INSTALL_DIR || true
    unset PI_I18N_REPO_ROOT_OVERRIDE || true
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/usr/local/share/locale"
    export PREFIX="$tmp"
    export HOME="$tmp/home"
    mkdir -p "$HOME"
    export PI_I18N_SKIP_REPO_LOCALE=1
    export PI_I18N_SKIP_SYSTEM_LOCALE=1
    run _pi_resolve_textdomain_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp/usr/local/share/locale" ]
    rm -rf "$tmp"
    unset PI_I18N_SKIP_REPO_LOCALE PI_I18N_SKIP_SYSTEM_LOCALE PREFIX
}

@test "i18n: gettext_env expands bare language to LANG_LANG.UTF-8" {
    export TEST_MODE=true
    export PI_UI_LANG=es
    run _pi_gettext_env
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n'"es_ES.UTF-8" ]] || [[ "$output" == *"es_ES.UTF-8"* ]]
}

@test "i18n: gettext_env keeps locale with underscore" {
    unset PI_UI_LANG || true
    export TEST_MODE=false
    export LC_MESSAGES=pt_BR.UTF-8
    run _pi_gettext_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"pt"* ]]
}

@test "i18n: gettext falls back when gettext binary hidden" {
    local tmpbin
    tmpbin=$(mktemp -d)
    # Empty PATH hides gettext
    PATH="$tmpbin" run _pi_gettext "Checking dependencies..."
    [ "$status" -eq 0 ]
    [ "$output" = "Checking dependencies..." ]
    rm -rf "$tmpbin"
}

@test "i18n: ngettext falls back when ngettext binary hidden" {
    local tmpbin
    tmpbin=$(mktemp -d)
    PATH="$tmpbin" run _pi_ngettext "one file" "%s files" 2
    [ "$status" -eq 0 ]
    [ "$output" = "%s files" ]
    rm -rf "$tmpbin"
}

@test "i18n: repo root helper returns parent of lib" {
    run _pi_i18n_repo_root
    [ "$status" -eq 0 ]
    [ -d "$output" ]
    [ -f "$output/lib/i18n.sh" ]
}

@test "i18n soft stubs: gettextf and echof without real i18n" {
    run bash -c '
        source ./lib/i18n_soft.sh
        printf "%s\n" "$(_pi_gettext "plain-msg")"
        printf "%s\n" "$(_pi_gettextf "Hello %s" "world")"
        _pi_echo "plain"
        _pi_echof "A %s B %s" "x" "y"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"plain-msg"* ]]
    [[ "$output" == *"Hello world"* ]]
    [[ "$output" == *"plain"* ]]
    [[ "$output" == *"A x B y"* ]]
}

@test "i18n soft stubs: no-op when real helpers already loaded" {
    run bash -c '
        source ./lib/i18n.sh
        source ./lib/i18n_soft.sh
        _pi_echo "still-real"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"still-real"* ]]
}

@test "i18n: install.sh inline stubs format %s when lib missing" {
    run bash -c '
        export PI_I18N_FORCE_INLINE_STUBS=1
        source ./install.sh
        _pi_echof "Version set to: %s" "v9.9.9"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version set to: v9.9.9"* ]]
}

@test "i18n: uninstall.sh inline stubs format %s when lib missing" {
    run bash -c '
        export PI_I18N_FORCE_INLINE_STUBS=1
        source ./uninstall.sh
        _pi_echof "Removed: %s" "cron"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed: cron"* ]]
}

@test "i18n: uninstall prefers INSTALL_DIR soft stubs over missing root lib" {
    run bash -c '
        tmp=$(mktemp -d)
        mkdir -p "$tmp/empty" "$tmp/install/lib"
        cp ./lib/i18n_soft.sh "$tmp/install/lib/"
        export PI_UNINSTALL_ROOT_OVERRIDE="$tmp/empty"
        export INSTALL_DIR="$tmp/install"
        unset PI_I18N_FORCE_INLINE_STUBS
        source ./uninstall.sh
        _pi_echof "Hello %s" "install-dir"
        rm -rf "$tmp"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hello install-dir"* ]]
}

@test "i18n: uninstall prefers INSTALL_DIR real i18n over root" {
    run bash -c '
        tmp=$(mktemp -d)
        mkdir -p "$tmp/empty" "$tmp/install/lib"
        cp ./lib/i18n.sh "$tmp/install/lib/"
        export PI_UNINSTALL_ROOT_OVERRIDE="$tmp/empty"
        export INSTALL_DIR="$tmp/install"
        export PI_I18N_FORCE_INLINE_STUBS=1
        # First force stubs, then clear and re-source path is awkward; source without force
        unset PI_I18N_FORCE_INLINE_STUBS
        # Soft missing under empty root and install; only real i18n in INSTALL_DIR.
        source ./uninstall.sh
        _pi_echo "Checking dependencies..."
        rm -rf "$tmp"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking dependencies..."* ]]
}

@test "i18n: resolve textdomain falls through when no dirs exist" {
    run bash -c '
        export HOME="/tmp/pi-i18n-missing-home-$$"
        export INSTALL_DIR="/tmp/pi-i18n-missing-install-$$"
        export PREFIX="/tmp/pi-i18n-missing-prefix-$$"
        export PI_I18N_SKIP_SYSTEM_LOCALE=1
        export PI_I18N_SKIP_REPO_LOCALE=1
        unset TEXTDOMAINDIR
        source ./lib/i18n.sh
        _pi_resolve_textdomain_dir
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"/usr/local/share/locale" ]]
}

@test "i18n: gettext empty translation falls back to msgid" {
    run bash -c '
        source ./lib/i18n.sh
        # Fake gettext that succeeds with empty stdout to hit fallback branch.
        tmpbin=$(mktemp -d)
        printf "%s\n" "#!/bin/bash" "exit 0" > "$tmpbin/gettext"
        chmod +x "$tmpbin/gettext"
        export PATH="$tmpbin:$PATH"
        export TEST_MODE=true PI_UI_LANG=ro
        out=$(_pi_gettext "Checking dependencies...")
        rm -rf "$tmpbin"
        printf "%s\n" "$out"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "Checking dependencies..." ]]
}

@test "i18n: ngettext failure falls back to source plural" {
    run bash -c '
        source ./lib/i18n.sh
        tmpbin=$(mktemp -d)
        printf "%s\n" "#!/bin/bash" "exit 1" > "$tmpbin/ngettext"
        chmod +x "$tmpbin/ngettext"
        export PATH="$tmpbin:$PATH"
        export TEST_MODE=true PI_UI_LANG=en
        out=$(_pi_ngettext "one file" "%s files" 4)
        rm -rf "$tmpbin"
        printf "%s\n" "$out"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "%s files" ]]
}
