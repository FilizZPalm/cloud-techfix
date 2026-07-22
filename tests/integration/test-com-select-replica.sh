#!/usr/bin/env bash
# tests/integration/test-com-select-replica.sh
#
# Integration test — Property 13:
#   HPA replica count ∈ [2, 10] durante tutto il load test
#
# Additionally verifies:
#   Com_select increment on MariaDB Replica during load test
#   (proves read queries are hitting the Replica, not just Primary)
#
# Validates: Requirements 6.4, 12.5
#
# What this test does:
#   1. Records Com_select counter on MariaDB Replica BEFORE the load test
#   2. Starts k6 load test in background (50 VUs, 3 minutes)
#   3. Takes 100 HPA replica count snapshots (~every 2s during the test)
#   4. Verifies ALL snapshot values are in range [2, 10]
#   5. Records Com_select counter on Replica AFTER the load test
#   6. Verifies Com_select increased (proving reads hit the replica)
#
# Prerequisites:
#   - k6 installed and in PATH
#   - kubectl configured (KUBECONFIG set or default k3s path)
#   - mysql client installed
#   - MariaDB Replica running on /var/run/mysqld/mysqld-replica.sock
#   - k6 load test script at scripts/load-test.js
#   - HPA and Laravel deployment active in namespace 'techfix'
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-com-select-replica.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPLICA_SOCKET="${REPLICA_SOCKET:-/var/run/mysqld/mysqld-replica.sock}"
NAMESPACE="${NAMESPACE:-techfix}"
HPA_NAME="${HPA_NAME:-laravel-hpa}"
K6_SCRIPT="${K6_SCRIPT:-scripts/load-test.js}"
SNAPSHOT_COUNT=100
SNAPSHOT_INTERVAL=2   # seconds between snapshots (~200s total ≈ 3min20s)

# HPA bounds from requirements 6.4
HPA_MIN=2
HPA_MAX=10

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0

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
    if [[ -n "${K6_PID:-}" ]] && kill -0 "${K6_PID}" 2>/dev/null; then
        info "Stopping k6 process (PID ${K6_PID})..."
        kill "${K6_PID}" 2>/dev/null || true
        wait "${K6_PID}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "Pre-flight Checks"

# Check k6
if ! command -v k6 &>/dev/null; then
    fail "k6 not found in PATH"
    exit 1
fi
info "k6 found: $(k6 version 2>/dev/null | head -1)"

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    fail "kubectl not found in PATH"
    exit 1
fi
info "kubectl found"

# Check mysql client
if ! command -v mysql &>/dev/null; then
    fail "mysql client not found in PATH"
    exit 1
fi
info "mysql client found"

# Check replica socket exists
if [[ ! -S "${REPLICA_SOCKET}" ]]; then
    fail "Replica socket not found: ${REPLICA_SOCKET}"
    exit 1
fi
info "Replica socket exists: ${REPLICA_SOCKET}"

# Check k6 script exists
if [[ ! -f "${K6_SCRIPT}" ]]; then
    fail "k6 script not found: ${K6_SCRIPT}"
    exit 1
fi
info "k6 script found: ${K6_SCRIPT}"

# Check HPA exists
if ! kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    fail "HPA '${HPA_NAME}' not found in namespace '${NAMESPACE}'"
    exit 1
fi
info "HPA '${HPA_NAME}' found in namespace '${NAMESPACE}'"

# ---------------------------------------------------------------------------
# Helper: get Com_select from Replica
# ---------------------------------------------------------------------------

get_com_select() {
    local value
    value=$(mysql --socket="${REPLICA_SOCKET}" -u root -N \
        -e "SHOW GLOBAL STATUS LIKE 'Com_select';" 2>/dev/null \
        | awk '{print $2}')
    echo "${value}"
}

# ---------------------------------------------------------------------------
# Helper: get current HPA replica count
# ---------------------------------------------------------------------------

get_replicas() {
    local replicas
    replicas=$(kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
    echo "${replicas}"
}

# ---------------------------------------------------------------------------
# STEP 1: Record Com_select BEFORE load test
# ---------------------------------------------------------------------------

header "STEP 1: Record Com_select BEFORE load test"

COM_SELECT_BEFORE=$(get_com_select)

if [[ -z "${COM_SELECT_BEFORE}" ]] || ! [[ "${COM_SELECT_BEFORE}" =~ ^[0-9]+$ ]]; then
    fail "Could not read Com_select from Replica (got: '${COM_SELECT_BEFORE}')"
    exit 1
fi

info "Com_select BEFORE: ${COM_SELECT_BEFORE}"

# ---------------------------------------------------------------------------
# STEP 2: Start k6 load test in background
# ---------------------------------------------------------------------------

header "STEP 2: Start k6 load test in background"

k6 run "${K6_SCRIPT}" --quiet &>/dev/null &
K6_PID=$!

info "k6 started with PID ${K6_PID}"

# Give k6 a few seconds to spin up VUs and start generating load
sleep 5

# Verify k6 is still running
if ! kill -0 "${K6_PID}" 2>/dev/null; then
    fail "k6 process exited prematurely"
    exit 1
fi

info "k6 confirmed running after 5s warmup"

# ---------------------------------------------------------------------------
# STEP 3: Take 100 HPA replica count snapshots
# ---------------------------------------------------------------------------

header "STEP 3: Collecting ${SNAPSHOT_COUNT} HPA replica snapshots (interval: ${SNAPSHOT_INTERVAL}s)"

declare -a SNAPSHOTS=()
OUT_OF_RANGE=0

for i in $(seq 1 ${SNAPSHOT_COUNT}); do
    replicas=$(get_replicas)

    # Handle empty or non-numeric values gracefully
    if [[ -z "${replicas}" ]] || ! [[ "${replicas}" =~ ^[0-9]+$ ]]; then
        info "Snapshot ${i}/${SNAPSHOT_COUNT}: could not read replicas (got: '${replicas}'), retrying..."
        sleep "${SNAPSHOT_INTERVAL}"
        continue
    fi

    SNAPSHOTS+=("${replicas}")

    # Check bounds
    if (( replicas < HPA_MIN || replicas > HPA_MAX )); then
        OUT_OF_RANGE=$((OUT_OF_RANGE + 1))
        info "Snapshot ${i}/${SNAPSHOT_COUNT}: REPLICAS=${replicas} ⚠️  OUT OF RANGE [${HPA_MIN}, ${HPA_MAX}]"
    else
        # Print progress every 10 snapshots
        if (( i % 10 == 0 )); then
            info "Snapshot ${i}/${SNAPSHOT_COUNT}: REPLICAS=${replicas} ✓"
        fi
    fi

    sleep "${SNAPSHOT_INTERVAL}"
done

info "Collected ${#SNAPSHOTS[@]} valid snapshots out of ${SNAPSHOT_COUNT} attempts"

# ---------------------------------------------------------------------------
# STEP 4: Verify ALL snapshots are in range [2, 10]
# Property 13: HPA replica count ∈ [2, 10] durante tutto il load test
# ---------------------------------------------------------------------------

header "STEP 4: Verify HPA replica count ∈ [${HPA_MIN}, ${HPA_MAX}]"

if [[ ${#SNAPSHOTS[@]} -eq 0 ]]; then
    fail "No valid snapshots collected — cannot verify Property 13"
else
    if [[ ${OUT_OF_RANGE} -eq 0 ]]; then
        # Find min and max for reporting
        min_val=${SNAPSHOTS[0]}
        max_val=${SNAPSHOTS[0]}
        for val in "${SNAPSHOTS[@]}"; do
            (( val < min_val )) && min_val=${val}
            (( val > max_val )) && max_val=${val}
        done
        pass "Property 13: All ${#SNAPSHOTS[@]} snapshots in [${HPA_MIN}, ${HPA_MAX}] — range observed: [${min_val}, ${max_val}]"
    else
        fail "Property 13: ${OUT_OF_RANGE} snapshot(s) out of range [${HPA_MIN}, ${HPA_MAX}]"
        # Print all out-of-range values for debugging
        for idx in "${!SNAPSHOTS[@]}"; do
            val=${SNAPSHOTS[$idx]}
            if (( val < HPA_MIN || val > HPA_MAX )); then
                info "  → snapshot $((idx+1)): REPLICAS=${val}"
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# STEP 5: Wait for k6 to finish, then record Com_select AFTER
# ---------------------------------------------------------------------------

header "STEP 5: Wait for k6 to finish and record Com_select AFTER"

# Wait for k6 to complete (it runs for 3 minutes)
if kill -0 "${K6_PID}" 2>/dev/null; then
    info "Waiting for k6 to complete (PID ${K6_PID})..."
    wait "${K6_PID}" 2>/dev/null || true
fi

info "k6 load test completed"

# Small delay to allow any in-flight queries to complete
sleep 3

COM_SELECT_AFTER=$(get_com_select)

if [[ -z "${COM_SELECT_AFTER}" ]] || ! [[ "${COM_SELECT_AFTER}" =~ ^[0-9]+$ ]]; then
    fail "Could not read Com_select from Replica after load test (got: '${COM_SELECT_AFTER}')"
else
    info "Com_select AFTER: ${COM_SELECT_AFTER}"
fi

# ---------------------------------------------------------------------------
# STEP 6: Verify Com_select increased (Requirement 12.5)
# ---------------------------------------------------------------------------

header "STEP 6: Verify Com_select increment on Replica"

if [[ -n "${COM_SELECT_AFTER}" ]] && [[ "${COM_SELECT_AFTER}" =~ ^[0-9]+$ ]]; then
    DELTA=$((COM_SELECT_AFTER - COM_SELECT_BEFORE))
    info "Com_select delta: ${DELTA} (${COM_SELECT_BEFORE} → ${COM_SELECT_AFTER})"

    if (( DELTA > 0 )); then
        pass "Requirement 12.5: Com_select increased by ${DELTA} — reads are hitting the Replica"
    else
        fail "Requirement 12.5: Com_select did NOT increase (delta=${DELTA}) — reads may not be routed to Replica"
    fi
else
    fail "Requirement 12.5: Could not compute Com_select delta"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TOTAL=$((PASSED + FAILED))

header "TEST SUMMARY"
echo ""
echo "  Total:  ${TOTAL}"
echo -e "  Passed: \033[32m${PASSED}\033[0m"
echo -e "  Failed: \033[31m${FAILED}\033[0m"
echo ""

if [[ "${FAILED}" -gt 0 ]]; then
    echo -e "  \033[31m✗ ${FAILED} check(s) FAILED\033[0m"
    echo ""
    exit 1
else
    echo -e "  \033[32m✓ All checks PASSED\033[0m"
    echo ""
    exit 0
fi
