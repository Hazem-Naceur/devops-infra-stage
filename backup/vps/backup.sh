#!/bin/bash
# ==============================================================================
# BACKUP.SH - Deploy IDENTICALLY on VPS1 AND VPS2 (both DBs being
# replicated/synced, each VPS must be able to produce a valid backup
# independently, in case one of them is unreachable at the time
# of the cron run).
# ==============================================================================

set -uo pipefail

DATE=$(date +%Y-%m-%d_%H%M)

# --- Local paths on this VPS -----------------------------------------------

BACKUP_DIR="$HOME/backups"
APP_DIR="${APP_DIR:-/opt/testapp}"   # app deployment path (override via env)
LOG_FILE="$BACKUP_DIR/backup.log"
LOCK_FILE="$HOME/.backup.lock"

# --- Configuration MySQL -----------------------------------------------------

DB_NAME="test_app_db"

# --- Final backup files ------------------------------------------------

DB_BACKUP_FILE="$BACKUP_DIR/db_backup_$DATE.sql.gz"
FILES_BACKUP_FILE="$BACKUP_DIR/files_backup_$DATE.tar.gz"
MARKER_FILE="$BACKUP_DIR/.backup_complete_$DATE"

# ==============================================================================
# LOCK - prevents two concurrent runs (e.g. a cron that fires again
# while a previous run is still in progress on a large uploads volume)
# ==============================================================================

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] - A backup is already running, aborting." >> "${LOG_FILE:-/tmp/backup_lock_error.log}"
    exit 1
fi

# ==============================================================================
# LOGGING
# ==============================================================================

log_message() {
    local TYPE="$1"
    local MSG="$2"
    local LOG_LINE="$(date +'%Y-%m-%d %H:%M:%S') [$TYPE] - $MSG"
    echo -e "$LOG_LINE"
    echo -e "$LOG_LINE" >> "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
log_message "INFO" "=== Start of local backup (dump + archive) ==="

# ==============================================================================
# 1. DATABASE DUMP + COMPRESSION
#    --single-transaction : avoids locking InnoDB tables
#    --quick               : avoids loading the whole table in RAM
# ==============================================================================

log_message "INFO" "Exporting MySQL database ($DB_NAME)..."

mysqldump --defaults-file="$HOME/.my_backup.cnf" --single-transaction --quick "$DB_NAME" 2>> "$LOG_FILE" | gzip > "$DB_BACKUP_FILE"
DUMP_STATUS=${PIPESTATUS[0]}

if [ "$DUMP_STATUS" -eq 0 ]; then
    chmod 600 "$DB_BACKUP_FILE"
    log_message "SUCCESS" "Database exported and compressed successfully: $DB_BACKUP_FILE"
else
    log_message "ERROR" "Database export failed! Stopping script."
    rm -f "$DB_BACKUP_FILE"   # never leave a partial/corrupt file that Borg could pick up
    exit 1
fi

# ==============================================================================
# 2. APPLICATION FILES ARCHIVE (if the folder exists)
# ==============================================================================

if [ -d "$APP_DIR/uploads" ]; then
    log_message "INFO" "Archiving and compressing application files (uploads)..."

    tar -czf "$FILES_BACKUP_FILE" -C "$APP_DIR" "uploads" 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        chmod 600 "$FILES_BACKUP_FILE"
        log_message "SUCCESS" "Files backed up successfully: $FILES_BACKUP_FILE"
    else
        log_message "ERROR" "File backup failed!"
        rm -f "$FILES_BACKUP_FILE"
    fi
else
    log_message "WARNING" "Uploads folder ($APP_DIR/uploads) does not exist. Step skipped."
fi

# ==============================================================================
# 3. COMPLETION MARKER - tells the on-prem script (borg_pull.sh) that the
#    files of this run are complete and safe to fetch.
#    Without this marker, a pull arriving while files are being written
#    could fetch a truncated archive.
# ==============================================================================

touch "$MARKER_FILE"
log_message "INFO" "=== End of local backup ==="
