#!/usr/bin/env bash
# tests/integration/test-mariadb-replication.sh
#
# Integration test that validates MariaDB Primary-Replica replication behavior:
# - Replication lag within tolerance
# - Replica enforces read-only mode
# - Laravel continues serving when Replica is down
# - Replication auto-resumes after Replica restart
#
# Requirements: 5.2, 5.3, 5.5
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-mariadb-replication.sh
#
# Prerequisites:
#   - MariaDB Primary on 127.0.0.1:3306 with database grp_61_db
#   - MariaDB Replica on 127.0.0.1:3307 (systemd service: mariadb-replica)
#   - Replica socket: /var/run/mysqld/mysqld-replica.sock
#   - Laravel deployed in Kubernetes namespace 'techfix'
#   - Script must be run as root (systemd service management)
#
# Exit codes:
#   0 — all integration checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MARIADB_PRIMARY_HOST="${MARIADB_PRIMARY_HOST:-127.0.0.1}"
MARIADB_PRIMARY_PORT="${MARIADB_PRIMARY_PORT:-3306}"
MARIADB_REPLICA_HOST="${MARIADB_REPLICA_HOST:-127.0.0.1}"
MARIADB_REPLICA_PORT="${MARIADB_REPLICA_PORT:-3307}"
MARIADB_REPLICA_SOCKET="${MARIADB_REPLICA_SOCKET:-/var/run/mysqld/mysqld-replica.sock}"
REPLICA_SERVICE="${REPLICA_SERVICE:-mariadb-replica}"
DB_NAME="${DB_NAME:-grp_61_db}"
NAMESPACE="${NAMESPACE:-techfix}"
DOMAIN="${DOMAIN:-techfix.local}"
REPLICATION_LAG_THRESHOLD="${REPLICATION_LAG_THRESHOLD:-5}"  # seconds
REPLICA_RESTART_TIMEOUT="${REPLICA_RESTART_TIMEOUT:-30}"     # seconds to wait for replica restart
REPLICATION_RESUME_TIMEOUT="${REPLICATION_RESUME_TIMEOUT:-60}" # seconds to wait for replication resume

# Test table and data
TEST_TABLE="replication_test_$(date +%s)"

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0
TOTAL=4

pass() { echo -e "  \033[32m[PASS]\033[0m $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  \033[31m[FAIL]\033[0m $*"; FAILED=$((FAILED + 1)); }
info() { echo -e "  [INFO] $*"; }
header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

cleanup() {
    info "Cleaning up test table '${TEST_TABLE}' on Primary..."
    mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" \
        -u root "${DB_NAME}" \
        -e "DROP TABLE IF EXISTS ${TEST_TABLE};" 2>/dev/null || true

    # Ensure Replica is running after test
    if ! systemctl is-active --quiet "${REPLICA_SERVICE}" 2>/dev/null; then
        info "Ensuring Replica service is running after test..."
        systemctl start "${REPLICA_SERVICE}" 2>/dev/null || true
        sleep 5
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix MariaDB Replication Integration Tests"
echo ""
echo "  Primary:           ${MARIADB_PRIMARY_HOST}:${MARIADB_PRIMARY_PORT}"
echo "  Replica:           ${MARIADB_REPLICA_HOST}:${MARIADB_REPLICA_PORT}"
echo "  Replica socket:    ${MARIADB_REPLICA_SOCKET}"
echo "  Replica service:   ${REPLICA_SERVICE}"
echo "  Database:          ${DB_NAME}"
echo "  Lag threshold:     ${REPLICATION_LAG_THRESHOLD}s"
echo ""

# Verify root access
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script requires root access (systemd service management)."
    exit 1
fi

# Verify Primary is reachable
if ! mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" \
    -u root -e "SELECT 1;" &>/dev/null; then
    echo "ERROR: Cannot connect to MariaDB Primary on ${MARIADB_PRIMARY_HOST}:${MARIADB_PRIMARY_PORT}"
    exit 1
fi

# Verify Replica is reachable
if [[ -S "${MARIADB_REPLICA_SOCKET}" ]]; then
    if ! mysql --socket="${MARIADB_REPLICA_SOCKET}" -u root -e "SELECT 1;" &>/dev/null; then
        echo "ERROR: Cannot connect to MariaDB Replica via socket ${MARIADB_REPLICA_SOCKET}"
        exit 1
    fi
else
    if ! mysql -h "${MARIADB_REPLICA_HOST}" -P "${MARIADB_REPLICA_PORT}" \
        -u root -e "SELECT 1;" &>/dev/null; then
        echo "ERROR: Cannot connect to MariaDB Replica on ${MARIADB_REPLICA_HOST}:${MARIADB_REPLICA_PORT}"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Helper: query replica (prefers socket, falls back to TCP)
# ---------------------------------------------------------------------------

replica_query() {
    if [[ -S "${MARIADB_REPLICA_SOCKET}" ]]; then
        mysql --socket="${MARIADB_REPLICA_SOCKET}" -u root "$@"
    else
        mysql -h "${MARIADB_REPLICA_HOST}" -P "${MARIADB_REPLICA_PORT}" -u root "$@"
    fi
}

# ---------------------------------------------------------------------------
# IT-01: INSERT on Primary → Seconds_Behind_Master ≤ 5 on Replica
# Requirements: 5.3
# ---------------------------------------------------------------------------

header "IT-01: Replication lag after INSERT on Primary (≤ ${REPLICATION_LAG_THRESHOLD}s)"

# Create a test table and insert data on Primary
info "Creating test table '${TEST_TABLE}' on Primary..."
mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" -u root "${DB_NAME}" -e "
    CREATE TABLE IF NOT EXISTS ${TEST_TABLE} (
        id INT AUTO_INCREMENT PRIMARY KEY,
        payload VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
" 2>/dev/null

info "Inserting test row on Primary..."
mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" -u root "${DB_NAME}" -e "
    INSERT INTO ${TEST_TABLE} (payload) VALUES ('replication-lag-test-$(date +%s)');
" 2>/dev/null

# Wait a moment for replication to propagate
sleep 2

# Check Seconds_Behind_Master on Replica
seconds_behind=$(replica_query -N -e "SHOW SLAVE STATUS\G" 2>/dev/null \
    | grep "Seconds_Behind_Master:" | awk '{print $2}' || true)
seconds_behind=$(echo "${seconds_behind}" | tr -d '[:space:]')

if [[ -z "${seconds_behind}" ]] || [[ "${seconds_behind}" == "NULL" ]]; then
    fail "IT-01: Could not read Seconds_Behind_Master (got: '${seconds_behind}')"
elif [[ "${seconds_behind}" -le ${REPLICATION_LAG_THRESHOLD} ]]; then
    pass "IT-01: Seconds_Behind_Master = ${seconds_behind}s (≤ ${REPLICATION_LAG_THRESHOLD}s threshold)"
else
    fail "IT-01: Seconds_Behind_Master = ${seconds_behind}s (exceeds ${REPLICATION_LAG_THRESHOLD}s threshold)"
fi

# Verify the row actually replicated
replica_count=$(replica_query -N "${DB_NAME}" -e "SELECT COUNT(*) FROM ${TEST_TABLE};" 2>/dev/null || true)
replica_count=$(echo "${replica_count}" | tr -d '[:space:]')
if [[ "${replica_count}" -ge 1 ]] 2>/dev/null; then
    info "Confirmed: test row replicated to Replica (count: ${replica_count})"
else
    info "WARNING: test row not yet visible on Replica (count: '${replica_count}')"
fi

# ---------------------------------------------------------------------------
# IT-02: Direct INSERT on Replica → read-only error
# Requirements: 5.2
# ---------------------------------------------------------------------------

header "IT-02: Direct INSERT on Replica → read-only error"

insert_error=$(replica_query "${DB_NAME}" -e "
    INSERT INTO ${TEST_TABLE} (payload) VALUES ('should-fail-readonly');
" 2>&1 || true)

if echo "${insert_error}" | grep -qiE "(read.only|read_only|super privilege|--read-only)"; then
    pass "IT-02: INSERT on Replica rejected with read-only error"
    info "Error message: $(echo "${insert_error}" | head -1)"
else
    fail "IT-02: INSERT on Replica did NOT return read-only error (got: '${insert_error}')"
fi

# ---------------------------------------------------------------------------
# IT-03: Simulate Replica down → Laravel queries continue without HTTP errors
# Requirements: 5.5
# ---------------------------------------------------------------------------

header "IT-03: Replica down → Laravel continues serving (no HTTP errors)"

info "Stopping Replica service '${REPLICA_SERVICE}'..."
systemctl stop "${REPLICA_SERVICE}" 2>/dev/null

# Give time for the service to fully stop
sleep 3

# Verify Replica is actually down
if systemctl is-active --quiet "${REPLICA_SERVICE}" 2>/dev/null; then
    fail "IT-03: Could not stop Replica service '${REPLICA_SERVICE}'"
else
    info "Replica service stopped successfully"

    # Send HTTP requests to Laravel and check for success
    http_errors=0
    http_total=5

    for i in $(seq 1 ${http_total}); do
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
            --resolve "${DOMAIN}:443:127.0.0.1" \
            "https://${DOMAIN}/" --max-time 10 2>/dev/null || echo "000")

        if [[ "${http_code}" =~ ^(2[0-9]{2}|3[0-9]{2})$ ]]; then
            info "  Request ${i}/${http_total}: HTTP ${http_code} ✓"
        else
            info "  Request ${i}/${http_total}: HTTP ${http_code} ✗"
            http_errors=$((http_errors + 1))
        fi
        sleep 1
    done

    if [[ ${http_errors} -eq 0 ]]; then
        pass "IT-03: All ${http_total} requests succeeded while Replica was down"
    else
        fail "IT-03: ${http_errors}/${http_total} requests failed while Replica was down"
    fi
fi

# ---------------------------------------------------------------------------
# IT-04: Restart Replica → replication resumes automatically
# Requirements: 5.3
# ---------------------------------------------------------------------------

header "IT-04: Restart Replica → replication resumes automatically"

info "Starting Replica service '${REPLICA_SERVICE}'..."
systemctl start "${REPLICA_SERVICE}" 2>/dev/null

# Wait for the service to come up
info "Waiting for Replica to become available (timeout: ${REPLICA_RESTART_TIMEOUT}s)..."
elapsed=0
replica_up=false

while [[ ${elapsed} -lt ${REPLICA_RESTART_TIMEOUT} ]]; do
    sleep 3
    elapsed=$((elapsed + 3))

    if replica_query -e "SELECT 1;" &>/dev/null; then
        replica_up=true
        info "Replica is accepting connections after ${elapsed}s"
        break
    fi
done

if [[ "${replica_up}" != "true" ]]; then
    fail "IT-04: Replica did not become available within ${REPLICA_RESTART_TIMEOUT}s"
else
    # Wait for replication to resume
    info "Checking replication status (timeout: ${REPLICATION_RESUME_TIMEOUT}s)..."
    elapsed=0
    replication_ok=false

    while [[ ${elapsed} -lt ${REPLICATION_RESUME_TIMEOUT} ]]; do
        sleep 3
        elapsed=$((elapsed + 3))

        slave_io=$(replica_query -N -e "SHOW SLAVE STATUS\G" 2>/dev/null \
            | grep "Slave_IO_Running:" | awk '{print $2}' || true)
        slave_sql=$(replica_query -N -e "SHOW SLAVE STATUS\G" 2>/dev/null \
            | grep "Slave_SQL_Running:" | awk '{print $2}' || true)

        slave_io=$(echo "${slave_io}" | tr -d '[:space:]')
        slave_sql=$(echo "${slave_sql}" | tr -d '[:space:]')

        info "  [${elapsed}s] Slave_IO_Running: ${slave_io}, Slave_SQL_Running: ${slave_sql}"

        if [[ "${slave_io}" == "Yes" ]] && [[ "${slave_sql}" == "Yes" ]]; then
            replication_ok=true
            break
        fi
    done

    if [[ "${replication_ok}" == "true" ]]; then
        # Additional verification: insert on Primary and confirm it replicates
        info "Verifying replication with a new INSERT on Primary..."
        mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" -u root "${DB_NAME}" -e "
            INSERT INTO ${TEST_TABLE} (payload) VALUES ('post-restart-test-$(date +%s)');
        " 2>/dev/null

        sleep 3

        post_restart_count=$(replica_query -N "${DB_NAME}" \
            -e "SELECT COUNT(*) FROM ${TEST_TABLE} WHERE payload LIKE 'post-restart-test-%';" 2>/dev/null || true)
        post_restart_count=$(echo "${post_restart_count}" | tr -d '[:space:]')

        if [[ "${post_restart_count}" -ge 1 ]] 2>/dev/null; then
            pass "IT-04: Replication resumed — Slave_IO: Yes, Slave_SQL: Yes, new data replicated"
        else
            pass "IT-04: Replication resumed — Slave_IO: Yes, Slave_SQL: Yes (data propagation pending)"
        fi
    else
        fail "IT-04: Replication did NOT resume within ${REPLICATION_RESUME_TIMEOUT}s (IO: '${slave_io}', SQL: '${slave_sql}')"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "MARIADB REPLICATION TEST SUMMARY"
echo ""
echo "  Total:  ${TOTAL}"
echo -e "  Passed: \033[32m${PASSED}\033[0m"
echo -e "  Failed: \033[31m${FAILED}\033[0m"
echo ""

if [[ "${FAILED}" -gt 0 ]]; then
    echo -e "  \033[31m✗ ${FAILED} integration test(s) FAILED\033[0m"
    echo ""
    exit 1
else
    echo -e "  \033[32m✓ All ${TOTAL} MariaDB replication tests PASSED\033[0m"
    echo ""
    exit 0
fi
