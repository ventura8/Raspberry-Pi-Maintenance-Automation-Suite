#!/bin/bash
# Description: Checks for updates to the Raspberry Pi Maintenance Suite and applies them.
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- Configuration ---
INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"
VERSION_FILE="$INSTALL_DIR/.version"
GITHUB_USER="ventura8"
REPO_NAME="Raspberry-Pi-Maintenance-Automation-Suite"
# API URL for fetching the latest release
API_URL="https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/releases/latest"

# Source the install script to verify we can find it (for re-downloading)
INSTALL_SCRIPT="$INSTALL_DIR/../install.sh"
# If install.sh is not in parent (dev mode), try current dir
if [ ! -f "$INSTALL_SCRIPT" ]; then
    INSTALL_SCRIPT="./install.sh"
fi

# Ensure logging
LOG_FILE="${LOG_FILE:-$HOME/maintenance.log}"
SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_notification() {
    local subject="$1"
    local body="$2"
    
    if command -v ssmtp >/dev/null 2>&1; then
        RECIPIENT_EMAIL=$(grep "^root=" "$SSMTP_CONF" 2>/dev/null | cut -d= -f2)
        if [ -n "$RECIPIENT_EMAIL" ]; then
            log "Sending email to $RECIPIENT_EMAIL..."
            {
                echo "Subject: $subject"
                echo ""
                echo "$body"
            } | ssmtp "$RECIPIENT_EMAIL"
        fi
    else
        log "ssmtp not found, skipping email notification."
    fi
}

exit_with_failure() {
    local reason="$1"
    log "Error: $reason"
    send_notification "Pi Maintenance Update Failed" "The auto-update failed. Reason: $reason"
    exit 1
}

main() {
    log "Checking for updates..."

    if ! command -v curl &> /dev/null; then
        # Can't email if we can't do anything, but try logging
        log "Error: curl is required but not installed."
        exit 1
    fi

    # Fetch remote Release JSON
    if ! REMOTE_JSON=$(curl -s -L --max-time 10 "$API_URL"); then
        exit_with_failure "Failed to contact GitHub API."
    fi

    # Extract tag_name using grep/sed (avoiding jq dependency)
    # Looking for "tag_name": "v1.0.0"
    REMOTE_TAG=$(echo "$REMOTE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)

    if [ -z "$REMOTE_TAG" ]; then
        # Fallback: Check if it's a rate limit or other error in JSON
        log "Debug Response: $REMOTE_JSON"
        exit_with_failure "Could not parse remote tag from GitHub response."
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
        log "System is up to date."
        send_notification "Pi Maintenance: System Up to Date" "The system is running the latest version: $LOCAL_TAG."
        exit 0
    else
        log "Update available! ($LOCAL_TAG -> $REMOTE_TAG)"
        
        # Determine URL for install.sh based on the TAG
        # Construct raw URL: .../tag_name/install.sh? No, raw objects are usually by commit or branch.
        # But for releases, we can use the tag in the raw URL structure:
        # https://raw.githubusercontent.com/user/repo/TAG/install.sh
        RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$REMOTE_TAG"
        
        log "Downloading installer from $REMOTE_TAG..."
        if ! curl -sSL "$RAW_URL/install.sh" -o "$INSTALL_SCRIPT"; then
             exit_with_failure "Failed to download install.sh from $RAW_URL."
        fi
        chmod +x "$INSTALL_SCRIPT"
        
        if [ "$TEST_MODE" == "true" ]; then
            log "TEST_MODE: Skipping actual execution of install.sh"
            echo "$REMOTE_TAG" > "$VERSION_FILE"
            # Send Success Email for test verification
            send_notification "Pi Maintenance Suite Updated" "The suite has been updated to version $REMOTE_TAG."
            exit 0
        fi

        log "Running installer to update scripts..."
        
        # Execute installer non-interactively
        # We assume install.sh is robust. If it fails, we might not know unless we capture output.
        if ! (echo "4"; sleep 5; echo "0") | bash "$INSTALL_SCRIPT"; then
             exit_with_failure "Installer execution failed."
        fi
        
        # Update version file on success
        echo "$REMOTE_TAG" > "$VERSION_FILE"
        log "Update complete. Version updated to $REMOTE_TAG"
        
        send_notification "Pi Maintenance Suite Updated" "The suite has been updated to version $REMOTE_TAG."
    fi
}

main "$@"
