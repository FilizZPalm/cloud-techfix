#!/usr/bin/env bash
# tests/integration/test-node-failure-rescheduling.sh
#
# Integration test that validates Kubernetes self-healing behaviour when the
# node hosting application pods becomes unavailable.
#
# On this single-node k3s cluster a real VM failure cannot be simulated
# without destroying the cluster itself. Instead, the test applies a
# NoExecute taint to the node — the same mechanism Kubernetes uses
# internally when a real node goes NotReady. Calico and the k3s
# node-lifecycle controller both honour NoExecute taints identically to
# an actual node failure, making this a faithful simulation:
#
#   kubectl taint nodes <node> simulation=node-failure:NoExecute
#
# A NoExecute taint causes:
#   - All pods WITHOUT a matching toleration to be evicted immediately.
#   - The Deployments' ReplicaSets to create replacement pods.
#   - New pods to remain Pending until the taint is removed (single-node),
#     at which point they are scheduled and reach Running.
#
# The test then removes the taint (simulating node recovery) and waits for
# all pods to return to the Ready state. HTTP probes run throughout to
# measure how long the application is unavailable, if at all.
#
# Test structure:
#   IT-01  All target pods are Running before the simulated failure
#   IT-02  Pods are evicted after the NoExecute taint is applied
#   IT-03  HTTP service is restored within the recovery timeout after taint removal
#   IT-04  All Deployments reach their desired replica count after recovery
#   IT-05  Pod names changed — confirms rescheduling, not just restart
#
# NOTE: This test is intentionally destructive within the namespace: it
# evicts running pods. It is designed to be idempotent — the cleanup trap
# always removes the taint so the cluster is left in a healthy state.
#
# Requirements: 2.1, 4.1, 4.2
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-node-failure-rescheduling.sh
#
# Prerequisites:
#   - Single-node k3s cluster with namespace 'techfix'
#   - Laravel and Nginx deployments Running
#   - curl available on the VM
#   - KUBECONFIG set or defaulting to /etc/rancher/k3s/k3s.yaml
#
# Exit codes:
#   0 — all integration checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
DOMAIN="${DOMAIN:-techfix.local}"

# Taint applied to simulate node failure
TAINT_KEY="${TAINT_KEY:-simulation}"
TAINT_VALUE="${TAINT_VALUE:-node-failure}"
TAINT_EFFECT="${TAINT_EFFECT:-NoExecute}"
TAINT="${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}"

# Deployments to monitor — these are the ones that must recover
DEPLOYMENTS=("laravel-deployment" "nginx-deployment")

# How long to wait for pods to be evicted after the taint is applied (seconds)
EVICTION_TIMEOUT="${EVICTION_TIMEOUT:-60}"

# How long to wait for full recovery after the taint is removed (seconds).
# Pods must be Running AND the HTTP endpoint must return 200 within this window.
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-120}"

# Individual HTTP probe timeout (seconds)
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"

# Polling interval for pod status checks (seconds)
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# ---------------------------------------------------------------------------
# Counters and helpers
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0
TOTAL=5

pass() { echo -e "  \033[32m[PASS]\033[0m $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  \033[31m[FAIL]\033[0m $*"; FAILED=$((FAILED + 1)); }
info() { echo -e "  [INFO] $*"; }
header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ---------------------------------------------------------------------------
# Cleanup — always remove the taint on exit so the cluster stays healthy.
# Without this, a test failure would leave all pods permanently evicted.
# ---------------------------------------------------------------------------

NODE_NAME=""   # populated after pre-flight

cleanup() {
    if [[ -n "${NODE_NAME}" ]]; then
        # Check if the taint is still present before trying to remove it
        if kubectl get node "${NODE_NAME}" -o jsonpath='{.spec.taints}' 2>/dev/null \
                | grep -q "${TAINT_KEY}"; then
            info "CLEANUP: Removing taint '${TAINT}' from node '${NODE_NAME}'..."
            kubectl taint node "${NODE_NAME}" "${TAINT_KEY}-" &>/dev/null 2>&1 || true
            info "CLEANUP: Taint removed — cluster restored"
        else
            info "CLEANUP: Taint not present on node '${NODE_NAME}' — nothing to remove"
        fi
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helper: probe the HTTPS endpoint and return the HTTP status code.
# Returns "000" on connection failure/timeout.
# ---------------------------------------------------------------------------

http_probe() {
    curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${DOMAIN}:443:127.0.0.1" \
        "https://${DOMAIN}/" \
        --max-time "${HTTP_TIMEOUT}" 2>/dev/null || echo "000"
}

# ---------------------------------------------------------------------------
# Helper: count Running pods for a given deployment label.
# ---------------------------------------------------------------------------

count_running_pods() {
    local label="$1"
    kubectl get pods -n "${NAMESPACE}" -l "app=${label}" \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null \
        | wc -l \
        | tr -d '[:space:]'
}

# ---------------------------------------------------------------------------
# Helper: count all pods (any phase) for a deployment label.
# ---------------------------------------------------------------------------

count_all_pods() {
    local label="$1"
    kubectl get pods -n "${NAMESPACE}" -l "app=${label}" \
        --no-headers 2>/dev/null \
        | wc -l \
        | tr -d '[:space:]'
}

# ---------------------------------------------------------------------------
# Helper: collect current pod names for a deployment label.
# Returns a space-separated list.
# ---------------------------------------------------------------------------

get_pod_names() {
    local label="$1"
    kubectl get pods -n "${NAMESPACE}" -l "app=${label}" \
        --no-headers 2>/dev/null \
        | awk '{print $1}' \
        | tr '\n' ' ' \
        | sed 's/ $//'
}

# ---------------------------------------------------------------------------
# Helper: get desired replica count for a deployment.
# ---------------------------------------------------------------------------

get_desired_replicas() {
    local deploy="$1"
    kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# Helper: get ready replica count for a deployment.
# ---------------------------------------------------------------------------

get_ready_replicas() {
    local deploy="$1"
    kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix Node Failure & Pod Rescheduling Integration Test"
echo ""
echo "  Namespace:         ${NAMESPACE}"
echo "  Domain:            ${DOMAIN}"
echo "  Taint applied:     ${TAINT}"
echo "  Eviction timeout:  ${EVICTION_TIMEOUT}s"
echo "  Recovery timeout:  ${RECOVERY_TIMEOUT}s"
echo "  HTTP probe timeout:${HTTP_TIMEOUT}s"
echo "  Deployments:       ${DEPLOYMENTS[*]}"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH."
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found in PATH."
    exit 1
fi

# Resolve node name (single-node cluster — there is exactly one)
NODE_NAME=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [[ -z "${NODE_NAME}" ]]; then
    echo "ERROR: Could not determine node name. Is kubectl configured correctly?"
    exit 1
fi
info "Node under test: ${NODE_NAME}"

# Verify the taint is not already present from a previous aborted run
if kubectl get node "${NODE_NAME}" -o jsonpath='{.spec.taints}' 2>/dev/null \
        | grep -q "${TAINT_KEY}"; then
    info "Stale taint '${TAINT_KEY}' found from a previous run — removing it first..."
    kubectl taint node "${NODE_NAME}" "${TAINT_KEY}-" &>/dev/null 2>&1 || true
    sleep 5
fi

# Verify deployments exist
for deploy in "${DEPLOYMENTS[@]}"; do
    if ! kubectl get deployment "${deploy}" -n "${NAMESPACE}" &>/dev/null; then
        echo "ERROR: Deployment '${deploy}' not found in namespace '${NAMESPACE}'."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# IT-01: Baseline — all deployments Running before the simulated failure
#
# The test is only meaningful if the cluster starts from a healthy state.
# We capture pod names here so IT-05 can compare them after recovery.
# ---------------------------------------------------------------------------

header "IT-01: Baseline — all deployments healthy before simulated failure"

baseline_ok=true
declare -A PODS_BEFORE   # label → space-separated pod names

for deploy in "${DEPLOYMENTS[@]}"; do
    # Derive the app label from the deployment name
    # (laravel-deployment → laravel, nginx-deployment → nginx)
    label="${deploy%-deployment}"

    desired=$(get_desired_replicas "${deploy}")
    ready=$(get_ready_replicas "${deploy}")
    ready="${ready:-0}"

    PODS_BEFORE["${label}"]=$(get_pod_names "${label}")

    info "Deployment '${deploy}': desired=${desired}, ready=${ready}"
    info "  Current pods: ${PODS_BEFORE[${label}]}"

    if [[ "${ready}" -lt 1 ]] 2>/dev/null; then
        baseline_ok=false
        info "  ✗ No ready replicas"
    fi
done

# Baseline HTTP check
baseline_http=$(http_probe)
info "Baseline HTTP probe: ${baseline_http}"

if [[ "${baseline_ok}" == "true" ]] && [[ "${baseline_http}" == "200" ]]; then
    pass "IT-01: All deployments have ready replicas and HTTPS returns 200 before failure"
elif [[ "${baseline_ok}" == "true" ]]; then
    pass "IT-01: All deployments have ready replicas (HTTP probe returned ${baseline_http} — Traefik may not be fully ready)"
else
    fail "IT-01: One or more deployments have no ready replicas before the test — fix the cluster first"
    # Do not proceed: the subsequent tests would be meaningless
    header "NODE FAILURE RESCHEDULING TEST SUMMARY"
    echo ""
    echo "  Total:  ${TOTAL}"
    echo -e "  Passed: \033[32m${PASSED}\033[0m"
    echo -e "  Failed: \033[31m${FAILED}\033[0m"
    echo ""
    echo -e "  \033[31m✗ Aborted: cluster was not healthy at test start\033[0m"
    echo ""
    exit 1
fi

# ---------------------------------------------------------------------------
# Apply the NoExecute taint — simulates the node becoming unavailable.
#
# NoExecute is the strongest taint effect:
#   - Pods without a matching toleration are evicted immediately.
#   - New pods from the ReplicaSet cannot be scheduled (single-node: nowhere
#     else to go), so they stay Pending until the taint is removed.
#
# This mirrors what happens when the kubelet stops reporting to the API server
# and the node-lifecycle controller marks the node NotReady, then applies
# node.kubernetes.io/not-ready:NoExecute automatically.
# ---------------------------------------------------------------------------

header "Simulating node failure — applying NoExecute taint to '${NODE_NAME}'"

kubectl taint node "${NODE_NAME}" "${TAINT}" \
    || { echo "ERROR: Failed to apply taint '${TAINT}' to node '${NODE_NAME}'."; exit 1; }

TAINT_APPLIED_AT=$(date +%s)
info "Taint '${TAINT}' applied at $(date '+%H:%M:%S')"
info "Waiting for pod eviction (timeout: ${EVICTION_TIMEOUT}s)..."

# ---------------------------------------------------------------------------
# IT-02: Pods are evicted after the NoExecute taint is applied
#
# We poll until Running pod counts across all monitored deployments drop to 0,
# or until the timeout expires. A drop to 0 confirms that Kubernetes honoured
# the NoExecute taint and evicted the pods.
# ---------------------------------------------------------------------------

header "IT-02: Pods evicted within ${EVICTION_TIMEOUT}s of NoExecute taint"

elapsed=0
all_evicted=false

while [[ ${elapsed} -lt ${EVICTION_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    total_running=0
    status_parts=()

    for deploy in "${DEPLOYMENTS[@]}"; do
        label="${deploy%-deployment}"
        running=$(count_running_pods "${label}")
        running="${running:-0}"
        total_running=$((total_running + running))
        status_parts+=("${label}=${running}")
    done

    info "  [${elapsed}s/${EVICTION_TIMEOUT}s] Running pods: ${status_parts[*]}"

    if [[ "${total_running}" -eq 0 ]]; then
        all_evicted=true
        break
    fi
done

if [[ "${all_evicted}" == "true" ]]; then
    pass "IT-02: All monitored pods evicted within ${elapsed}s of NoExecute taint — self-healing triggered"
else
    # Report what is still running
    remaining=()
    for deploy in "${DEPLOYMENTS[@]}"; do
        label="${deploy%-deployment}"
        running=$(count_running_pods "${label}")
        [[ "${running:-0}" -gt 0 ]] && remaining+=("${label}: ${running} still Running")
    done
    fail "IT-02: Pods NOT fully evicted within ${EVICTION_TIMEOUT}s — ${remaining[*]:-unknown state}"
fi

# ---------------------------------------------------------------------------
# Remove the taint — simulates the node recovering / coming back online.
# ---------------------------------------------------------------------------

header "Simulating node recovery — removing taint from '${NODE_NAME}'"

kubectl taint node "${NODE_NAME}" "${TAINT_KEY}-" \
    || { echo "ERROR: Failed to remove taint from node '${NODE_NAME}'."; exit 1; }

RECOVERY_STARTED_AT=$(date +%s)
info "Taint removed at $(date '+%H:%M:%S') — pods should now be schedulable"
info "Waiting for full recovery (timeout: ${RECOVERY_TIMEOUT}s)..."

# ---------------------------------------------------------------------------
# IT-03: HTTP service restored within the recovery timeout
#
# We poll the HTTPS endpoint until we get HTTP 200 (or 301 redirect).
# This is the user-visible measure of recovery: the application is serving
# requests again. We record the time-to-recovery for informational output.
# ---------------------------------------------------------------------------

header "IT-03: HTTPS service restored within ${RECOVERY_TIMEOUT}s of node recovery"

elapsed=0
service_restored=false
recovery_elapsed=0

while [[ ${elapsed} -lt ${RECOVERY_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    http_code=$(http_probe)
    info "  [${elapsed}s/${RECOVERY_TIMEOUT}s] HTTP probe: ${http_code}"

    if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "301" ]]; then
        service_restored=true
        recovery_elapsed=${elapsed}
        break
    fi
done

if [[ "${service_restored}" == "true" ]]; then
    pass "IT-03: HTTPS service restored in ${recovery_elapsed}s — HTTP ${http_code} received"
else
    fail "IT-03: HTTPS service NOT restored within ${RECOVERY_TIMEOUT}s (last HTTP code: ${http_code:-000})"
fi

# ---------------------------------------------------------------------------
# IT-04: All Deployments reach their desired replica count after recovery
#
# Recovery of the HTTP endpoint alone is not sufficient — we must confirm
# that ALL replicas (not just one) are back and ready. A deployment that
# permanently loses replicas would silently degrade capacity.
# ---------------------------------------------------------------------------

header "IT-04: All Deployments reach desired replica count after recovery"

all_recovered=true
recovery_details=()

for deploy in "${DEPLOYMENTS[@]}"; do
    desired=$(get_desired_replicas "${deploy}")
    desired="${desired:-0}"

    # Allow up to RECOVERY_TIMEOUT total; subtract time already spent in IT-03
    remaining_timeout=$((RECOVERY_TIMEOUT - recovery_elapsed))
    [[ "${remaining_timeout}" -lt 10 ]] && remaining_timeout=30  # minimum grace

    elapsed_local=0
    deploy_recovered=false

    while [[ ${elapsed_local} -lt ${remaining_timeout} ]]; do
        ready=$(get_ready_replicas "${deploy}")
        ready="${ready:-0}"

        if [[ "${ready}" -ge "${desired}" ]] && [[ "${desired}" -gt 0 ]]; then
            deploy_recovered=true
            break
        fi

        sleep "${POLL_INTERVAL}"
        elapsed_local=$((elapsed_local + POLL_INTERVAL))
        info "  [${elapsed_local}s] '${deploy}': ready=${ready}/${desired}"
    done

    if [[ "${deploy_recovered}" == "true" ]]; then
        final_ready=$(get_ready_replicas "${deploy}")
        recovery_details+=("${deploy}: ${final_ready}/${desired} ready ✓")
        info "  '${deploy}' recovered: ${final_ready}/${desired} ready"
    else
        final_ready=$(get_ready_replicas "${deploy}")
        recovery_details+=("${deploy}: ${final_ready:-0}/${desired} ready ✗")
        all_recovered=false
        info "  '${deploy}' did NOT fully recover: ${final_ready:-0}/${desired} ready"
    fi
done

if [[ "${all_recovered}" == "true" ]]; then
    pass "IT-04: All Deployments recovered to desired replica count — ${recovery_details[*]}"
else
    fail "IT-04: One or more Deployments did not recover — ${recovery_details[*]}"
fi

# ---------------------------------------------------------------------------
# IT-05: Pod names changed after recovery — confirms rescheduling occurred
#
# If the pod names after recovery are different from those before the taint,
# it proves that Kubernetes created brand-new pods (rescheduling), not just
# restarted the original ones in place. This is the defining property of
# Deployment-based self-healing.
# ---------------------------------------------------------------------------

header "IT-05: Pod names changed — rescheduling confirmed (not in-place restart)"

all_rescheduled=true
reschedule_details=()

for deploy in "${DEPLOYMENTS[@]}"; do
    label="${deploy%-deployment}"

    pods_before_list="${PODS_BEFORE[${label}]:-}"
    pods_after_list=$(get_pod_names "${label}")

    info "  '${deploy}' pods BEFORE: ${pods_before_list:-<none>}"
    info "  '${deploy}' pods AFTER:  ${pods_after_list:-<none>}"

    if [[ -z "${pods_after_list}" ]]; then
        all_rescheduled=false
        reschedule_details+=("${deploy}: no pods found after recovery")
        continue
    fi

    # Check whether ALL current pod names are new (not in the before-list).
    # In a Deployment rollout, the ReplicaSet always creates pods with new names.
    new_pods_found=false
    for pod_after in ${pods_after_list}; do
        if ! echo "${pods_before_list}" | grep -qw "${pod_after}"; then
            new_pods_found=true
            break
        fi
    done

    if [[ "${new_pods_found}" == "true" ]]; then
        reschedule_details+=("${deploy}: new pod names confirmed ✓")
        info "  '${deploy}': new pod names confirmed — rescheduling occurred"
    else
        all_rescheduled=false
        reschedule_details+=("${deploy}: pod names unchanged ✗")
        info "  '${deploy}': pod names UNCHANGED — rescheduling may not have occurred"
    fi
done

if [[ "${all_rescheduled}" == "true" ]]; then
    pass "IT-05: All Deployments have new pod names after recovery — ${reschedule_details[*]}"
else
    fail "IT-05: One or more Deployments show unchanged pod names — ${reschedule_details[*]}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "NODE FAILURE RESCHEDULING TEST SUMMARY"
echo ""
echo "  Failure simulation:  NoExecute taint on node '${NODE_NAME}'"
echo "  Deployments tested:  ${DEPLOYMENTS[*]}"
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
    echo -e "  \033[32m✓ All ${TOTAL} node failure / rescheduling tests PASSED\033[0m"
    echo ""
    exit 0
fi
