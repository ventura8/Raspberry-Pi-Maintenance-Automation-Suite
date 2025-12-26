#!/bin/bash
# Description: Reclaims disk space by pruning unused Docker containers, images, 
# volumes, and build cache. It forces the cleanup without user interaction 
# and emails the results to Gmail.

# --- Configuration ---
RECIPIENT_EMAIL="your_email@gmail.com"
# ---------------------

LOG_FILE=$(mktemp)
PI_HOSTNAME=$(hostname)
SUBJECT_LINE="Raspberry Pi Docker Cleanup Report for $PI_HOSTNAME - $(date)"

{
    echo "========================================================="
    echo "   DOCKER CLEANUP LOG - $(date)"
    echo "========================================================="
    echo ""

    echo "--- Step 1: System Prune ---"
    sudo docker system prune -a -f --volumes 2>&1
    echo ""

    echo "--- Step 2: Builder Prune ---"
    sudo docker builder prune -a -f 2>&1
    echo ""

    echo "========================================================="
    echo "   Maintenance Finished at $(date)"
    echo "========================================================="
} > "$LOG_FILE"

# Convert line endings for email compatibility
CLEAN_LOG=$(mktemp)
sed 's/$/\r/' "$LOG_FILE" > "$CLEAN_LOG"

/usr/sbin/ssmtp "$RECIPIENT_EMAIL" <<EOF
To: $RECIPIENT_EMAIL
Subject: $SUBJECT_LINE
From: "Raspberry Pi Docker" <$RECIPIENT_EMAIL>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$CLEAN_LOG")
EOF

rm "$LOG_FILE"
rm "$CLEAN_LOG"
