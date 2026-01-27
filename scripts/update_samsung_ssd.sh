#!/bin/bash
# Description: Checks for and applies firmware updates for Samsung SSDs.
# Primary method: fwupdmgr (LVFS). Fallback: Dynamic scraping of Samsung's official page.
# It runs the update automatically and schedules a reboot if required.
# Compatible with: Raspberry Pi OS, Xubuntu, and other Debian-based systems.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
SAMSUNG_FIRMWARE_PAGE="https://semiconductor.samsung.com/consumer-storage/support/tools/"
# ---------------------

# Prevent ANSI color codes
export TERM=dumb
export NO_COLOR=1
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Check Architecture
CURRENT_ARCH=$(uname -m)
if [ "$TEST_MODE" = "true" ] && [ -n "$MOCK_ARCH" ]; then
    CURRENT_ARCH="$MOCK_ARCH"
fi

if [ "$CURRENT_ARCH" != "x86_64" ] && [ "$CURRENT_ARCH" != "aarch64" ]; then
    echo "Error: This script supports 64-bit systems only."
    exit 1
fi

# --- Dependency Management ---
check_and_install_dependencies() {
    echo "--- Checking Dependencies ---"
    local MISSING_DEPS=()
    
    # Required packages and their commands
    # Format: package_name:command_to_check
    local DEPS=(
        "fwupd:fwupdmgr"
        "nvme-cli:nvme"
        "curl:curl"
        "cpio:cpio"
        "p7zip-full:7z"
        "file:file"
        "gzip:gzip"
    )
    
    for dep in "${DEPS[@]}"; do
        local pkg="${dep%%:*}"
        local cmd="${dep##*:}"
        
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_DEPS+=("$pkg")
        fi
    done
    
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${MISSING_DEPS[*]}"
        sudo apt-get update >/dev/null 2>&1
        # shellcheck disable=SC2068
        if sudo apt-get install -y ${MISSING_DEPS[@]} >/dev/null 2>&1; then
            echo "Dependencies installed successfully."
        else
            echo "Warning: Some dependencies may have failed to install."
            return 1
        fi
    else
        echo "All dependencies are installed."
    fi
    echo ""
}

# Function to dynamically find firmware URL for a given model
find_firmware_url() {
    local MODEL="$1"
    local PAGE_HTML
    
    echo "Fetching Samsung firmware page..."
    PAGE_HTML=$(curl -sL "$SAMSUNG_FIRMWARE_PAGE" 2>/dev/null)
    
    if [ -z "$PAGE_HTML" ]; then
        echo "Failed to fetch Samsung firmware page."
        return 1
    fi
    
    # Normalize model name for matching (e.g., "Samsung SSD 990 PRO 2TB" -> "990 PRO")
    local MODEL_PATTERN=""
    
    if echo "$MODEL" | /usr/bin/grep -qi "9100 PRO"; then
        MODEL_PATTERN="9100.PRO"
    elif echo "$MODEL" | /usr/bin/grep -qi "990 PRO"; then
        MODEL_PATTERN="990.PRO"
    elif echo "$MODEL" | /usr/bin/grep -qi "990 EVO Plus"; then
        MODEL_PATTERN="990.EVO.Plus"
    elif echo "$MODEL" | /usr/bin/grep -qi "990 EVO"; then
        MODEL_PATTERN="990.EVO"
    elif echo "$MODEL" | /usr/bin/grep -qi "980 PRO"; then
        MODEL_PATTERN="980.PRO"
    elif echo "$MODEL" | /usr/bin/grep -qi "980"; then
        MODEL_PATTERN="980[^0-9]"
    elif echo "$MODEL" | /usr/bin/grep -qi "970 EVO Plus"; then
        MODEL_PATTERN="970.EVO.Plus"
    elif echo "$MODEL" | /usr/bin/grep -qi "970 EVO"; then
        MODEL_PATTERN="970.EVO"
    elif echo "$MODEL" | /usr/bin/grep -qi "970 PRO"; then
        MODEL_PATTERN="970.PRO"
    elif echo "$MODEL" | /usr/bin/grep -qi "960 PRO"; then
        MODEL_PATTERN="960.PRO"
    elif echo "$MODEL" | /usr/bin/grep -qi "960 EVO"; then
        MODEL_PATTERN="960.EVO"
    elif echo "$MODEL" | /usr/bin/grep -qi "950 PRO"; then
        MODEL_PATTERN="950.PRO"
    else
        echo "Model '$MODEL' not recognized for dynamic lookup."
        return 1
    fi
    
    # Extract ISO URL from page HTML
    local RAW_MATCH
    RAW_MATCH=$(echo "$PAGE_HTML" | /usr/bin/grep -iE "href=\"[^\"]+${MODEL_PATTERN}[^\"]*\"" | /usr/bin/grep -i "\.iso" | head -n1)
    ISO_URL=$(echo "$RAW_MATCH" | /usr/bin/grep -oE "https://[^\"]+\.iso")
    
    if [ -z "$ISO_URL" ]; then
        ISO_URL=$(echo "$PAGE_HTML" | /usr/bin/grep -oE "https://semiconductor\.samsung\.com/resources/software-resources/Samsung_SSD_[^\"]+\.iso" | /usr/bin/grep -i "$MODEL_PATTERN" | head -n1)
    fi
    
    if [ -z "$ISO_URL" ]; then
        echo "Could not find firmware URL for model pattern: $MODEL_PATTERN"
        return 1
    fi
    
    # Extract version from URL
    local FW_VERSION
    FW_VERSION=$(echo "$ISO_URL" | /usr/bin/grep -oE '[A-Z0-9]{8}\.iso$' | sed 's/\.iso//')
    
    echo "Found firmware: $ISO_URL"
    echo "Firmware version: $FW_VERSION"
    
    # Export for caller
    FOUND_ISO_URL="$ISO_URL"
    FOUND_FW_VERSION="$FW_VERSION"
    return 0
}

extract_and_run_fumagician() {
    local ISO_PATH="$1"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "Firmware updated successfully (MOCK)"
        return 0
    fi

    local WORK_DIR
    WORK_DIR=$(mktemp -d)
    local MOUNT_DIR="$WORK_DIR/iso_mount"
    local EXTRACT_DIR="$WORK_DIR/extracted"
    
    mkdir -p "$MOUNT_DIR" "$EXTRACT_DIR"
    
    echo "Mounting ISO..."
    if ! sudo mount -o loop "$ISO_PATH" "$MOUNT_DIR" 2>/dev/null; then
        echo "Failed to mount ISO."
        rm -rf "$WORK_DIR"
        return 1
    fi
    
    # Find initrd file
    local INITRD_FILE=""
    if [ -f "$MOUNT_DIR/initrd" ]; then
        INITRD_FILE="$MOUNT_DIR/initrd"
    elif [ -f "$MOUNT_DIR/boot/initrd" ]; then
        INITRD_FILE="$MOUNT_DIR/boot/initrd"
    fi
    
    if [ -z "$INITRD_FILE" ]; then
        echo "Could not find initrd in ISO."
        sudo umount "$MOUNT_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi
    
    echo "Extracting initrd..."
    cd "$EXTRACT_DIR" || return 1
    
    if file "$INITRD_FILE" | /usr/bin/grep -q "gzip"; then
        gzip -dc "$INITRD_FILE" 2>/dev/null | cpio -idm --no-absolute-filenames 2>/dev/null
    elif file "$INITRD_FILE" | /usr/bin/grep -q "7-zip"; then
        if command -v 7z >/dev/null 2>&1; then
            7z x "$INITRD_FILE" -o"$EXTRACT_DIR" >/dev/null 2>&1
        else
            echo "7z required but not installed."
            sudo umount "$MOUNT_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi
    else
        cpio -idm --no-absolute-filenames < "$INITRD_FILE" 2>/dev/null
    fi
    
    # Find fumagician
    local FUMAGICIAN=""
    FUMAGICIAN=$(find "$EXTRACT_DIR" -name "fumagician" -type f 2>/dev/null | head -n1)
    
    if [ -z "$FUMAGICIAN" ]; then
        echo "Could not find fumagician in initrd."
        sudo umount "$MOUNT_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi
    
    echo "Found fumagician at: $FUMAGICIAN"
    chmod +x "$FUMAGICIAN"
    
    local FUMA_DIR
    FUMA_DIR=$(dirname "$FUMAGICIAN")
    
    echo "Running firmware update..."
    cd "$FUMA_DIR" || return 1
    
    local UPDATE_RESULT
    UPDATE_RESULT=$(sudo "$FUMAGICIAN" --auto 2>&1 || sudo "$FUMAGICIAN" -y 2>&1 || sudo "$FUMAGICIAN" 2>&1)
    echo "$UPDATE_RESULT"
    
    # Cleanup
    cd / || true
    sudo umount "$MOUNT_DIR" 2>/dev/null
    rm -rf "$WORK_DIR"
    
    if echo "$UPDATE_RESULT" | /usr/bin/grep -qiE "success|updated|complete|reboot"; then
        return 0
    else
        return 1
    fi
}

update_via_official_iso() {
    local NVME_DEV="$1"
    local MODEL="$2"
    
    if ! find_firmware_url "$MODEL"; then
        echo "Manual update: https://semiconductor.samsung.com/consumer-storage/support/tools/"
        return 1
    fi
    
    local CURRENT_FW
    CURRENT_FW=$(sudo nvme id-ctrl "$NVME_DEV" 2>/dev/null | /usr/bin/grep "fr " | awk '{print $3}' | tr -d '[:space:]')
    echo "Current Firmware: $CURRENT_FW"
    echo "Latest Firmware:  $FOUND_FW_VERSION"
    
    if [ "$CURRENT_FW" = "$FOUND_FW_VERSION" ]; then
        echo "Firmware is already up to date."
        return 1
    fi
    
    echo "New firmware available! Downloading..."
    local ISO_PATH="/tmp/samsung_fw.iso"
    
    if ! curl -L -s -o "$ISO_PATH" "$FOUND_ISO_URL"; then
        echo "Failed to download firmware ISO."
        return 1
    fi
    
    if [ ! -s "$ISO_PATH" ]; then
        echo "Downloaded file is empty."
        rm -f "$ISO_PATH"
        return 1
    fi
    
    echo "ISO downloaded: $(du -h "$ISO_PATH" | cut -f1)"
    
    if extract_and_run_fumagician "$ISO_PATH"; then
        echo "Firmware update applied successfully."
        rm -f "$ISO_PATH"
        return 0
    else
        echo "Firmware update via fumagician failed."
        rm -f "$ISO_PATH"
        return 1
    fi
}

main() {
    LOG_FILE=$(mktemp)
    HOSTNAME=$(hostname)
    SUBJECT_LINE="Samsung SSD Firmware Update Report for $HOSTNAME - $(date)"
    REBOOT_NEEDED=false

    {
        echo "======================================================="
        echo "   SAMSUNG SSD FIRMWARE UPDATE LOG - $(date)"
        echo "======================================================="
        echo ""
        
        check_and_install_dependencies

        if command -v fwupdmgr >/dev/null 2>&1; then
            echo "--- Checking for Samsung SSDs via fwupd ---"
            
            local FWUPD_DEVICES
            if [ "$TEST_MODE" = "true" ] && [ -n "$MOCK_FWUPD_DEVICES" ]; then
                FWUPD_DEVICES="$MOCK_FWUPD_DEVICES"
            else
                FWUPD_DEVICES=$(sudo fwupdmgr get-devices 2>/dev/null)
            fi
            
            if echo "$FWUPD_DEVICES" | /usr/bin/grep -qi "Samsung"; then
                echo "Samsung SSD detected by fwupd."
                
                echo "--- Refreshing Metadata ---"
                sudo fwupdmgr refresh >/dev/null 2>&1
                
                echo "--- Checking for Updates ---"
                if sudo fwupdmgr get-updates 2>/dev/null | /usr/bin/grep -qi "Samsung"; then
                    echo "Updates available. Installing..."
                    
                    UPDATE_OUTPUT=$(sudo fwupdmgr update -y --no-reboot 2>&1)
                    echo "$UPDATE_OUTPUT"
                    
                    if echo "$UPDATE_OUTPUT" | /usr/bin/grep -qiE "Restarting|Must be restarted|Reboot required|Successfully installed"; then
                        REBOOT_NEEDED=true
                    fi
                else
                    echo "No updates available via LVFS."
                fi
            else
                echo "No Samsung SSDs detected by fwupd."
                echo ""
                echo "--- Fallback: Samsung Official ISO Update ---"
                
                if command -v nvme >/dev/null 2>&1; then
                    local NVME_LIST_OUTPUT
                    NVME_LIST_OUTPUT=$(sudo nvme list 2>/dev/null)
                    
                    NVME_DEV=$(echo "$NVME_LIST_OUTPUT" | /usr/bin/grep -i "Samsung" | head -n1 | awk '{print $1}')
                    MODEL=$(echo "$NVME_LIST_OUTPUT" | /usr/bin/grep -i "Samsung" | head -n1 | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//')
                    
                    if [ -n "$NVME_DEV" ]; then
                        echo "Found: $MODEL on $NVME_DEV"
                        
                        if update_via_official_iso "$NVME_DEV" "$MODEL"; then
                            REBOOT_NEEDED=true
                        fi
                    else
                        echo "No Samsung SSDs detected by nvme-cli."
                    fi
                else
                    echo "nvme-cli is not installed and could not be installed automatically."
                fi
            fi
        else
            echo "Error: fwupdmgr (fwupd) is not installed."
        fi

        echo ""
        if [ "$REBOOT_NEEDED" = true ]; then
            echo "--- REBOOT STATUS ---"
            echo "A firmware update was applied. A reboot is required."
            echo "The system will reboot shortly after this report is sent."
        else
            echo "--- REBOOT STATUS ---"
            echo "No firmware update was applied or no reboot is required."
        fi

        echo "======================================================="
        echo "   Maintenance Finished at $(date)"
        echo "======================================================="
    } > "$LOG_FILE"
    
    # Display log to stdout for cron capture/debugging
    cat "$LOG_FILE"

    if command -v ssmtp >/dev/null 2>&1; then
        ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Samsung SSD Maintenance" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF
    fi

    if [ "$REBOOT_NEEDED" = true ]; then
        rm "$LOG_FILE"
        sudo shutdown -r +1 "Samsung SSD Firmware update requires a reboot. Rebooting in 1 minute."
    else
        rm "$LOG_FILE"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
