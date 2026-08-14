#!/bin/bash
set -e

# Define mock directory (callers may set MOCK_DIR before sourcing for isolation)
export MOCK_DIR="${MOCK_DIR:-/tmp/mocks}"
mkdir -p "$MOCK_DIR"

# Add MOCK_DIR and system sbin to PATH
export PATH="$MOCK_DIR:/usr/sbin:$PATH"

echo "--- Setting up System Mocks in $MOCK_DIR ---"
export MOCK_FS="$MOCK_DIR/fs"
mkdir -p "$MOCK_FS/proc/device-tree"
echo "Raspberry Pi 5 Model B Rev 1.0" > "$MOCK_FS/proc/device-tree/model"
echo "Model : Raspberry Pi 5 Model B Rev 1.0" > "$MOCK_FS/proc/cpuinfo"

# 1. Smart Sudo Mock
cat << EOF > "$MOCK_DIR/sudo"
#!/bin/bash
MOCK_DIR="\${MOCK_DIR:-$MOCK_DIR}"
ORIG_ARGS=("\$@")
while [[ "\$1" == -* ]]; do
    if [[ "\$1" == "-u" ]]; then shift; shift; else shift; fi
done
CMD_NAME="\$1"
if [ -n "\$CMD_NAME" ] && [ -x "\$MOCK_DIR/\$CMD_NAME" ]; then
    export IS_MOCKED_SUDO=true
    shift 
    "\$MOCK_DIR/\$CMD_NAME" "\$@"
else
    /usr/bin/sudo env PATH="\$MOCK_DIR:\$PATH" MOCK_DIR="\$MOCK_DIR" "\${ORIG_ARGS[@]}"
fi
EOF
chmod +x "$MOCK_DIR/sudo"

# 2. Mock rpi-eeprom-update
/usr/bin/rm -f "$MOCK_DIR/rpi-eeprom-update"
cat << 'EOF' > "$MOCK_DIR/rpi-eeprom-update"
#!/bin/bash
echo "BOOTLOADER: update available"
echo "UPDATE SUCCESSFUL"
EOF
/usr/bin/chmod +x "$MOCK_DIR/rpi-eeprom-update"

# 3. Mock Docker
cat << 'EOF' > "$MOCK_DIR/docker"
#!/bin/bash
if [[ "$1" == "buildx" && "$2" == "version" ]]; then
    echo "github.com/docker/buildx v0.10.0"
    exit 0
fi
echo "[MOCK] docker $@"
EOF

# 4. Mock Shutdown
cat << 'EOF' > "$MOCK_DIR/shutdown"
#!/bin/bash
echo "[MOCK] shutdown scheduled: $@"
EOF

# Package-manager and real-binary mocks are skipped when REAL_DEPS=1 (e2e/compat smoke).
if [ "${REAL_DEPS:-0}" != "1" ]; then
    # 5. Mock Apt-Get / dnf / yum / pacman
    cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "[MOCK] apt-get $@"
if [[ "$*" == *"install"* ]]; then
    echo "Dependencies installed successfully."
fi
EOF

    cat << 'EOF' > "$MOCK_DIR/dnf"
#!/bin/bash
echo "[MOCK] dnf $@"
if [[ "$*" == *"install"* ]]; then
    echo "Dependencies installed successfully."
fi
EOF

    cat << 'EOF' > "$MOCK_DIR/yum"
#!/bin/bash
echo "[MOCK] yum $@"
if [[ "$*" == *"install"* ]]; then
    echo "Dependencies installed successfully."
fi
EOF

    cat << 'EOF' > "$MOCK_DIR/pacman"
#!/bin/bash
echo "[MOCK] pacman $@"
if [[ "$*" == *"-S"* ]]; then
    echo "Dependencies installed successfully."
fi
EOF

    # 6. Mock Crontab (Stateful)
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
_MD="\${MOCK_DIR:-$MOCK_DIR}"
if [ "\$IS_MOCKED_SUDO" == "true" ]; then CRON_FILE="\$_MD/root_cron"; else CRON_FILE="\$_MD/user_cron"; fi
touch "\$CRON_FILE"
if [[ "\$1" == "-l" ]]; then cat "\$CRON_FILE"; exit 0; fi
if [[ "\$1" == "-" ]]; then cat > "\${CRON_FILE}.tmp"; mv "\${CRON_FILE}.tmp" "\$CRON_FILE"; exit 0; fi
if [[ -f "\$1" ]]; then cp "\$1" "\$CRON_FILE"; exit 0; fi
EOF
    chmod +x "$MOCK_DIR/crontab"

    # 7. Mock Curl (with local file support and Samsung page simulation)
    cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
url=""
args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
  case "${args[$i]}" in
    -o|--output)
      i=$((i + 1))
      outfile="${args[$i]}"
      ;;
    -s|-sS|-sSL|-sL|-L|-f|-S|--silent|--show-error|--fail|--location) ;;
    --max-time|-m|--connect-timeout)
      i=$((i + 1))
      ;;
    -*)
      ;;
    *)
      if [ -z "$url" ]; then
        url="${args[$i]}"
      fi
      ;;
  esac
  i=$((i + 1))
done
if [[ "$url" == *"semiconductor.samsung.com"* ]]; then
    echo '<a href="https://download.semiconductor.samsung.com/970_EVO_Plus_2B2QEXM7.iso">970 EVO Plus</a><span>2B2QEXM7</span>'
    exit 0
fi
script_name=$(basename -- "$url")
if [[ -f "./scripts/$script_name" ]]; then SRC="./scripts/$script_name"
elif [[ -f "./lib/$script_name" ]]; then SRC="./lib/$script_name"
elif [[ -f "./$script_name" ]]; then SRC="./$script_name"
else SRC="/dev/null"; /usr/bin/touch "$SRC" 2>/dev/null || true; fi
if [[ -n "$outfile" ]]; then 
    if [ "$SRC" = "/dev/null" ]; then echo "MOCK DATA" > "$outfile"; else cp "$SRC" "$outfile"; fi
else cat "$SRC" 2>/dev/null || true; fi
EOF

    # 8. No-ops (chmod, chown, usermod)
    for cmd in chmod chown usermod; do
        echo "#!/bin/bash" > "$MOCK_DIR/$cmd"
        echo "exit 0" >> "$MOCK_DIR/$cmd"
    done

    # 9. Mock hostname, clear, tput
    echo '#!/bin/bash' > "$MOCK_DIR/hostname"
    echo 'echo "test-pi"' >> "$MOCK_DIR/hostname"
    echo '#!/bin/bash' > "$MOCK_DIR/clear"
    echo '#!/bin/bash' > "$MOCK_DIR/tput"
    chmod +x "$MOCK_DIR/clear" "$MOCK_DIR/tput"

    # 10. Mock ssmtp / msmtp
    echo '#!/bin/bash' > "$MOCK_DIR/ssmtp"
    echo 'cat' >> "$MOCK_DIR/ssmtp"
    echo '#!/bin/bash' > "$MOCK_DIR/msmtp"
    echo 'cat' >> "$MOCK_DIR/msmtp"

    # 11. Mock pip3
    echo '#!/bin/bash' > "$MOCK_DIR/pip3"
    echo 'exit 0' >> "$MOCK_DIR/pip3"
else
    echo "--- REAL_DEPS=1: keeping real package managers and mailer binaries ---"
    # Still isolate crontab writes in e2e
    cat << EOF > "$MOCK_DIR/crontab"
#!/bin/bash
_MD="\${MOCK_DIR:-$MOCK_DIR}"
if [ "\$IS_MOCKED_SUDO" == "true" ]; then CRON_FILE="\$_MD/root_cron"; else CRON_FILE="\$_MD/user_cron"; fi
touch "\$CRON_FILE"
if [[ "\$1" == "-l" ]]; then cat "\$CRON_FILE"; exit 0; fi
if [[ "\$1" == "-" ]]; then cat > "\${CRON_FILE}.tmp"; mv "\${CRON_FILE}.tmp" "\$CRON_FILE"; exit 0; fi
if [[ -f "\$1" ]]; then cp "\$1" "\$CRON_FILE"; exit 0; fi
EOF
    chmod +x "$MOCK_DIR/crontab"
fi

# Continue with /etc redirection and remaining mocks when not REAL_DEPS
if [ "${REAL_DEPS:-0}" != "1" ]; then
    # 12. /etc Redirection Mocks (mkdir, touch, tee, grep)
    cat << 'EOF' > "$MOCK_DIR/redirect_etc.sh"
#!/bin/bash
MOCK_FS="${MOCK_FS:-${MOCK_DIR:-/tmp/mocks}/fs}"
CMD=$(basename "$0")
ARGS=()
APPEND=false
for arg in "$@"; do
    if [[ "$CMD" == "tee" && "$arg" == "-a" ]]; then APPEND=true; continue; fi
    if [[ "$arg" == /etc/* ]]; then
        mkdir -p "$(dirname "$MOCK_FS$arg")"
        ARGS+=("$MOCK_FS$arg")
    else ARGS+=("$arg")
    fi
done
if [[ "$CMD" == "mkdir" ]]; then exec /bin/mkdir "${ARGS[@]}"
elif [[ "$CMD" == "touch" ]]; then exec /usr/bin/touch "${ARGS[@]}"
elif [[ "$CMD" == "grep" ]]; then
    if [[ "$*" == *"/proc/device-tree/model"* ]] || [[ "$*" == *"/proc/cpuinfo"* ]]; then
        if [[ "$*" == *"Raspberry Pi"* ]]; then exit 0; fi
    fi
    exec /usr/bin/grep "${ARGS[@]}"
elif [[ "$CMD" == "tee" ]]; then
    if [ "$APPEND" = true ]; then exec /usr/bin/tee -a "${ARGS[@]}"; else exec /usr/bin/tee "${ARGS[@]}"; fi
fi
EOF

    for cmd in mkdir touch tee grep; do
        ln -sf "$MOCK_DIR/redirect_etc.sh" "$MOCK_DIR/$cmd"
    done

    # 13. Samsung Extraction Mocks
    for cmd in mount umount cpio 7z file gzip; do
        cat << EOF > "$MOCK_DIR/$cmd"
#!/bin/bash
if [[ "$cmd" == "file" ]]; then echo "gzip compressed data"; exit 0; fi
if [[ "$cmd" == "cpio" ]]; then
     if [[ "\$*" == *"-id"* ]]; then
         mkdir -p "./root/usr/bin"
         touch "./root/usr/bin/fumagician"
         chmod +x "./root/usr/bin/fumagician"
     fi
     exit 0
fi
echo "[MOCK] $cmd \$@"
EOF
    done

    # 14. fwupdmgr Mock (Simplified & Robust)
    /usr/bin/rm -f "$MOCK_DIR/fwupdmgr"
    cat << EOF > "$MOCK_DIR/fwupdmgr"
#!/bin/bash
STATE_FILE="$MOCK_DIR/fwupd_mode"
KEEP="default"
if [ -f "\$STATE_FILE" ]; then KEEP=\$(cat "\$STATE_FILE"); fi

case "\$1" in
    "enable-remote"|"disable-remote"|"refresh")
        exit 0
        ;;
    "get-devices")
        if [ "\$KEEP" = "no-devices" ]; then
            echo "No devices found"
        else
            echo "Samsung SSD 970 EVO Plus 1TB"
        fi
        exit 0
        ;;
    "get-updates")
        if [ "\$KEEP" = "update-avail" ]; then
            echo "Samsung SSD 970 EVO Plus 1TB"
            echo "New version: 2B2QEXM7"
        else
            echo "No updates"
        fi
        exit 0
        ;;
    "update")
        echo "Successfully installed firmware"
        echo "Reboot required"
        exit 0
        ;;
    *)
        echo "[MOCK] fwupdmgr \$@"
        exit 0
        ;;
esac
EOF
    /usr/bin/chmod +x "$MOCK_DIR/fwupdmgr"

    # 15. nvme Mock (Simplified & Robust)
    /usr/bin/rm -f "$MOCK_DIR/nvme"
    cat << 'EOF' > "$MOCK_DIR/nvme"
#!/bin/bash
LIST_FILE="${MOCK_DIR:-/tmp/mocks}/nvme_output"
REV_FILE="${MOCK_DIR:-/tmp/mocks}/nvme_fw_rev"

case "$1" in
    "list")
        if [ -f "$LIST_FILE" ]; then
            cat "$LIST_FILE"
        else
            echo "/dev/nvme0n1     SERIAL               Samsung SSD 970 EVO Plus 1TB"
        fi
        exit 0
        ;;
    "id-ctrl")
        MODEL="Samsung SSD 970 EVO Plus"
        if [ -f "$LIST_FILE" ]; then
            if /usr/bin/grep -qi "990 PRO" "$LIST_FILE" 2>/dev/null; then MODEL="Samsung SSD 990 PRO"; fi
            if /usr/bin/grep -qi "9100 PRO" "$LIST_FILE" 2>/dev/null; then MODEL="Samsung SSD 9100 PRO"; fi
        fi
        echo "mn : $MODEL"
        if [ -f "$REV_FILE" ]; then cat "$REV_FILE"; else echo "fr : 1B2QEXM7"; fi
        exit 0
        ;;
    *)
        echo "[MOCK] nvme $@"
        exit 0
        ;;
esac
EOF

    # 16. Controllable whiptail mock (opt-in via INSTALL_USE_WHIPTAIL=1 in tests)
    # State files:
    #   ${MOCK_DIR}/whiptail_mode     - auto|fail|cancel|missing (default: auto)
    #   ${MOCK_DIR}/whiptail_yesno    - yes|no (default: yes)
    #   ${MOCK_DIR}/whiptail_input    - value for inputbox/passwordbox/menu (one value, or newline queue)
    #   ${MOCK_DIR}/whiptail_checklist - newline-separated tags for checklist output-fd
    cat << 'EOF' > "$MOCK_DIR/whiptail"
#!/bin/bash
MODE_FILE="${MOCK_DIR:-/tmp/mocks}/whiptail_mode"
YESNO_FILE="${MOCK_DIR:-/tmp/mocks}/whiptail_yesno"
INPUT_FILE="${MOCK_DIR:-/tmp/mocks}/whiptail_input"
CHECKLIST_FILE="${MOCK_DIR:-/tmp/mocks}/whiptail_checklist"
MODE="auto"
[ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE")

if [ "$MODE" = "missing" ]; then
    echo "whiptail: command not found" >&2
    exit 127
fi
if [ "$MODE" = "fail" ]; then
    echo "[MOCK] whiptail hard failure" >&2
    exit 2
fi
if [ "$MODE" = "cancel" ]; then
    exit 255
fi

# Parse dialog type and optional --output-fd
dialog=""
output_fd=""
args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
        --yesno) dialog="yesno" ;;
        --msgbox) dialog="msgbox" ;;
        --inputbox) dialog="inputbox" ;;
        --passwordbox) dialog="passwordbox" ;;
        --menu) dialog="menu" ;;
        --checklist) dialog="checklist" ;;
        --output-fd)
            i=$((i + 1))
            output_fd="${args[$i]}"
            ;;
    esac
    i=$((i + 1))
done

read_queued_value() {
    local queue_file="${1:-$INPUT_FILE}"
    if [ ! -f "$queue_file" ]; then
        echo ""
        return 0
    fi
    local first rest
    first=$(head -n 1 "$queue_file")
    rest=$(tail -n +2 "$queue_file")
    printf '%s\n' "$rest" > "$queue_file"
    printf '%s' "$first"
}

write_result() {
    local value="$1"
    if [ -n "$output_fd" ]; then
        eval "echo \"\$value\" >&$output_fd"
    else
        echo "$value"
    fi
}

case "$dialog" in
    yesno)
        ans="yes"
        if [ -f "$YESNO_FILE" ]; then
            ans=$(read_queued_value "$YESNO_FILE")
            [ -z "$ans" ] && ans="yes"
        fi
        if [ "$ans" = "no" ]; then
            exit 1
        fi
        exit 0
        ;;
    msgbox)
        exit 0
        ;;
    inputbox|passwordbox|menu)
        value=$(read_queued_value "$INPUT_FILE")
        if [ "$dialog" = "menu" ] && [ -z "$value" ]; then
            exit 255
        fi
        write_result "$value"
        exit 0
        ;;
    checklist)
        if [ -f "$CHECKLIST_FILE" ]; then
            if [ -n "$output_fd" ]; then
                eval "cat \"\$CHECKLIST_FILE\" >&$output_fd"
            else
                cat "$CHECKLIST_FILE"
            fi
        fi
        exit 0
        ;;
    *)
        echo "[MOCK] whiptail $*" >&2
        exit 0
        ;;
esac
EOF

    # Default mode files for deterministic tests
    echo "auto" > "$MOCK_DIR/whiptail_mode"
    echo "yes" > "$MOCK_DIR/whiptail_yesno"
    : > "$MOCK_DIR/whiptail_input"
    : > "$MOCK_DIR/whiptail_checklist"
fi # end REAL_DEPS != 1 heavy mocks

# Use real chmod for making mocks executable.
/usr/bin/chmod +x "$MOCK_DIR/"* 2> /dev/null || chmod +x "$MOCK_DIR/"*
echo "--- Mocks Ready ---"
