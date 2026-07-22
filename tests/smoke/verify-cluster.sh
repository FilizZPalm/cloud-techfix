#!/usr/bin/env bash
# tests/smoke/verify-cluster.sh
#
# Comprehensive smoke test suite that validates the entire TechFix cluster
# deployment. Runs 10 checks covering database, Kubernetes, TLS, security,
# and network isolation.
#
# Requirements: 2.1, 5.1, 7.2, 7.3, 8.4, 9.1, 10.1
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/smoke/verify-cluster.sh
#
# Exit codes:
#   0 — all smoke tests passed
#   1 — one or more smoke tests failed (see output for details)

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MARIADB_PRIMARY_HOST="${MARIADB_PRIMARY_HOST:-127.0.0.1}"
MARIADB_PRIMARY_PORT="${MARIADB_PRIMARY_PORT:-3306}"
MARIADB_REPLICA_HOST="${MARIADB_REPLICA_HOST:-127.0.0.1}"
MARIADB_REPLICA_PORT="${MARIADB_REPLICA_PORT:-3307}"
MARIADB_REPLICA_SOCKET="${MARIADB_REPLICA_SOCKET:-/var/run/mysqld/mysqld-replica.sock}"
DB_USER="${DB_USER:-techfix}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-grp_61_db}"
DOMAIN="${DOMAIN:-techfix.local}"
NAMESPACE="${NAMESPACE:-techfix}"

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0
TOTAL=10

pass() { echo -e "  \033[32m[PASS]\033[0m $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  \033[31m[FAIL]\033[0m $*"; FAILED=$((FAILED + 1)); }
info() { echo -e "  [INFO] $*"; }
header() { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix Cluster Smoke Tests"
echo ""
echo "  Domain:    ${DOMAIN}"
echo "  Namespace: ${NAMESPACE}"
echo "  Primary:   ${MARIADB_PRIMARY_HOST}:${MARIADB_PRIMARY_PORT}"
echo "  Replica:   ${MARIADB_REPLICA_HOST}:${MARIADB_REPLICA_PORT}"
echo ""

# ---------------------------------------------------------------------------
# ST-01: MariaDB Primary responds and contains 7 products
# Requirements: 5.1
# ---------------------------------------------------------------------------

header "ST-01: MariaDB Primary — connection and data"

product_count=""
if [[ -n "${DB_PASSWORD}" ]]; then
    product_count=$(mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" \
        -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        -N -e "SELECT COUNT(*) FROM prodotto;" 2>/dev/null || true)
else
    product_count=$(mysql -h "${MARIADB_PRIMARY_HOST}" -P "${MARIADB_PRIMARY_PORT}" \
        -u root "${DB_NAME}" \
        -N -e "SELECT COUNT(*) FROM prodotto;" 2>/dev/null || true)
fi

product_count=$(echo "${product_count}" | tr -d '[:space:]')

if [[ "${product_count}" == "7" ]]; then
    pass "MariaDB Primary on ${MARIADB_PRIMARY_HOST}:${MARIADB_PRIMARY_PORT} — 7 products found"
else
    fail "MariaDB Primary on ${MARIADB_PRIMARY_HOST}:${MARIADB_PRIMARY_PORT} — expected 7 products, got '${product_count}'"
fi

# ---------------------------------------------------------------------------
# ST-02: MariaDB Replica responds, Slave_IO_Running: Yes
# Requirements: 5.1
# ---------------------------------------------------------------------------

header "ST-02: MariaDB Replica — replication status"

slave_io=""
if [[ -S "${MARIADB_REPLICA_SOCKET}" ]]; then
    slave_io=$(mysql --socket="${MARIADB_REPLICA_SOCKET}" -u root \
        -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Slave_IO_Running:" | awk '{print $2}' || true)
else
    slave_io=$(mysql -h "${MARIADB_REPLICA_HOST}" -P "${MARIADB_REPLICA_PORT}" -u root \
        -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Slave_IO_Running:" | awk '{print $2}' || true)
fi

slave_io=$(echo "${slave_io}" | tr -d '[:space:]')

if [[ "${slave_io}" == "Yes" ]]; then
    pass "MariaDB Replica on ${MARIADB_REPLICA_HOST}:${MARIADB_REPLICA_PORT} — Slave_IO_Running: Yes"
else
    fail "MariaDB Replica — Slave_IO_Running: '${slave_io}' (expected 'Yes')"
fi

# ---------------------------------------------------------------------------
# ST-03: kubectl get nodes — node in Ready state
# Requirements: 2.1
# ---------------------------------------------------------------------------

header "ST-03: Kubernetes node status"

node_status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || true)

if echo "${node_status}" | grep -q "Ready"; then
    node_name=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}' | head -1)
    pass "Node '${node_name}' is in Ready state"
else
    fail "No Kubernetes node in Ready state (got: '${node_status}')"
fi

# ---------------------------------------------------------------------------
# ST-04: Traefik pod Running, ports 80/443 listening
# Requirements: 7.2, 7.3
# ---------------------------------------------------------------------------

header "ST-04: Traefik Ingress Controller"

traefik_running=false
traefik_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep traefik || true)

if echo "${traefik_pods}" | grep -q "Running"; then
    traefik_running=true
fi

port_80=$(ss -tlnp 2>/dev/null | grep ":80 " || true)
port_443=$(ss -tlnp 2>/dev/null | grep ":443 " || true)

if [[ "${traefik_running}" == "true" ]] && [[ -n "${port_80}" ]] && [[ -n "${port_443}" ]]; then
    pass "Traefik pod Running, ports 80 and 443 listening"
else
    details=""
    [[ "${traefik_running}" != "true" ]] && details="${details} traefik-not-running"
    [[ -z "${port_80}" ]] && details="${details} port-80-not-listening"
    [[ -z "${port_443}" ]] && details="${details} port-443-not-listening"
    fail "Traefik check failed:${details}"
fi

# ---------------------------------------------------------------------------
# ST-05: TLS certificate present on techfix.local:443
# Requirements: 7.3
# ---------------------------------------------------------------------------

header "ST-05: TLS certificate verification"

cert_output=$(echo | openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null || true)
cert_subject=$(echo "${cert_output}" | openssl x509 -noout -subject 2>/dev/null || true)

if [[ -n "${cert_subject}" ]]; then
    pass "TLS certificate present — ${cert_subject}"
else
    fail "No TLS certificate found on ${DOMAIN}:443"
fi

# ---------------------------------------------------------------------------
# ST-06: HTTP → HTTPS redirect (301)
# Requirements: 7.2
# ---------------------------------------------------------------------------

header "ST-06: HTTP to HTTPS redirect"

http_code=$(curl -s -o /dev/null -w "%{http_code}" --resolve "${DOMAIN}:80:127.0.0.1" \
    "http://${DOMAIN}/" --max-time 10 2>/dev/null || true)

if [[ "${http_code}" == "301" ]]; then
    pass "HTTP request returns 301 redirect to HTTPS"
else
    fail "HTTP request returned ${http_code} (expected 301)"
fi

# ---------------------------------------------------------------------------
# ST-07: HTTPS returns HTTP 200
# Requirements: 7.3
# ---------------------------------------------------------------------------

header "ST-07: HTTPS connectivity"

https_code=$(curl -sk -o /dev/null -w "%{http_code}" --resolve "${DOMAIN}:443:127.0.0.1" \
    "https://${DOMAIN}/" --max-time 10 2>/dev/null || true)

if [[ "${https_code}" == "200" ]]; then
    pass "HTTPS request returns HTTP 200"
else
    fail "HTTPS request returned ${https_code} (expected 200)"
fi

# ---------------------------------------------------------------------------
# ST-08: Laravel container runs as uid=1001
# Requirements: 9.1
# ---------------------------------------------------------------------------

header "ST-08: Container SecurityContext — UID"

container_uid=$(kubectl exec -n "${NAMESPACE}" deploy/laravel-deployment -- id -u 2>/dev/null || true)
container_uid=$(echo "${container_uid}" | tr -d '[:space:]')

if [[ "${container_uid}" == "1001" ]]; then
    pass "Laravel container runs as uid=1001"
else
    fail "Laravel container uid='${container_uid}' (expected 1001)"
fi

# ---------------------------------------------------------------------------
# ST-09: NetworkPolicy blocks egress to external IPs
# Requirements: 8.4
# ---------------------------------------------------------------------------

header "ST-09: NetworkPolicy — egress blocked"

# Attempt to curl an external IP from inside the Laravel pod.
# The NetworkPolicy should block this. We expect a timeout or connection refused.
egress_result=$(kubectl exec -n "${NAMESPACE}" deploy/laravel-deployment -- \
    curl -s -o /dev/null -w "%{http_code}" http://8.8.8.8 --max-time 3 2>&1 || true)

# A successful block means curl exits with an error (timeout/connection refused)
# or returns 000 (no response). If we get a real HTTP code (like 200, 301), it's not blocked.
if [[ "${egress_result}" == "000" ]] || echo "${egress_result}" | grep -qiE "(timed out|connection refused|couldn't connect|exit code|command terminated)"; then
    pass "Egress to 8.8.8.8 blocked by NetworkPolicy"
else
    fail "Egress to 8.8.8.8 NOT blocked — got response: '${egress_result}'"
fi

# ---------------------------------------------------------------------------
# ST-10: Kubernetes Secret values are base64-encoded, not plaintext
# Requirements: 10.1
# ---------------------------------------------------------------------------

header "ST-10: Kubernetes Secrets — base64 encoding"

secret_yaml=$(kubectl get secret techfix-db-secret -n "${NAMESPACE}" -o yaml 2>/dev/null || true)

if [[ -z "${secret_yaml}" ]]; then
    fail "Secret 'techfix-db-secret' not found in namespace ${NAMESPACE}"
else
    # Check that the 'data' section exists (base64-encoded values)
    # and that no plaintext passwords appear directly
    has_data=$(echo "${secret_yaml}" | grep "^data:" || true)
    # Try to decode one value to confirm it's valid base64
    db_password_b64=$(echo "${secret_yaml}" | grep "DB_PASSWORD:" | awk '{print $2}' || true)

    if [[ -n "${has_data}" ]] && [[ -n "${db_password_b64}" ]]; then
        # Verify it decodes correctly (valid base64)
        decoded=$(echo "${db_password_b64}" | base64 -d 2>/dev/null || true)
        if [[ -n "${decoded}" ]]; then
            pass "Secret 'techfix-db-secret' contains base64-encoded values (not plaintext)"
        else
            fail "Secret 'techfix-db-secret' data does not appear to be valid base64"
        fi
    else
        fail "Secret 'techfix-db-secret' missing 'data' section or DB_PASSWORD key"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "SMOKE TEST SUMMARY"
echo ""
echo "  Total:  ${TOTAL}"
echo -e "  Passed: \033[32m${PASSED}\033[0m"
echo -e "  Failed: \033[31m${FAILED}\033[0m"
echo ""

if [[ "${FAILED}" -gt 0 ]]; then
    echo -e "  \033[31m✗ ${FAILED} smoke test(s) FAILED\033[0m"
    echo ""
    exit 1
else
    echo -e "  \033[32m✓ All ${TOTAL} smoke tests PASSED\033[0m"
    echo ""
    exit 0
fi
