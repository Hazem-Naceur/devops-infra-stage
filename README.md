# Monitoring, backup and failover for a bare-metal application

Internship project (Cloud/DevOps, ESPRIT, 2026). A company runs a web application directly on Ubuntu 24 servers (no Docker): a primary VPS, a secondary VPS and a firewalled on-prem Linux server. The goal was to add three things using only free, open-source tools:

1. **Application monitoring** (not just OS metrics)
2. **Automated backups** of the app files and the MySQL database from the primary VPS to the on-prem server
3. **Failover** between the two VPS

Everything here is generic: the application is a minimal Spring Boot test app (`testapp`) with a test database (`test_app_db`). Hosts use placeholders (`vps1.example.com`, IPs from the `203.0.113.0/24` documentation range).

> **Lab note:** the solution was built and tested on one AlmaLinux VM that simulated the three hosts with three Linux users. The repo is adapted from that lab (paths, users and unit files were generalized to a production-style layout) and was **not re-run end to end after the adaptation**. See [Limitations](#limitations).

## Architecture

```
                     users
                       |
                  DNS record (DuckDNS)  <---------------------------+
                       |                                            |
          +------------+-------------+                              |
          v                          v                              |
   VPS1 (primary)             VPS2 (standby)                        |
   app :8080, MySQL           app :8080, MySQL                      |
   backup.sh  03:00           backup.sh  03:00                      |
   ~/backups + marker         ~/backups + marker                    |
          ^                          ^                              |
          |   SSH pull, restricted key (forced command)             |
          +------------+-------------+                              |
                       |                                            |
                On-prem server                                      |
                borg_pull.sh 03:30 -> Borg repo (encrypted, dedup)  |
                writes backup_last_success timestamp                |
                       |                                            |
                node_exporter (textfile collector)                  |
                       |                                            |
   Monitoring stack: Prometheus <- blackbox, mysqld_exporter,       |
   node_exporter, Spring Actuator; Loki/Promtail for logs;          |
   Grafana dashboard                                                |
                       |                                            |
                Alertmanager --> email, Telegram, webhook           |
                                          |                         |
                                 webhook_listener.py :9095          |
                                          |                         |
                                    failover.sh -- DuckDNS API -----+
```

## How the pieces interact

- **Metrics:** Prometheus scrapes the app (`/actuator/prometheus`, Micrometer), MySQL (`mysqld_exporter`), a blackbox HTTP probe of `/actuator/health`, and `node_exporter` (textfile collector only).
- **Alerts:** `BackupStale` (no confirmed backup for 26h), `AppDown` (probe fails for 1m), `MySQLDown`. Alertmanager sends to email, Telegram and a local webhook.
- **Backups feed monitoring:** after each confirmed Borg archive, `borg_pull.sh` writes `backup_last_success_timestamp_seconds`. If that stops advancing, `BackupStale` fires (a dead man's switch).
- **Monitoring feeds failover:** `AppDown` -> Alertmanager POSTs to `webhook_listener.py` -> `failover.sh` repoints the DNS record from VPS1 to VPS2.

## 1. Monitoring (`monitoring/`)

Prometheus 2.53, Grafana, Alertmanager 0.27, Blackbox Exporter 0.25, mysqld_exporter 0.15, node_exporter 1.8 (textfile collector only), Loki and Promtail 3.1, all as systemd services (`monitoring/systemd/`). The Grafana dashboard (`monitoring/grafana/dashboard.json`) has JVM heap/threads, uptime, HTTP rate and latency, MySQL connections/QPS/slow queries, and a live Loki logs panel. The Alertmanager config is a template: `render_alertmanager_config.sh` injects the secrets from a local file, so secrets are never committed.

## 2. Backups (`backup/`)

- **VPS side (`backup/vps/backup.sh`, runs on both VPS):** `mysqldump --single-transaction --quick | gzip`, tar of `uploads/`, files set to `600`, then a `.backup_complete_*` marker so a pull never grabs a half-written backup. `flock` prevents concurrent runs, and a failed dump aborts and removes the partial file. DB credentials come from `~/.my_backup.cnf` for a read-only user (`backup/sql/setup_users.sql`).
- **Pull model (`backup/onprem/borg_pull.sh`):** the on-prem server connects to the VPS, never the other way round, so a compromised VPS holds no key to the backup server. It picks VPS1 if reachable with a completed marker, otherwise VPS2; pulls with rsync; creates a BorgBackup archive (encrypted, deduplicated, zstd); and only then deletes the files on the VPS. It also cleans the standby VPS if its marker is older than 30 minutes. Retention: 7 daily, 4 weekly, 6 monthly.
- **Restricted SSH key (`backup/vps/borg_receive.sh`):** forced via `command=` in `authorized_keys`, it whitelists only `rsync --server --sender`, `CHECK_MARKER`, `CLEANUP`, `CLEANUP_IF_OLD` and `RESTORE_UPLOAD`. Example entry:
```
  command="/opt/devops-infra/backup/borg_receive.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 <key>
```
- **Restore:** `restore_fetch.sh <archive> <user> <host>` (on-prem) extracts the archive and streams the dump to the target VPS; `restore.sh` (VPS) imports it after an interactive confirmation.
- **Schedule:** `backup.timer` 03:00 on each VPS, `borg-pull.timer` 03:30 on-prem.

## 3. Failover (`failover/`)

DNS-based, because VRRP/keepalived needs a shared L2 network that was not confirmed at the hosting provider. `webhook_listener.py` (port 9095, systemd unit included) accepts the Alertmanager webhook and runs `failover.sh` on a firing `AppDown`. The script calls the DuckDNS API to point the subdomain at VPS2's IP and records the switch in a state file. Tested with a real flip, verified with `dig` and `dig +trace` against the authoritative servers.

## Repo layout

```
monitoring/   prometheus, alertmanager (template), blackbox, loki, promtail, grafana, systemd, testapp
backup/       vps/, onprem/, systemd/, sql/
failover/     failover.sh, webhook_listener.py, webhook-listener.service
secrets.example/   fake-value templates for every secret file
docs/         lessons-learned.md
```

## Deploying

Install layout: scripts in `/opt/devops-infra/{backup,failover}`, units in `/etc/systemd/system/`, configs in `/etc/<tool>/`.

1. Create the DB users: edit the `CHANGE_ME` passwords in `backup/sql/setup_users.sql`, then run it as MySQL root.
2. Copy `secrets.example/*` to your home directory without the `.example` suffix, fill in real values, `chmod 600`.
3. VPS: install `backup/vps/*` and `backup.service/.timer`, add the restricted key to `authorized_keys`.
4. On-prem: install `backup/onprem/*`, create the Borg repo (`borg init --encryption=repokey`), enable `borg-pull.timer`.
5. Monitoring host: install the configs and units, run `render_alertmanager_config.sh`, import the Grafana dashboard.
6. Failover: install `failover/*` and enable `webhook-listener.service`.

**Change the Grafana default `admin` credentials after install.** Replace the placeholder IPs and hostnames. Point the Prometheus targets (`localhost` in the lab) at the real VPS1.

## Secrets

Never committed (see `.gitignore`): DB credential files, `.borg_passphrase`, `.alertmanager_secrets`, `.duckdns_secrets`, the rendered `alertmanager.yml`, and SSH keys. Use `secrets.example/` as the template.

## Limitations

- **Single-VM simulation.** The repo layout was adapted from the tested lab and not re-run end to end; `webhook-listener.service` in particular is new and untested.
- **WireGuard tunnel** (on-prem to VPS) is not implemented; it is a production requirement.
- **MySQL replication** between the VPS is assumed (the company said it exists), not reproduced.
- **DuckDNS and placeholder IPs** stand in for a real DNS provider and real VPS addresses.
- **Failover is a one-way latch.** After the first switch the state file records VPS2 as the target and later runs exit early, so the 300 s cooldown never applies in practice. Failback is manual: delete the state file and repoint DNS.
- **rsync path scope.** `borg_receive.sh` whitelists `rsync --server --sender` but does not confine paths; in production, use `rrsync` to lock it to the backup directory.
- **`BackupStale` is silent if the metric disappears** (for example a broken textfile collector); `or absent(backup_last_success_timestamp_seconds)` would close that gap.
- **MariaDB vs MySQL 8.** The lab ran MariaDB. On MySQL 8, `mysqldump` needs `--no-tablespaces` or the `PROCESS` privilege for the backup user.
- **Prometheus targets** use `localhost` in the lab; in production, run the stack outside VPS1, otherwise the monitor goes down with the primary.
- **Webhook listener** binds to localhost over plain HTTP with no authentication.
- **Monthly automated restore test** was designed but skipped.
- **Angular frontend monitoring (RUM)** was out of scope (no good open-source option).

## License

MIT
