#!/bin/bash
set -e

# Define mock directory using dynamic HOME
export MOCK_DIR="/tmp/mocks"
mkdir -p "$MOCK_DIR"

# Add MOCK_DIR and system sbin to PATH
export PATH="$MOCK_DIR:/usr/sbin:$PATH"

echo "--- Setting up System Mocks in $MOCK_DIR ---"
export MOCK_FS="$MOCK_DIR/fs"
mkdir -p "$MOCK_FS/proc/device-tree"
echo "Raspberry Pi 5 Model B Rev 1.0" > "$MOCK_FS/proc/device-tree/model"
echo "Model : Raspberry Pi 5 Model B Rev 1.0" > "$MOCK_FS/proc/cpuinfo"

# 1. Smart Sudo Mock
cat << 'EOF' > "/tmp/mocks/sudo"
#!/bin/bash
MOCK_DIR="/tmp/mocks"
ORIG_ARGS=("$@")
while [[ "$1" == -* ]]; do
    if [[ "$1" == "-u" ]]; then shift; shift; else shift; fi
done
CMD_NAME="$1"
if [ -n "$CMD_NAME" ] && [ -x "$MOCK_DIR/$CMD_NAME" ]; then
    export IS_MOCKED_SUDO=true
    shift 
    "$MOCK_DIR/$CMD_NAME" "$@"
else
    /usr/bin/sudo env PATH="$MOCK_DIR:$PATH" MOCK_DIR="$MOCK_DIR" "${ORIG_ARGS[@]}"
fi
EOF

# 2. Mock rpi-eeprom-update
cat << 'EOF' > "$MOCK_DIR/rpi-eeprom-update"
#!/bin/bash
echo "BOOTLOADER: update available"
echo "UPDATE SUCCESSFUL"
EOF

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

# 5. Mock Apt-Get
cat << 'EOF' > "$MOCK_DIR/apt-get"
#!/bin/bash
echo "[MOCK] apt-get $@"
# For dependency check success message
if [[ "$*" == *"install"* ]]; then
    echo "Dependencies installed successfully."
fi
EOF

# 6. Mock Crontab (Stateful)
cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
if [ "$IS_MOCKED_SUDO" == "true" ]; then CRON_FILE="/tmp/mocks/root_cron"; else CRON_FILE="/tmp/mocks/user_cron"; fi
touch "$CRON_FILE"
if [[ "$1" == "-l" ]]; then cat "$CRON_FILE"; exit 0; fi
if [[ "$1" == "-" ]]; then cat > "${CRON_FILE}.tmp"; mv "${CRON_FILE}.tmp" "$CRON_FILE"; fi
EOF

# 7. Mock Curl (with local file support and Samsung page simulation)
cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
outfile=""
url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -o) outfile="$2"; shift; shift ;;
    -sSL|-sL|-L|-s) url="$2"; shift; shift ;;
    *) shift ;;
  esac
done
if [[ "$url" == *"semiconductor.samsung.com"* ]]; then
    echo '<a href="https://download.semiconductor.samsung.com/970_EVO_Plus_2B2QEXM7.iso">970 EVO Plus</a><span>2B2QEXM7</span>'
    exit 0
fi
script_name=$(basename "$url")
if [[ -f "./scripts/$script_name" ]]; then SRC="./scripts/$script_name"
elif [[ -f "./$script_name" ]]; then SRC="./$script_name"
else SRC="/dev/null"; touch "$SRC"; fi
if [[ -n "$outfile" ]]; then 
    if [ "$SRC" = "/dev/null" ]; then echo "MOCK DATA" > "$outfile"; else cp "$SRC" "$outfile"; fi
else cat "$SRC" 2>/dev/null || true; fi
EOF

# 8. No-ops (chmod, chown, usermod)
for cmd in chmod chown usermod; do
    echo "#!/bin/bash" > "$MOCK_DIR/$cmd"
    echo "exit 0" >> "$MOCK_DIR/$cmd"
done

# 9. Mock hostname
echo '#!/bin/bash' > "$MOCK_DIR/hostname"
echo 'echo "test-pi"' >> "$MOCK_DIR/hostname"

# 10. Mock ssmtp
echo '#!/bin/bash' > "$MOCK_DIR/ssmtp"
echo 'cat' >> "$MOCK_DIR/ssmtp"

# 11. Mock pip3
echo '#!/bin/bash' > "$MOCK_DIR/pip3"
echo 'exit 0' >> "$MOCK_DIR/pip3"

# 12. /etc Redirection Mocks (mkdir, touch, tee, grep)
cat <<'EOF' > "$MOCK_DIR/redirect_etc.sh"
#!/bin/bash
MOCK_FS="/tmp/mocks/fs"
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
    ln -sf "/tmp/mocks/redirect_etc.sh" "$MOCK_DIR/$cmd"
done

# 13. Samsung Extraction Mocks
for cmd in mount umount cpio 7z file gzip; do
    cat <<EOF > "$MOCK_DIR/$cmd"
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
cat <<'EOF' > "/tmp/mocks/fwupdmgr"
#!/bin/bash
STATE_FILE="/tmp/mocks/fwupd_mode"
MODE="default"
if [ -f "$STATE_FILE" ]; then MODE=$(cat "$STATE_FILE"); fi

case "$1" in
    "enable-remote"|"disable-remote"|"refresh")
        exit 0
        ;;
    "get-devices")
        if [ "$MODE" = "no-devices" ]; then
            echo "No devices found"
        else
            echo "Samsung SSD 970 EVO Plus 1TB"
        fi
        exit 0
        ;;
    "get-updates")
        if [ "$MODE" = "update-avail" ]; then
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
        echo "[MOCK] fwupdmgr $@"
        exit 0
        ;;
esac
EOF

# 15. nvme Mock (Simplified & Robust)
cat <<'EOF' > "/tmp/mocks/nvme"
#!/bin/bash
LIST_FILE="/tmp/mocks/nvme_output"
REV_FILE="/tmp/mocks/nvme_fw_rev"

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

chmod +x "$MOCK_DIR/"*
echo "--- Mocks Ready ---"
