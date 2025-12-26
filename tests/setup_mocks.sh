#!/bin/bash
set -e

# Define mock directory using dynamic HOME
# This ensures alignment with BATS tests which use $HOME
export MOCK_DIR="$HOME/mocks"
mkdir -p "$MOCK_DIR"

# Add MOCK_DIR and system sbin to PATH
export PATH="$MOCK_DIR:/usr/sbin:$PATH"

echo "--- Setting up System Mocks in $MOCK_DIR ---"
export MOCK_FS="$MOCK_DIR/fs"
mkdir -p "$MOCK_FS"

# 1. Smart Sudo Mock
# We use unquoted EOF so MOCK_DIR is expanded now
cat << EOF > "$MOCK_DIR/sudo"
#!/bin/bash
# Save original arguments for real sudo fallback
ORIG_ARGS=("\$@")

# Shift through flags (arguments starting with -)
# Support common flags like -H, -E, -u
while [[ "\$1" == -* ]]; do
    if [[ "\$1" == "-u" ]]; then
        shift; shift # Skip -u and its value
    else
        shift
    fi
done

CMD_NAME="\$1"

# Check if the command matches one of our mocks
if [ -n "\$CMD_NAME" ] && [ -x "$MOCK_DIR/\$CMD_NAME" ]; then
    # It's a mock. Run it directly with its full path and remaining arguments.
    # We skip the first argument (the command name) and pass the rest.
    export IS_MOCKED_SUDO=true
    # Shift to get only arguments
    shift 
    "$MOCK_DIR/\$CMD_NAME" "\$@"
else
    # It's a real system command. Run with real sudo and original arguments.
    # We must pass PATH so sudo sees our mocks
    /usr/bin/sudo env PATH="\$PATH" "\${ORIG_ARGS[@]}"
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
EOF

# 6. Mock Crontab (Stateful)
cat << 'EOF' > "$MOCK_DIR/crontab"
#!/bin/bash
# Identify target file based on sudo context
if [ "$IS_MOCKED_SUDO" == "true" ]; then
    CRON_FILE="$MOCK_DIR/root_cron"
else
    CRON_FILE="$MOCK_DIR/user_cron"
fi
touch "$CRON_FILE"

# If listing (-l), read the file
if [[ "$1" == "-l" ]]; then
    cat "$CRON_FILE"
    exit 0
fi

# If installing (-), overwrite the file from stdin
if [[ "$1" == "-" ]]; then
    # Buffer stdin to a temp file first to avoid race condition
    cat > "${CRON_FILE}.tmp"
    mv "${CRON_FILE}.tmp" "$CRON_FILE"
fi
EOF

# 7. Mock Curl
cat << 'EOF' > "$MOCK_DIR/curl"
#!/bin/bash
output=""
url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -o) output="$2"; shift; shift ;;
    -sSL) url="$2"; shift; shift ;;
    *) shift ;;
  esac
done
script_name=$(basename "$url")
SRC=""

# Look in ./scripts/ (standard) or current dir (uninstall.sh)
if [[ -f "./scripts/$script_name" ]]; then
    SRC="./scripts/$script_name"
elif [[ -f "./$script_name" ]]; then
    SRC="./$script_name"
fi

if [[ -n "$SRC" ]]; then
    if [[ -n "$output" ]]; then
        cp "$SRC" "$output"
    else
        # No output file -> Pipe to stdout (e.g. for uninstall.sh | bash)
        cat "$SRC"
    fi
else
    echo "Error: Mock curl could not find local file for $url" >&2
    exit 1
fi
EOF

# 8. Mock tee (critical for SSMTP config writes)
# 8. Mock tee (critical for SSMTP config writes)
cat <<'EOF' > "$MOCK_DIR/tee"
#!/bin/bash
# Mock tee to write stdin to files without requiring sudo permissions
append_mode=false
files=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -a) append_mode=true; shift ;;
    *) 
      ARG="$1"
      # Redirect /etc to MOCK_FS/etc
      if [[ "$ARG" == /etc/* ]]; then
          ARG="$MOCK_FS$ARG"
      fi
      files+=("$ARG")
      shift 
      ;;
  esac
done

# Read stdin into a variable
content=$(cat)

# Write to each file
for file in "${files[@]}"; do
  if [[ "$file" == "/dev/null" ]]; then
    continue
  fi
  
  # Create parent directory if needed
  mkdir -p "$(dirname "$file")"
  
  if [[ "$append_mode" == "true" ]]; then
    echo "$content" >> "$file"
  else
    echo "$content" > "$file"
  fi
done

# Always output to stdout (that's what tee does)
echo "$content"
EOF

# 9. Mock chmod (no-op, just succeed)
cat <<'EOF' > "$MOCK_DIR/chmod"
#!/bin/bash
# Mock chmod - just succeed without doing anything
exit 0
EOF

# 10. Mock chown (no-op, just succeed)
cat <<'EOF' > "$MOCK_DIR/chown"
#!/bin/bash
# Mock chown - just succeed without doing anything
exit 0
EOF

# 11. Mock usermod (no-op, just succeed)
cat <<'EOF' > "$MOCK_DIR/usermod"
#!/bin/bash
# Mock usermod - just succeed without doing anything
exit 0
EOF

# 12. Mock hostname (return a test hostname)
cat <<'EOF' > "$MOCK_DIR/hostname"
#!/bin/bash
echo "test-pi"
EOF

# 13. Mock ssmtp (centralized for all tests)
cat <<'EOF' > "$MOCK_DIR/ssmtp"
#!/bin/bash
# Simply print stdin to stdout or a file so tests can capture email content
cat
EOF

# 14. Mock pip3 (default, can be overridden by tests)
cat <<'EOF' > "$MOCK_DIR/pip3"
#!/bin/bash
# Default pip3 mock returns nothing to indicate up-to-date
exit 0
EOF

# 15. Mock mkdir (robust for /etc accesses)
cat <<'EOF' > "$MOCK_DIR/mkdir"
#!/bin/bash
# Redirect /etc writes to MOCK_FS
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == /etc/* ]]; then
        ARGS+=("$MOCK_FS$arg")
    else
        ARGS+=("$arg")
    fi
done

# Call real mkdir with redirected paths
/bin/mkdir "${ARGS[@]}"
EOF

# 16. Mock touch (robust for /etc accesses)
cat <<'EOF' > "$MOCK_DIR/touch"
#!/bin/bash
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == /etc/* ]]; then
        mkdir -p "$(dirname "$MOCK_FS$arg")"
        ARGS+=("$MOCK_FS$arg")
    else
        ARGS+=("$arg")
    fi
done

/usr/bin/touch "${ARGS[@]}"
EOF

# 17. Mock grep (prevent permission denied errors on system logs/configs)
cat <<'EOF' > "$MOCK_DIR/grep"
#!/bin/bash
ARGS=()
for arg in "$@"; do
    # If checking a file in /etc, check the mock FS instead
    if [[ "$arg" == /etc/* ]]; then
        ARGS+=("$MOCK_FS$arg")
    else
        ARGS+=("$arg")
    fi
done

/bin/grep "${ARGS[@]}" 2>/dev/null
EOF

# Make all mocks executable
chmod +x "$MOCK_DIR/"*

echo "--- Mocks Ready ---"
