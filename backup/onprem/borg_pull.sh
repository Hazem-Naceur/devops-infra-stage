#!/bin/bash
set -uo pipefail

STAGING_DIR="$HOME/onprem_backups/staging"
REPO="$HOME/onprem_backups/test_project_repo"
SSH_KEY="$HOME/.ssh/id_borg_pull"
LOG_FILE="$HOME/onprem_backups/borg_pull.log"

export BORG_PASSPHRASE="$(cat "$HOME/.borg_passphrase")"

VPS1_USER="backupuser"; VPS1_HOST="vps1.example.com"
VPS2_USER="backupuser"; VPS2_HOST="vps2.example.com"
REMOTE_BACKUP_DIR="backups"

log_message() {
    local TYPE="$1" MSG="$2"
    local LOG_LINE="$(date +'%Y-%m-%d %H:%M:%S') [$TYPE] - $MSG"
    echo -e "$LOG_LINE"
    echo -e "$LOG_LINE" >> "$LOG_FILE"
}

log_message "INFO" "=== Start of Borg pull ==="
mkdir -p "$STAGING_DIR"

# 1. SOURCE VPS SELECTION - via the CHECK_MARKER keyword handled by the wrapper
ACTIVE_USER=""; ACTIVE_HOST=""
for PAIR in "$VPS1_USER:$VPS1_HOST" "$VPS2_USER:$VPS2_HOST"; do
    U="${PAIR%%:*}"; H="${PAIR##*:}"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
         "$U@$H" "CHECK_MARKER" 2>/dev/null; then
        ACTIVE_USER="$U"; ACTIVE_HOST="$H"
        log_message "INFO" "Selected source: $U@$H"
        break
    else
        log_message "WARNING" "$U@$H unreachable or backup not finalized - trying next..."
    fi
done

if [ -z "$ACTIVE_HOST" ]; then
    log_message "ERROR" "No reachable VPS with a complete backup. Aborting."
    exit 1
fi

# 2. PULL FILES
rsync -avz -e "ssh -i $SSH_KEY" "$ACTIVE_USER@$ACTIVE_HOST:$REMOTE_BACKUP_DIR/" "$STAGING_DIR/"
if [ $? -ne 0 ]; then
    log_message "ERROR" "rsync failed from $ACTIVE_HOST. Nothing deleted on the VPS side."
    exit 1
fi
log_message "SUCCESS" "Files pulled from $ACTIVE_USER@$ACTIVE_HOST"

# 3. BORG ARCHIVE CREATION
borg create --stats --compression zstd "$REPO::test_project-{now:%Y-%m-%d_%H%M}" "$STAGING_DIR"
if [ $? -ne 0 ]; then
    log_message "ERROR" "Borg archive failed! VPS files kept."
    exit 1
fi
log_message "SUCCESS" "Borg archive created from $ACTIVE_USER@$ACTIVE_HOST"

# Dead man's switch: timestamp read by node_exporter (textfile collector)
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
mkdir -p "$TEXTFILE_DIR"
echo "backup_last_success_timestamp_seconds $(date +%s)" > "$TEXTFILE_DIR/backup_status.prom.tmp"
mv "$TEXTFILE_DIR/backup_status.prom.tmp" "$TEXTFILE_DIR/backup_status.prom"

# 4. DELETION ON ACTIVE VPS - via the CLEANUP keyword
ssh -i "$SSH_KEY" -o BatchMode=yes "$ACTIVE_USER@$ACTIVE_HOST" "CLEANUP"
if [ $? -eq 0 ]; then
    log_message "SUCCESS" "Files deleted on $ACTIVE_HOST."
else
    log_message "WARNING" "Deletion failed on $ACTIVE_HOST."
fi

# 4b. STANDBY CLEANUP - via CLEANUP_IF_OLD
for PAIR in "$VPS1_USER:$VPS1_HOST" "$VPS2_USER:$VPS2_HOST"; do
    U="${PAIR%%:*}"; H="${PAIR##*:}"
    [ "$H:$U" == "$ACTIVE_HOST:$ACTIVE_USER" ] && continue

    ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$U@$H" "CLEANUP_IF_OLD" 2>/dev/null
    STATUS=$?
    case $STATUS in
        0) log_message "SUCCESS" "Standby $U@$H cleaned." ;;
        2) log_message "INFO" "$U@$H : nothing to clean." ;;
        *) log_message "WARNING" "$U@$H unreachable or cleanup failed." ;;
    esac
done

# 5. RETENTION
borg prune --list "$REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6

# 6. LOCAL STAGING CLEANUP
rm -rf "${STAGING_DIR:?}"/*
log_message "INFO" "=== End of Borg pull ==="
