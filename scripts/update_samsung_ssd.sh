#!/bin/bash
# Description: Checks for and applies firmware updates for Samsung SSDs.
# Primary method: fwupdmgr (LVFS). Fallback: Dynamic scraping of Samsung's official page.
# It runs the update automatically and schedules a reboot if required.
# Compatible with: Raspberry Pi OS, Xubuntu, and other Debian-based systems.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
SAMSUNG_VENDOR="Samsung"
REPORT_SEPARATOR="======================================================="
SAMSUNG_FIRMWARE_PAGE="https://semiconductor.samsung.com/consumer-storage/support/tools/"
# ---------------------

# Prevent ANSI color codes
export TERM=dumb
export NO_COLOR=1

_RPI_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_RPI_HERE/lib/os_pkg.sh" ]]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/lib/mail_send.sh"
    # shellcheck source=../lib/ui_msg.sh
    source "$_RPI_HERE/lib/ui_msg.sh"
elif [[ -f "$_RPI_HERE/../lib/os_pkg.sh" ]]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/../lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/../lib/mail_send.sh"
    # shellcheck source=../lib/ui_msg.sh
    source "$_RPI_HERE/../lib/ui_msg.sh"
fi

# Check Architecture
CURRENT_ARCH=$(uname -m)
if [[ "$TEST_MODE" = "true" ]] && [[ -n "$MOCK_ARCH" ]]; then
    CURRENT_ARCH="$MOCK_ARCH"
fi

if [[ "$CURRENT_ARCH" != "x86_64" ]] && [[ "$CURRENT_ARCH" != "aarch64" ]]; then
    _pi_echo "Error: This script supports 64-bit systems only."
    exit 1
fi

# --- Dependency Management ---
check_and_install_dependencies() {
    _pi_echo "--- Checking Dependencies ---"
    local missing_logical=()
    local logical_deps=("fwupd" "nvme-cli" "curl" "cpio" "p7zip" "file" "gzip")
    local logical

    for logical in "${logical_deps[@]}"; do
        if ! logical_is_installed "$logical"; then
            missing_logical+=("$logical")
        fi
    done

    if [[ ${#missing_logical[@]} -gt 0 ]]; then
        echo "Installing missing dependencies: ${missing_logical[*]}"
        if pkg_install "${missing_logical[@]}"; then
            _pi_echo "Dependencies installed successfully."
        else
            _pi_echo "Warning: Some dependencies may have failed to install."
            return 1
        fi
    else
        _pi_echo "All dependencies are installed."
    fi
    echo ""
}

# Function to dynamically find firmware URL for a given model
find_firmware_url() {
    local model="$1"
    local page_html

    _pi_echo "Fetching Samsung firmware page..."
    page_html=$(curl -sL --proto '=https' --proto-redir '=https' \
        "$SAMSUNG_FIRMWARE_PAGE" 2> /dev/null)

    if [[ -z "$page_html" ]]; then
        _pi_echo "Failed to fetch Samsung firmware page."
        return 1
    fi

    # Normalize model name for matching (e.g., "Samsung SSD 990 PRO 2TB" -> "990 PRO")
    local model_pattern=""

    if echo "$model" | /usr/bin/grep -qi "9100 PRO"; then
        model_pattern="9100.PRO"
    elif echo "$model" | /usr/bin/grep -qi "990 PRO"; then
        model_pattern="990.PRO"
    elif echo "$model" | /usr/bin/grep -qi "990 EVO Plus"; then
        model_pattern="990.EVO.Plus"
    elif echo "$model" | /usr/bin/grep -qi "990 EVO"; then
        model_pattern="990.EVO"
    elif echo "$model" | /usr/bin/grep -qi "980 PRO"; then
        model_pattern="980.PRO"
    elif echo "$model" | /usr/bin/grep -qi "980"; then
        model_pattern="980[^0-9]"
    elif echo "$model" | /usr/bin/grep -qi "970 EVO Plus"; then
        model_pattern="970.EVO.Plus"
    elif echo "$model" | /usr/bin/grep -qi "970 EVO"; then
        model_pattern="970.EVO"
    elif echo "$model" | /usr/bin/grep -qi "970 PRO"; then
        model_pattern="970.PRO"
    elif echo "$model" | /usr/bin/grep -qi "960 PRO"; then
        model_pattern="960.PRO"
    elif echo "$model" | /usr/bin/grep -qi "960 EVO"; then
        model_pattern="960.EVO"
    elif echo "$model" | /usr/bin/grep -qi "950 PRO"; then
        model_pattern="950.PRO"
    else
        echo "Model '$model' not recognized for dynamic lookup."
        return 1
    fi

    # Extract ISO URL from page HTML
    local raw_match
    raw_match=$(echo "$page_html" |
        /usr/bin/grep -iE "href=\"[^\"]+${model_pattern}[^\"]*\"" |
        /usr/bin/grep -i "\.iso" |
        head -n1)
    ISO_URL=$(echo "$raw_match" | /usr/bin/grep -oE "https://[^\"]+\.iso")

    if [[ -z "$ISO_URL" ]]; then
        ISO_URL=$(echo "$page_html" |
            /usr/bin/grep -oE "https://semiconductor\.samsung\.com/resources/software-resources/Samsung_SSD_[^\"]+\.iso" |
            /usr/bin/grep -i "$model_pattern" |
            head -n1)
    fi

    if [[ -z "$ISO_URL" ]]; then
        echo "Could not find firmware URL for model pattern: $model_pattern"
        return 1
    fi

    # Extract version from URL
    local fw_version
    fw_version=$(echo "$ISO_URL" | /usr/bin/grep -oE '[A-Z0-9]{8}\.iso$' | sed 's/\.iso//')

    echo "Found firmware: $ISO_URL"
    echo "Firmware version: $fw_version"

    # Export for caller
    FOUND_ISO_URL="$ISO_URL"
    FOUND_FW_VERSION="$fw_version"
    return 0
}

extract_and_run_fumagician() {
    local iso_path="$1"

    if [[ "$TEST_MODE" == "true" ]]; then
        echo "Firmware updated successfully (MOCK)"
        return 0
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local mount_dir="$work_dir/iso_mount"
    local extract_dir="$work_dir/extracted"

    mkdir -p "$mount_dir" "$extract_dir"

    _pi_echo "Mounting ISO..."
    if ! sudo mount -o loop "$iso_path" "$mount_dir" 2> /dev/null; then
        _pi_echo "Failed to mount ISO."
        rm -rf "$work_dir"
        return 1
    fi

    # Find initrd file
    local initrd_file=""
    if [[ -f "$mount_dir/initrd" ]]; then
        initrd_file="$mount_dir/initrd"
    elif [[ -f "$mount_dir/boot/initrd" ]]; then
        initrd_file="$mount_dir/boot/initrd"
    fi

    if [[ -z "$initrd_file" ]]; then
        _pi_echo "Could not find initrd in ISO."
        sudo umount "$mount_dir"
        rm -rf "$work_dir"
        return 1
    fi

    _pi_echo "Extracting initrd..."
    cd "$extract_dir" || return 1

    if file "$initrd_file" | /usr/bin/grep -q "gzip"; then
        gzip -dc "$initrd_file" 2> /dev/null | cpio -idm --no-absolute-filenames 2> /dev/null
    elif file "$initrd_file" | /usr/bin/grep -q "7-zip"; then
        if command -v 7z > /dev/null 2>&1; then
            7z x "$initrd_file" -o"$extract_dir" > /dev/null 2>&1
        else
            _pi_echo "7z required but not installed."
            sudo umount "$mount_dir"
            rm -rf "$work_dir"
            return 1
        fi
    else
        cpio -idm --no-absolute-filenames < "$initrd_file" 2> /dev/null
    fi

    # Find fumagician
    local fumagician=""
    fumagician=$(find "$extract_dir" -name "fumagician" -type f 2> /dev/null | head -n1)

    if [[ -z "$fumagician" ]]; then
        _pi_echo "Could not find fumagician in initrd."
        sudo umount "$mount_dir"
        rm -rf "$work_dir"
        return 1
    fi

    echo "Found fumagician at: $fumagician"
    chmod +x "$fumagician"

    local fuma_dir
    fuma_dir=$(dirname "$fumagician")

    _pi_echo "Running firmware update..."
    cd "$fuma_dir" || return 1

    local update_result
    update_result=$(timeout 900 sudo "$fumagician" --auto < /dev/null 2>&1 || timeout 900 sudo "$fumagician" -y < /dev/null 2>&1)
    echo "$update_result"

    # Cleanup
    cd / || true
    sudo umount "$mount_dir" 2> /dev/null
    rm -rf "$work_dir"

    if echo "$update_result" | /usr/bin/grep -qiE "success|updated|complete|reboot"; then
        return 0
    else
        return 1
    fi
}

update_via_official_iso() {
    local nvme_dev="$1"
    local model="$2"

    if ! find_firmware_url "$model"; then
        _pi_echo "Manual update: https://semiconductor.samsung.com/consumer-storage/support/tools/"
        return 1
    fi

    local current_fw
    current_fw=$(sudo nvme id-ctrl "$nvme_dev" 2> /dev/null | /usr/bin/grep "fr " | awk '{print $3}' | tr -d '[:space:]')
    echo "Current Firmware: $current_fw"
    echo "Latest Firmware:  $FOUND_FW_VERSION"

    if [[ "$current_fw" = "$FOUND_FW_VERSION" ]]; then
        _pi_echo "Firmware is already up to date."
        return 1
    fi

    _pi_echo "New firmware available! Downloading..."
    local iso_path
    iso_path=$(mktemp /tmp/samsung_fw.XXXXXX.iso) || return 1
    chmod 600 "$iso_path"

    if ! curl -L -s -o "$iso_path" "$FOUND_ISO_URL"; then
        _pi_echo "Failed to download firmware ISO."
        rm -f "$iso_path"
        return 1
    fi

    if [[ ! -s "$iso_path" ]]; then
        _pi_echo "Downloaded file is empty."
        rm -f "$iso_path"
        return 1
    fi

    echo "ISO downloaded: $(du -h "$iso_path" | cut -f1)"

    if extract_and_run_fumagician "$iso_path"; then
        _pi_echo "Firmware update applied successfully."
        rm -f "$iso_path"
        return 0
    else
        _pi_echo "Firmware update via fumagician failed."
        rm -f "$iso_path"
        return 1
    fi
}

main() {
    LOG_FILE=$(mktemp)
    HOSTNAME=$(hostname)
    SUBJECT_LINE="Samsung SSD Firmware Update Report for $HOSTNAME - $(date)"
    REBOOT_NEEDED=false

    {
        _pi_echo "$REPORT_SEPARATOR"
        echo "   SAMSUNG SSD FIRMWARE UPDATE LOG - $(date)"
        _pi_echo "$REPORT_SEPARATOR"
        echo ""

        check_and_install_dependencies

        if command -v fwupdmgr > /dev/null 2>&1; then
            _pi_echo "--- Checking for Samsung SSDs via fwupd ---"

            local fwupd_devices
            if [[ "$TEST_MODE" = "true" ]] && [[ -n "$MOCK_FWUPD_DEVICES" ]]; then
                fwupd_devices="$MOCK_FWUPD_DEVICES"
            else
                fwupd_devices=$(sudo fwupdmgr get-devices 2> /dev/null)
            fi

            if echo "$fwupd_devices" | /usr/bin/grep -qi "$SAMSUNG_VENDOR"; then
                _pi_echo "Samsung SSD detected by fwupd."

                _pi_echo "--- Refreshing Metadata ---"
                sudo fwupdmgr refresh > /dev/null 2>&1

                _pi_echo "--- Checking for Updates ---"
                if sudo fwupdmgr get-updates 2> /dev/null | /usr/bin/grep -qi "$SAMSUNG_VENDOR"; then
                    _pi_echo "Updates available. Installing..."

                    # --no-reboot-check is the real fwupd flag (1.x and 2.x); "--no-reboot" is rejected by 2.x.
                    FWUPD_UPDATE_RC=0
                    UPDATE_OUTPUT=$(sudo fwupdmgr update -y --no-reboot-check 2>&1) || FWUPD_UPDATE_RC=$?
                    echo "$UPDATE_OUTPUT"

                    if [[ "$FWUPD_UPDATE_RC" -ne 0 ]]; then
                        _pi_echof "ERROR: 'fwupdmgr update' failed (exit code %s). Firmware was NOT updated." "$FWUPD_UPDATE_RC"
                    elif echo "$UPDATE_OUTPUT" |
                        /usr/bin/grep -qiE "Restarting|Must be restarted|Reboot required|Successfully installed"; then
                        REBOOT_NEEDED=true
                    fi
                else
                    _pi_echo "No updates available via LVFS."
                fi
            else
                _pi_echo "No Samsung SSDs detected by fwupd."
                echo ""
                _pi_echo "--- Fallback: Samsung Official ISO Update ---"

                if command -v nvme > /dev/null 2>&1; then
                    local nvme_list_output
                    nvme_list_output=$(sudo nvme list 2> /dev/null)

                    nvme_dev=$(echo "$nvme_list_output" | /usr/bin/grep -i "$SAMSUNG_VENDOR" | head -n1 | awk '{print $1}')
                    model=$(echo "$nvme_list_output" |
                        /usr/bin/grep -i "$SAMSUNG_VENDOR" |
                        head -n1 |
                        awk '{$1=$2=""; print $0}' |
                        sed 's/^[ \t]*//')

                    if [[ -n "$nvme_dev" ]]; then
                        echo "Found: $model on $nvme_dev"

                        if update_via_official_iso "$nvme_dev" "$model"; then
                            REBOOT_NEEDED=true
                        fi
                    else
                        _pi_echo "No Samsung SSDs detected by nvme-cli."
                    fi
                else
                    _pi_echo "nvme-cli is not installed and could not be installed automatically."
                fi
            fi
        else
            _pi_echo "Error: fwupdmgr (fwupd) is not installed."
        fi

        echo ""
        if [[ "$REBOOT_NEEDED" = true ]]; then
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "A firmware update was applied. A reboot is required."
            _pi_echo "The system will reboot shortly after this report is sent."
        else
            _pi_echo "--- REBOOT STATUS ---"
            _pi_echo "No firmware update was applied or no reboot is required."
        fi

        _pi_echo "$REPORT_SEPARATOR"
        echo "   Maintenance Finished at $(date)"
        _pi_echo "$REPORT_SEPARATOR"
    } > "$LOG_FILE"

    # Display log to stdout for cron capture/debugging
    cat "$LOG_FILE"

    if ! declare -F send_mail > /dev/null 2>&1; then
        echo "ERROR: mail helper (lib/mail_send.sh) is not available" >&2
        return 1
    fi
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "Samsung SSD Maintenance" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    if [[ "$REBOOT_NEEDED" = true ]]; then
        rm "$LOG_FILE"
        sudo shutdown -r +1 "Samsung SSD Firmware update requires a reboot. Rebooting in 1 minute."
    else
        rm "$LOG_FILE"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
