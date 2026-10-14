#!/bin/bash
set -uo pipefail

REPO="$HOME/onprem_backups/test_project_repo"
STAGING_DIR="$HOME/onprem_backups/restore_staging"
SSH_KEY="$HOME/.ssh/id_borg_pull"
LOG_FILE="$HOME/onprem_backups/restore_fetch.log"

log_message() {
    local TYPE="$1" MSG="$2"
    local LOG_LINE="$(date +'%Y-%m-%d %H:%M:%S') [$TYPE] - $MSG"
    echo -e "$LOG_LINE"
    echo -e "$LOG_LINE" >> "$LOG_FILE"
}

ARCHIVE_NAME="${1:-}"
TARGET_USER="${2:-}"
TARGET_HOST="${3:-}"

if [ -z "$ARCHIVE_NAME" ] || [ -z "$TARGET_USER" ] || [ -z "$TARGET_HOST" ]; then
    echo "Usage: $0 <archive_name> <target_user> <target_host>"
    echo "Available archives:"
    borg list "$REPO"
    exit 1
fi

log_message "INFO" "=== Start restore_fetch: archive=$ARCHIVE_NAME target=$TARGET_USER@$TARGET_HOST ==="

mkdir -p "$STAGING_DIR"
rm -rf "${STAGING_DIR:?}"/*

cd "$STAGING_DIR" || exit 1
borg extract "$REPO::$ARCHIVE_NAME"

if [ $? -ne 0 ]; then
    log_message "ERROR" "Borg extraction failed for $ARCHIVE_NAME"
    exit 1
fi
log_message "SUCCESS" "Archive $ARCHIVE_NAME extracted to $STAGING_DIR"

FOUND_DUMP=$(find "$STAGING_DIR" -name "db_backup_*.sql.gz" | sort | tail -n 1)

if [ -z "$FOUND_DUMP" ]; then
    log_message "ERROR" "No db_backup_*.sql.gz found in the extracted archive."
    exit 1
fi
log_message "INFO" "Dump found: $FOUND_DUMP"

# Sent via the restricted key: the borg_receive.sh wrapper recognizes
# "RESTORE_UPLOAD" and reads the dump content from stdin.
ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" "RESTORE_UPLOAD" < "$FOUND_DUMP"

if [ $? -eq 0 ]; then
    log_message "SUCCESS" "Dump transferred to $TARGET_USER@$TARGET_HOST via restricted key"
    log_message "INFO" "Now run restore.sh on $TARGET_HOST"
else
    log_message "ERROR" "Transfer failed to $TARGET_USER@$TARGET_HOST"
    exit 1
fi

log_message "INFO" "=== End of restore_fetch ==="
