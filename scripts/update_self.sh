#!/bin/bash
# Description: Checks for updates to the Raspberry Pi Maintenance Suite and applies them.

# --- Configuration ---
INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"
VERSION_FILE="$INSTALL_DIR/.version"
GITHUB_USER="ventura8"
REPO_NAME="Raspberry-Pi-Maintenance-Automation-Suite"
# API URL for fetching the latest release
API_URL="https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/releases/latest"

# Ensure logging
LOG_FILE="${LOG_FILE:-$HOME/maintenance.log}"
SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
MSMTP_CONF="${MSMTP_CONF:-/etc/msmtprc}"

_RPI_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_RPI_HERE/lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/lib/mail_send.sh"
    # shellcheck source=../lib/ui_msg.sh
    source "$_RPI_HERE/lib/ui_msg.sh"
elif [ -f "$_RPI_HERE/../lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/../lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/../lib/mail_send.sh"
    # shellcheck source=../lib/ui_msg.sh
    source "$_RPI_HERE/../lib/ui_msg.sh"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_notification() {
    local subject="$1"
    local body="$2"
    local recipient
    local body_file

    recipient=$(mail_read_recipient_from_config 2> /dev/null || true)
    if [ -z "$recipient" ]; then
        log "$(_pi_gettext "No mail recipient configured, skipping email notification.")"
        return 0
    fi
    body_file=$(mktemp)
    printf '%s\n' "$body" > "$body_file"
    if send_mail "$recipient" "$subject" "Pi Maintenance" "$body_file"; then
        log "Email notification delivered to $recipient."
    else
        log "Failed to deliver email notification to $recipient."
    fi
    rm -f "$body_file"
}

exit_with_failure() {
    local reason="$1"
    log "Error: $reason"
    send_notification "$(_pi_gettext "Pi Maintenance Update Failed")" "$(_pi_gettextf "The auto-update failed. Reason: %s" "$reason")"
    exit 1
}

# Stage tagged installer + VERSION + lib/ into dest (mktemp tree). Lib fetch is best-effort.
stage_release_tree() {
    local raw_url="$1"
    local dest="$2"
    local lib_file tmp
    mkdir -p "$dest/lib"
    if ! curl -fsSL "$raw_url/install.sh" -o "$dest/install.sh"; then
        return 1
    fi
    chmod +x "$dest/install.sh"
    if ! curl -fsSL "$raw_url/VERSION" -o "$dest/VERSION"; then
        return 2
    fi
    for lib_file in os_pkg.sh mail_send.sh ui_msg.sh; do
        tmp=$(mktemp "$dest/lib/.lib.XXXXXX") || continue
        if curl -fsSL "$raw_url/lib/$lib_file" -o "$tmp"; then
            mv -f "$tmp" "$dest/lib/$lib_file"
        else
            rm -f "$tmp"
        fi
    done
    return 0
}

main() {
    log "$(_pi_gettext "Checking for updates...")"

    if ! command -v curl &> /dev/null; then
        # Can't email if we can't do anything, but try logging
        log "$(_pi_gettext "Error: curl is required but not installed.")"
        exit 1
    fi

    # Fetch remote Release JSON
    if ! REMOTE_JSON=$(curl -s -L --max-time 10 "$API_URL"); then
        exit_with_failure "$(_pi_gettext "Failed to contact GitHub API.")"
    fi

    # Extract tag_name using grep/sed (avoiding jq dependency)
    # Looking for "tag_name": "v1.0.0"
    REMOTE_TAG=$(echo "$REMOTE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -z "$REMOTE_TAG" ]; then
        # Fallback: Check if it's a rate limit or other error in JSON
        log "Debug Response: $REMOTE_JSON"
        exit_with_failure "$(_pi_gettext "Could not parse remote tag from GitHub response.")"
    fi

    log "Remote Version: $REMOTE_TAG"

    # Get Local Version
    LOCAL_TAG=""
    if [ -f "$VERSION_FILE" ]; then
        LOCAL_TAG=$(cat "$VERSION_FILE")
    fi
    log "Local Version:  ${LOCAL_TAG:-Unknown}"

    # Compare Versions
    if [ "$REMOTE_TAG" == "$LOCAL_TAG" ]; then
        log "$(_pi_gettext "System is up to date.")"
        send_notification "$(_pi_gettext "Pi Maintenance: System Up to Date")" \
            "$(_pi_gettextf "The system is running the latest version: %s." "$LOCAL_TAG")"
        exit 0
    else
        log "Update available! ($LOCAL_TAG -> $REMOTE_TAG)"

        # Tagged raw tree (install.sh + VERSION + lib/) — not $INSTALL_DIR/../install.sh.
        RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$REMOTE_TAG"

        local stage_dir stage_rc staged_version staged_tag
        stage_dir=$(mktemp -d) || stage_dir=""
        if [ -z "$stage_dir" ] || [ ! -d "$stage_dir" ]; then
            exit_with_failure "Failed to create staging directory."
        fi

        log "Downloading installer from $REMOTE_TAG..."
        stage_release_tree "$RAW_URL" "$stage_dir"
        stage_rc=$?
        if [ "$stage_rc" -eq 1 ]; then
            rm -rf "$stage_dir"
            exit_with_failure "Failed to download install.sh from $RAW_URL."
        fi
        if [ "$stage_rc" -eq 2 ]; then
            rm -rf "$stage_dir"
            exit_with_failure "Failed to download VERSION from $RAW_URL."
        fi
        staged_version="$stage_dir/VERSION"
        staged_tag=$(tr -d '[:space:]' < "$staged_version" 2> /dev/null || true)
        if [ -z "$staged_tag" ] || [ "$staged_tag" != "$REMOTE_TAG" ]; then
            rm -rf "$stage_dir"
            exit_with_failure "Staged VERSION ($staged_tag) does not match release tag ($REMOTE_TAG)."
        fi

        if [ "$TEST_MODE" == "true" ]; then
            log "TEST_MODE: Skipping actual execution of install.sh"
            # Prefer staged VERSION contents when present (must match release tag).
            if [ -f "$staged_version" ]; then
                tr -d '[:space:]' < "$staged_version" > "$VERSION_FILE"
                printf '\n' >> "$VERSION_FILE"
            else
                echo "$REMOTE_TAG" > "$VERSION_FILE"
            fi
            rm -rf "$stage_dir"
            # Send Success Email for test verification
            send_notification "Pi Maintenance Suite Updated" "The suite has been updated to version $REMOTE_TAG."
            exit 0
        fi

        log "Running installer to update scripts..."

        # Execute installer non-interactively via the --update flag.
        # --update causes install.sh to run check_dependencies + download_scripts and exit,
        # with no interactive prompts. Do NOT pipe fake input here: piping makes bash
        # treat stdin as non-terminal, which causes install.sh to attempt a /dev/tty
        # redirect that does not exist in a cron environment.
        export RAW_URL
        export INSTALL_DIR
        if ! bash "$stage_dir/install.sh" --update; then
            rm -rf "$stage_dir"
            exit_with_failure "Installer execution failed."
        fi
        rm -rf "$stage_dir"

        # Ensure .version matches the release tag (install.sh also writes from VERSION).
        echo "$REMOTE_TAG" > "$VERSION_FILE"
        log "Update complete. Version updated to $REMOTE_TAG"

        send_notification "Pi Maintenance Suite Updated" "The suite has been updated to version $REMOTE_TAG."
    fi
}

main "$@"
