#!/usr/bin/env bash
# infra/setup-mariadb-replication.sh
#
# Configures binary-log replication from the MariaDB Primary (port 3306)
# to the MariaDB Replica (port 3307, socket /var/run/mysqld/mysqld-replica.sock).
#
# Requirements: 5.3
#
# Usage:
#   export REPL_PASSWORD="<replication-user-password>"
#   sudo -E bash infra/setup-mariadb-replication.sh
#
# The -E flag preserves the user's environment variables under sudo.
# This script is idempotent: if the Replica's SQL thread and IO thread are
# already running, CHANGE MASTER and START SLAVE are skipped.

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        err "Environment variable '${var}' is not set or empty. Aborting."
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

require_env REPL_PASSWORD

if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root (use: sudo -E bash $0)"
fi

REPLICA_SOCKET="/var/run/mysqld/mysqld-replica.sock"

# Verify Primary (port 3306) is reachable via unix socket
if ! mysqladmin --user=root ping --connect-timeout=5 &>/dev/null; then
    err "MariaDB Primary is not responding. Run setup-mariadb-primary.sh first."
fi

# Verify Replica socket exists and is reachable
if [[ ! -S "${REPLICA_SOCKET}" ]]; then
    err "Replica socket not found at '${REPLICA_SOCKET}'. Run setup-mariadb-replica.sh first."
fi

if ! mysqladmin --socket="${REPLICA_SOCKET}" --user=root ping --connect-timeout=5 &>/dev/null; then
    err "MariaDB Replica is not responding on socket '${REPLICA_SOCKET}'. Check mariadb-replica.service."
fi

log "=== MariaDB replication setup started ==="

# ---------------------------------------------------------------------------
# Step 1: Idempotency check — skip if replication is already running
# ---------------------------------------------------------------------------

log "Checking current replication status on Replica..."

SLAVE_IO_RUNNING=$(mysql --socket="${REPLICA_SOCKET}" --user=root \
    -sNe "SHOW SLAVE STATUS\G" 2>/dev/null \
    | grep "Slave_IO_Running:" | awk '{print $2}' || echo "")

SLAVE_SQL_RUNNING=$(mysql --socket="${REPLICA_SOCKET}" --user=root \
    -sNe "SHOW SLAVE STATUS\G" 2>/dev/null \
    | grep "Slave_SQL_Running:" | awk '{print $2}' || echo "")

if [[ "${SLAVE_IO_RUNNING}" == "Yes" && "${SLAVE_SQL_RUNNING}" == "Yes" ]]; then
    log "Replica is already running (Slave_IO_Running=Yes, Slave_SQL_Running=Yes) — skipping CHANGE MASTER and START SLAVE."
    SKIP_CONFIGURE=true
else
    SKIP_CONFIGURE=false
    log "Replication is not yet active — proceeding with configuration."
fi

# ---------------------------------------------------------------------------
# Step 2: Read MASTER_LOG_FILE and MASTER_LOG_POS from Primary
# ---------------------------------------------------------------------------

if [[ "${SKIP_CONFIGURE}" == "false" ]]; then
    log "Reading SHOW MASTER STATUS from Primary (via unix socket)..."

    MASTER_STATUS=$(mysql --user=root \
        -e "SHOW MASTER STATUS\G" 2>/dev/null) \
        || err "Failed to execute SHOW MASTER STATUS on Primary."

    MASTER_LOG_FILE=$(echo "${MASTER_STATUS}" | grep "File:" | awk '{print $2}')
    MASTER_LOG_POS=$(echo "${MASTER_STATUS}" | grep "Position:" | awk '{print $2}')

    if [[ -z "${MASTER_LOG_FILE}" || -z "${MASTER_LOG_POS}" ]]; then
        err "SHOW MASTER STATUS returned empty File or Position. Is binary logging enabled on the Primary?"
    fi

    log "Primary binlog: file=${MASTER_LOG_FILE}, position=${MASTER_LOG_POS}"

    # ---------------------------------------------------------------------------
    # Step 3: Configure replication on the Replica (CHANGE MASTER TO)
    # ---------------------------------------------------------------------------

    log "Configuring replication on Replica (CHANGE MASTER TO)..."

    # Stop any previous (possibly failed) slave threads before reconfiguring
    mysql --socket="${REPLICA_SOCKET}" --user=root \
        -e "STOP SLAVE;" 2>/dev/null || true

    mysql --socket="${REPLICA_SOCKET}" --user=root \
        -e "CHANGE MASTER TO
              MASTER_HOST='127.0.0.1',
              MASTER_PORT=3306,
              MASTER_USER='repl',
              MASTER_PASSWORD='${REPL_PASSWORD}',
              MASTER_LOG_FILE='${MASTER_LOG_FILE}',
              MASTER_LOG_POS=${MASTER_LOG_POS};" \
        || err "CHANGE MASTER TO failed. Check credentials and Primary binlog status."

    log "CHANGE MASTER TO applied successfully."

    # ---------------------------------------------------------------------------
    # Step 4: Start Slave
    # ---------------------------------------------------------------------------

    log "Starting Slave threads on Replica..."

    mysql --socket="${REPLICA_SOCKET}" --user=root \
        -e "START SLAVE;" \
        || err "START SLAVE failed on Replica."

    log "START SLAVE issued successfully."
fi

# ---------------------------------------------------------------------------
# Step 5: Verify replication status (poll for up to 30 seconds)
# ---------------------------------------------------------------------------

log "Verifying replication status (up to 30 seconds)..."

WAIT_SECS=30
VERIFIED=false

for i in $(seq 1 "${WAIT_SECS}"); do
    SLAVE_STATUS=$(mysql --socket="${REPLICA_SOCKET}" --user=root \
        -e "SHOW SLAVE STATUS\G" 2>/dev/null) \
        || err "Failed to read SHOW SLAVE STATUS from Replica."

    IO_RUNNING=$(echo "${SLAVE_STATUS}"  | grep "Slave_IO_Running:"  | awk '{print $2}')
    SQL_RUNNING=$(echo "${SLAVE_STATUS}" | grep "Slave_SQL_Running:" | awk '{print $2}')
    SECONDS_BEHIND=$(echo "${SLAVE_STATUS}" | grep "Seconds_Behind_Master:" | awk '{print $2}')
    LAST_IO_ERROR=$(echo "${SLAVE_STATUS}"  | grep "Last_IO_Error:"  | sed 's/.*Last_IO_Error: //')
    LAST_SQL_ERROR=$(echo "${SLAVE_STATUS}" | grep "Last_SQL_Error:" | sed 's/.*Last_SQL_Error: //')

    if [[ "${IO_RUNNING}" == "Yes" && "${SQL_RUNNING}" == "Yes" ]]; then
        log "Replication threads are running (IO=${IO_RUNNING}, SQL=${SQL_RUNNING}) after ${i}s."
        VERIFIED=true
        break
    fi

    # Surface errors early instead of waiting the full timeout
    if [[ -n "${LAST_IO_ERROR}" && "${LAST_IO_ERROR}" != "" ]]; then
        err "Slave IO error: ${LAST_IO_ERROR}"
    fi
    if [[ -n "${LAST_SQL_ERROR}" && "${LAST_SQL_ERROR}" != "" ]]; then
        err "Slave SQL error: ${LAST_SQL_ERROR}"
    fi

    sleep 1
done

if [[ "${VERIFIED}" == "false" ]]; then
    err "Replication did not become active within ${WAIT_SECS}s. IO=${IO_RUNNING}, SQL=${SQL_RUNNING}. Check 'SHOW SLAVE STATUS\\G' on the Replica."
fi

# Verify Seconds_Behind_Master = 0 (allow NULL → freshly-started, treat as 0)
if [[ "${SECONDS_BEHIND}" != "0" && "${SECONDS_BEHIND}" != "NULL" ]]; then
    warn "Seconds_Behind_Master=${SECONDS_BEHIND} (not 0). Replication is catching up — this may be normal right after startup."
else
    log "Seconds_Behind_Master=${SECONDS_BEHIND} — OK"
fi

# ---------------------------------------------------------------------------
# Step 6: Verify replicated data — SELECT COUNT(*) FROM grp_61_db.prodotto
# ---------------------------------------------------------------------------

log "Verifying replicated data: SELECT COUNT(*) FROM grp_61_db.prodotto on Replica..."

# Give the SQL thread a moment to apply any pending events
sleep 2

PRODOTTO_COUNT=$(mysql --socket="${REPLICA_SOCKET}" --user=root \
    grp_61_db \
    -sNe "SELECT COUNT(*) FROM prodotto;" 2>/dev/null) \
    || err "Could not query 'grp_61_db.prodotto' on Replica. Has the dump been imported on the Primary?"

if [[ "${PRODOTTO_COUNT}" -ne 7 ]]; then
    err "Expected 7 rows in 'grp_61_db.prodotto' on Replica, found ${PRODOTTO_COUNT}. Replication may not have fully applied the dump yet."
fi

log "grp_61_db.prodotto on Replica: ${PRODOTTO_COUNT} rows — OK"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log ""
log "=== MariaDB replication setup completed successfully ==="
log "  Primary              : 127.0.0.1:3306"
log "  Replica socket       : ${REPLICA_SOCKET}"
log "  MASTER_LOG_FILE      : ${MASTER_LOG_FILE:-<already configured>}"
log "  MASTER_LOG_POS       : ${MASTER_LOG_POS:-<already configured>}"
log "  Slave_IO_Running     : Yes"
log "  Slave_SQL_Running    : Yes"
log "  Seconds_Behind_Master: ${SECONDS_BEHIND}"
log "  prodotto rows (Replica): ${PRODOTTO_COUNT}"
log ""
log "Next step: configure firewall iptables with infra/setup-firewall.sh (task 3.1)"
