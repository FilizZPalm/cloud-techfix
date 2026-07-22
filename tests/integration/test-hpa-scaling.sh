#!/usr/bin/env bash
# tests/integration/test-hpa-scaling.sh
#
# Integration test that validates HPA autoscaling behavior under load.
# Starts k6 load test in background, monitors HPA replica count for scale-up,
# then verifies scale-down after load stops.
#
# Requirements: 12.2, 12.3, 12.4
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-hpa-scaling.sh
#
# Prerequisites:
#   - k6 installed and in PATH
#   - kubectl configured with access to the cluster
#   - HPA 'laravel-hpa' deployed in namespace 'techfix'
#   - scripts/load-test.js present in the project root
#
# Exit codes:
#   0 — all integration checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
HPA_NAME="${HPA_NAME:-laravel-hpa}"
LOAD_TEST_SCRIPT="${LOAD_TEST_SCRIPT:-scripts/load-test.js}"
SCALE_UP_TIMEOUT="${SCALE_UP_TIMEOUT:-90}"       # seconds to wait for scale-up
SCALE_DOWN_TIMEOUT="${SCALE_DOWN_TIMEOUT:-600}"  # seconds (10 minutes) for scale-down
POLL_INTERVAL="${POLL_INTERVAL:-15}"             # seconds between HPA polls
MIN_REPLICAS="${MIN_REPLICAS:-2}"                # expected minReplicas from HPA spec
K6_OUTPUT_FILE="/tmp/k6-hpa-test-output.txt"

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
    # Kill k6 if still running
    if [[ -n "${K6_PID:-}" ]] && kill -0 "${K6_PID}" 2>/dev/null; then
        info "Stopping k6 process (PID: ${K6_PID})..."
        kill "${K6_PID}" 2>/dev/null || true
        wait "${K6_PID}" 2>/dev/null || true
    fi
    # Clean up temp file
    rm -f "${K6_OUTPUT_FILE}" 2>/dev/null || true
}

trap cleanup EXIT

get_hpa_replicas() {
    kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" --no-headers 2>/dev/null \
        | awk '{print $7}' || echo "0"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix HPA Scaling Integration Test"
echo ""
echo "  Namespace:          ${NAMESPACE}"
echo "  HPA:                ${HPA_NAME}"
echo "  Load test script:   ${LOAD_TEST_SCRIPT}"
echo "  Scale-up timeout:   ${SCALE_UP_TIMEOUT}s"
echo "  Scale-down timeout: ${SCALE_DOWN_TIMEOUT}s"
echo "  Poll interval:      ${POLL_INTERVAL}s"
echo ""

# Verify prerequisites
if ! command -v k6 &>/dev/null; then
    echo "ERROR: k6 not found in PATH. Install k6 first."
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH."
    exit 1
fi

if [[ ! -f "${LOAD_TEST_SCRIPT}" ]]; then
    echo "ERROR: Load test script not found: ${LOAD_TEST_SCRIPT}"
    exit 1
fi

# Verify HPA exists
if ! kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: HPA '${HPA_NAME}' not found in namespace '${NAMESPACE}'"
    exit 1
fi

# Record initial replica count
initial_replicas=$(get_hpa_replicas)
info "Initial replica count: ${initial_replicas}"

# ---------------------------------------------------------------------------
# IT-01: Start k6 load test and verify scale-up within 90s
# Requirements: 12.2
# ---------------------------------------------------------------------------

header "IT-01: HPA scale-up under load (target: REPLICAS > ${MIN_REPLICAS} within ${SCALE_UP_TIMEOUT}s)"

info "Starting k6 load test in background..."
k6 run "${LOAD_TEST_SCRIPT}" > "${K6_OUTPUT_FILE}" 2>&1 &
K6_PID=$!
info "k6 started with PID: ${K6_PID}"

# Poll HPA replicas until scale-up detected or timeout
scale_up_detected=false
elapsed=0

while [[ ${elapsed} -lt ${SCALE_UP_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    current_replicas=$(get_hpa_replicas)
    current_replicas=$(echo "${current_replicas}" | tr -d '[:space:]')

    info "[${elapsed}s/${SCALE_UP_TIMEOUT}s] HPA replicas: ${current_replicas}"

    if [[ -n "${current_replicas}" ]] && [[ "${current_replicas}" -gt ${MIN_REPLICAS} ]] 2>/dev/null; then
        scale_up_detected=true
        break
    fi

    # Check if k6 is still running
    if ! kill -0 "${K6_PID}" 2>/dev/null; then
        info "k6 process ended earlier than expected"
        break
    fi
done

if [[ "${scale_up_detected}" == "true" ]]; then
    pass "HPA scaled up to ${current_replicas} replicas within ${elapsed}s (> ${MIN_REPLICAS})"
else
    fail "HPA did NOT scale above ${MIN_REPLICAS} within ${SCALE_UP_TIMEOUT}s (current: ${current_replicas:-unknown})"
fi

# ---------------------------------------------------------------------------
# IT-02: Verify http_req_failed < 5% during load test
# Requirements: 12.4
# ---------------------------------------------------------------------------

header "IT-02: Request success rate (http_req_failed < 5%)"

# Wait for k6 to finish if still running
if kill -0 "${K6_PID}" 2>/dev/null; then
    info "Waiting for k6 to complete..."
    wait "${K6_PID}" 2>/dev/null || true
fi

# Parse k6 output for http_req_failed metric
k6_output=$(cat "${K6_OUTPUT_FILE}" 2>/dev/null || true)

# k6 outputs threshold results like: ✓ http_req_failed...........: 0.00% ✓ < 5%
# or: ✗ http_req_failed...........: 7.50% ✗ < 5%
# The rate value can be extracted from the output
failed_rate=""

# Try to extract the http_req_failed percentage from k6 output
# k6 formats it as: http_req_failed................: X.XX%  ✓ rate<0.05
failed_rate=$(echo "${k6_output}" | grep -oP 'http_req_failed[^0-9]*\K[0-9]+\.[0-9]+' | head -1 || true)

if [[ -z "${failed_rate}" ]]; then
    # Fallback: try alternate k6 output format
    failed_rate=$(echo "${k6_output}" | grep "http_req_failed" | grep -oE '[0-9]+\.[0-9]+%' | head -1 | tr -d '%' || true)
fi

if [[ -n "${failed_rate}" ]]; then
    # Compare: failed_rate < 5.0
    threshold_ok=$(echo "${failed_rate} < 5.0" | bc -l 2>/dev/null || echo "0")
    if [[ "${threshold_ok}" == "1" ]]; then
        pass "http_req_failed = ${failed_rate}% (< 5% threshold)"
    else
        fail "http_req_failed = ${failed_rate}% (exceeds 5% threshold)"
    fi
else
    # Check if k6 reported the threshold as passed (✓)
    if echo "${k6_output}" | grep -q "✓.*http_req_failed" || echo "${k6_output}" | grep -q "http_req_failed.*✓"; then
        pass "http_req_failed threshold passed (k6 reported ✓)"
    elif echo "${k6_output}" | grep -q "✗.*http_req_failed" || echo "${k6_output}" | grep -q "http_req_failed.*✗"; then
        fail "http_req_failed threshold FAILED (k6 reported ✗)"
    else
        fail "Could not parse http_req_failed from k6 output"
        info "k6 output (last 20 lines):"
        echo "${k6_output}" | tail -20
    fi
fi

# ---------------------------------------------------------------------------
# IT-03: Verify HPA replicas stayed within [2, 10] during load
# Requirements: 12.2 (implicit — HPA bounds)
# ---------------------------------------------------------------------------

header "IT-03: HPA replicas within configured bounds [${MIN_REPLICAS}, 10]"

# Get current replica count after load
post_load_replicas=$(get_hpa_replicas)
post_load_replicas=$(echo "${post_load_replicas}" | tr -d '[:space:]')

if [[ -n "${post_load_replicas}" ]] && \
   [[ "${post_load_replicas}" -ge ${MIN_REPLICAS} ]] && \
   [[ "${post_load_replicas}" -le 10 ]] 2>/dev/null; then
    pass "Post-load replicas = ${post_load_replicas} (within [${MIN_REPLICAS}, 10])"
else
    fail "Post-load replicas = ${post_load_replicas:-unknown} (expected [${MIN_REPLICAS}, 10])"
fi

# ---------------------------------------------------------------------------
# IT-04: Scale-down to minReplicas after load stops (within 10 minutes)
# Requirements: 12.3
# ---------------------------------------------------------------------------

header "IT-04: HPA scale-down to ${MIN_REPLICAS} replicas (timeout: ${SCALE_DOWN_TIMEOUT}s)"

info "Load test finished. Waiting for scale-down..."

scale_down_detected=false
elapsed=0

while [[ ${elapsed} -lt ${SCALE_DOWN_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    current_replicas=$(get_hpa_replicas)
    current_replicas=$(echo "${current_replicas}" | tr -d '[:space:]')

    info "[${elapsed}s/${SCALE_DOWN_TIMEOUT}s] HPA replicas: ${current_replicas}"

    if [[ -n "${current_replicas}" ]] && [[ "${current_replicas}" -eq ${MIN_REPLICAS} ]] 2>/dev/null; then
        scale_down_detected=true
        break
    fi
done

if [[ "${scale_down_detected}" == "true" ]]; then
    pass "HPA scaled down to ${MIN_REPLICAS} replicas within ${elapsed}s"
else
    fail "HPA did NOT scale down to ${MIN_REPLICAS} within ${SCALE_DOWN_TIMEOUT}s (current: ${current_replicas:-unknown})"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "HPA SCALING TEST SUMMARY"
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
    echo -e "  \033[32m✓ All ${TOTAL} HPA scaling tests PASSED\033[0m"
    echo ""
    exit 0
fi
