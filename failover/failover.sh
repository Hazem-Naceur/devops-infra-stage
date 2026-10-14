#!/bin/bash
# ==============================================================================
# FAILOVER.SH - triggered by the Alertmanager webhook when AppDown fires.
# Uses the real DuckDNS API. A cooldown prevents "flapping" (repeated switches
# if VPS1 becomes unstable instead of fully down).
# ==============================================================================
set -uo pipefail
source "$HOME/.duckdns_secrets"


VPS1_IP="203.0.113.10"   # placeholder - real public IP of VPS1 in production
VPS2_IP="203.0.113.20"   # placeholder - real public IP of VPS2 in production

STATE_FILE="/var/lib/devops-infra/failover_state.txt"
LOG_FILE="/var/log/devops-infra/failover.log"
COOLDOWN_SECONDS=300   # 5 minutes - avoids switching back and forth in a loop

log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$1] - $2" | tee -a "$LOG_FILE"
}

# ==============================================================================
# ANTI-FLAPPING GUARD
# ==============================================================================
if [ -f "$STATE_FILE" ]; then
    LAST_SWITCH=$(grep -oP 'timestamp=\K[0-9]+' "$STATE_FILE" 2>/dev/null || echo 0)
    CURRENT_TARGET=$(grep -oP 'target=\K.+' "$STATE_FILE" 2>/dev/null || echo "$VPS1_IP")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SWITCH))

    if [ "$CURRENT_TARGET" == "$VPS2_IP" ]; then
        log_message "INFO" "Already switched to VPS2, no action needed."
        exit 0
    fi

    if [ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]; then
        log_message "WARNING" "Switch ignored: last change ${ELAPSED}s ago (cooldown=${COOLDOWN_SECONDS}s)."
        exit 0
    fi
fi

# ==============================================================================
# REAL DUCKDNS API CALL
# ==============================================================================
log_message "WARNING" "VPS1 reported down by Alertmanager. Switching DNS to VPS2 ($VPS2_IP)."

RESPONSE=$(curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${VPS2_IP}")

if [ "$RESPONSE" == "OK" ]; then
    echo "timestamp=$(date +%s)" > "$STATE_FILE"
    echo "target=$VPS2_IP" >> "$STATE_FILE"
    log_message "SUCCESS" "DNS updated successfully: $VPS2_IP active (DuckDNS response: $RESPONSE)."
else
    log_message "ERROR" "DuckDNS update failed! Response: $RESPONSE"
    exit 1
fi
