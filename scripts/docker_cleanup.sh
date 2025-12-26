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
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

main() {
    LOG_FILE=$(mktemp)
    PI_HOSTNAME=$(hostname)
    SUBJECT_LINE="Raspberry Pi Docker Cleanup Report for $PI_HOSTNAME - $(date)"

    {
        # Hardcoded separators matching text length
        echo "========================================================="
        echo "   DOCKER CLEANUP LOG - $(date)"
        echo "========================================================="
        echo ""

        echo "--- Step 1: System Prune ---"
        # system prune handles stopped containers, unused networks, and dangling images.
        # The -a flag is omitted here to ensure compatibility with your Docker version.
        sudo docker system prune -f --volumes 2>&1
        echo ""

        echo "--- Step 2: Builder Prune ---"
        # Check if buildx is available as a docker plugin
        if sudo docker buildx version &> /dev/null; then
            echo "Modern Buildx detected. Pruning build cache..."
            # Using --force to handle confirmation natively.
            sudo docker buildx prune --force 2>&1
        else
            echo "Buildx not detected. Falling back to legacy builder..."
            # Filters out the legacy builder deprecation noise and installation suggestions.
            sudo docker builder prune -f 2>&1 | grep -vE "DEPRECATED|Install the buildx|docs.docker.com"
        fi
        echo ""

        echo "========================================================="
        echo "   Maintenance Finished at $(date)"
        echo "========================================================="
    } > "$LOG_FILE"

    # --- Send the report ---
    if command -v ssmtp >/dev/null 2>&1; then
        ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Docker" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")
EOF
    else
        echo "ssmtp not found, skipping email notification."
    fi

    # --- Cleanup ---
    rm "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
