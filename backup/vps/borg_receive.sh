#!/bin/bash
BACKUP_DIR="$HOME/backups"

case "$SSH_ORIGINAL_COMMAND" in
    "rsync --server --sender"*)
        exec $SSH_ORIGINAL_COMMAND
        ;;
    "CHECK_MARKER")
        ls "$BACKUP_DIR"/.backup_complete_* >/dev/null 2>&1
        exit $?
        ;;
    "CLEANUP")
        rm -f "$BACKUP_DIR"/db_backup_*.sql.gz "$BACKUP_DIR"/files_backup_*.tar.gz "$BACKUP_DIR"/.backup_complete_*
        exit $?
        ;;
    "CLEANUP_IF_OLD")
        MARKER=$(find "$BACKUP_DIR" -name ".backup_complete_*" -mmin +30 2>/dev/null | head -n 1)
        if [ -n "$MARKER" ]; then
            rm -f "$BACKUP_DIR"/db_backup_*.sql.gz "$BACKUP_DIR"/files_backup_*.tar.gz "$BACKUP_DIR"/.backup_complete_*
            exit 0
        else
            exit 2
        fi
        ;;
    "RESTORE_UPLOAD")
        # Receives a dump from stdin and stores it under a name that matches
        # the pattern expected by restore.sh (db_backup_*.sql.gz), timestamped
        # so it is automatically the most recent at restore time.
        DEST="$BACKUP_DIR/db_backup_restored_$(date +%Y-%m-%d_%H%M).sql.gz"
        cat > "$DEST"
        if [ $? -eq 0 ]; then
            chmod 600 "$DEST"
            exit 0
        else
            exit 1
        fi
        ;;
    *)
        echo "Command not permitted." >&2
        exit 1
        ;;
esac
