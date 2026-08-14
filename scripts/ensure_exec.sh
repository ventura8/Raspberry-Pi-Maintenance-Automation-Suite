#!/usr/bin/env bash
# Shared executable prep for local + GitHub Actions Docker bind-mounts.
# Source this file; do not execute as a standalone pipeline stage.
#
# On Actions, container USER pi often differs from the checkout owner, so chmod
# on the bind-mounted tree can fail with EPERM. Host orchestrators must chmod
# first; in-container callers fall back to asserting files are already +x.

rpi_collect_exec_scripts() {
    local root="${1:-.}"
    local -a files=()
    local f

    shopt -s nullglob
    for f in \
        "$root"/install.sh \
        "$root"/uninstall.sh \
        "$root"/scripts/*.sh \
        "$root"/scripts/coverage/*.sh \
        "$root"/tests/*.sh \
        "$root"/lib/*.sh; do
        if [[ -f "$f" ]]; then
            files+=("$f")
        fi
    done
    shopt -u nullglob

    if ((${#files[@]} == 0)); then
        echo "ERROR: no suite scripts found under ${root} to ensure executable" >&2
        return 1
    fi
    printf '%s\n' "${files[@]}"
}

rpi_ensure_scripts_executable() {
    local root="${1:-.}"
    local -a files=()
    local f
    local list

    list=$(rpi_collect_exec_scripts "$root") || return 1
    mapfile -t files <<< "$list"
    if ((${#files[@]} == 0)); then
        echo "ERROR: no suite scripts found under ${root} to ensure executable" >&2
        return 1
    fi

    if chmod +x "${files[@]}" 2> /dev/null; then
        return 0
    fi

    # Bind-mount owned by a different UID (typical on GitHub Actions): chmod may
    # fail even when the host already marked scripts executable.
    for f in "${files[@]}"; do
        if [[ ! -x "$f" ]]; then
            echo "ERROR: $f is not executable (chmod failed; host must mark scripts +x before bind-mount)" >&2
            return 1
        fi
    done
    return 0
}
