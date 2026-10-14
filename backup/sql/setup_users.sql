-- Run as MySQL root on each VPS. Replace CHANGE_ME with strong, unique passwords.
-- Test schema shown here; in production, scope the grants to the real database.

CREATE DATABASE IF NOT EXISTS test_app_db;
USE test_app_db;
CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(50));
INSERT IGNORE INTO users VALUES (1,'alice'),(2,'bob');

-- Read-only user used by backup.sh (credentials in ~/.my_backup.cnf, chmod 600)
CREATE USER IF NOT EXISTS 'backup_user'@'localhost' IDENTIFIED BY 'CHANGE_ME';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON test_app_db.* TO 'backup_user'@'localhost';

-- Used by restore.sh only (credentials in ~/.my_restore.cnf, chmod 600)
CREATE USER IF NOT EXISTS 'restore_user'@'localhost' IDENTIFIED BY 'CHANGE_ME';
GRANT ALL PRIVILEGES ON test_app_db.* TO 'restore_user'@'localhost';

-- Used by mysqld_exporter (credentials in .mysqld_exporter.cnf, chmod 600)
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'CHANGE_ME' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';

FLUSH PRIVILEGES;
