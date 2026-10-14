#!/bin/bash
set -uo pipefail

BACKUP_DIR="$HOME/backups"
DB_NAME="test_app_db"
LOG_FILE="$BACKUP_DIR/restore.log"

log_message() {
    local TYPE="$1" MSG="$2"
    local LOG_LINE="$(date +'%Y-%m-%d %H:%M:%S') [$TYPE] - $MSG"
    echo -e "$LOG_LINE"
    echo -e "$LOG_LINE" >> "$LOG_FILE"
}

log_message "INFO" "=== Start of restore ==="

LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/db_backup_*.sql.gz 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    log_message "ERROR" "No backup file found in $BACKUP_DIR"
    exit 1
fi

log_message "WARNING" "Preparing to restore file: $LATEST_BACKUP"
log_message "WARNING" "WARNING: This will overwrite the current database '$DB_NAME'!"

read -p "Do you want to continue? (y/N): " confirm

if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    log_message "INFO" "Decompressing and importing from $LATEST_BACKUP..."
    zcat "$LATEST_BACKUP" | mysql --defaults-file="$HOME/.my_restore.cnf" "$DB_NAME"

    if [ ${PIPESTATUS[1]} -eq 0 ]; then
        log_message "SUCCESS" "Restore completed successfully from $LATEST_BACKUP"
    else
        log_message "ERROR" "Restore failed from $LATEST_BACKUP"
        exit 1
    fi
else
    log_message "INFO" "Restore cancelled by user."
fi

log_message "INFO" "=== End of restore ==="
