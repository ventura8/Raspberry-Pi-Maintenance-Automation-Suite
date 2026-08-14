#!/bin/bash
# Description: Reclaims disk space by pruning unused Docker containers, images,
# and volumes. Automatically detects if the buildx plugin is installed to
# use modern pruning, otherwise falls back to the legacy builder.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

# Prevent ANSI color codes from being generated
export TERM=dumb
export NO_COLOR=1

_RPI_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_RPI_HERE/lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/lib/mail_send.sh"
    # shellcheck source=../lib/i18n.sh
    source "$_RPI_HERE/lib/i18n.sh"
elif [ -f "$_RPI_HERE/../lib/os_pkg.sh" ]; then
    # shellcheck source=../lib/os_pkg.sh
    source "$_RPI_HERE/../lib/os_pkg.sh"
    # shellcheck source=../lib/mail_send.sh
    source "$_RPI_HERE/../lib/mail_send.sh"
    # shellcheck source=../lib/i18n.sh
    source "$_RPI_HERE/../lib/i18n.sh"
fi

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi Docker Cleanup Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        _pi_echo "========================================================="
        echo "   DOCKER CLEANUP LOG - $(date)"
        _pi_echo "========================================================="
        echo ""

        _pi_echo "--- Step 1: System Prune ---"
        # system prune handles stopped containers, unused networks, and dangling images.
        # The -a flag is omitted here to ensure compatibility with your Docker version.
        sudo docker system prune -f --volumes 2>&1
        echo ""

        _pi_echo "--- Step 2: Builder Prune ---"
        # Check if buildx is available as a docker plugin
        if sudo docker buildx version &> /dev/null; then
            _pi_echo "Modern Buildx detected. Pruning build cache..."
            # Using --force to handle confirmation natively.
            sudo docker buildx prune --force 2>&1
        else
            _pi_echo "Buildx not detected. Falling back to legacy builder..."
            # Filters out the legacy builder deprecation noise and installation suggestions.
            sudo docker builder prune -f 2>&1 | grep -vE "DEPRECATED|Install the buildx|docs.docker.com"
        fi
        echo ""

        _pi_echo "========================================================="
        echo "   Maintenance Finished at $(date)"
        _pi_echo "========================================================="
    } > "$LOG_FILE"

    if ! declare -F send_mail > /dev/null 2>&1; then
        echo "ERROR: mail helper (lib/mail_send.sh) is not available" >&2
        return 1
    fi
    if ! send_mail "$RECIPIENT_EMAIL" "$SUBJECT_LINE" "Raspberry Pi Docker" "$LOG_FILE"; then
        echo "WARNING: failed to deliver email notification" >&2
    fi
    # --- Cleanup ---
    rm "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
