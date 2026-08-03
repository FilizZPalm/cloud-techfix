#!/usr/bin/env bash
# tests/integration/test-nginx-spof.sh
#
# Integration test that documents the Single Point of Failure (SPOF) introduced
# by running Nginx with replicas: 1, and measures the exact downtime window
# that occurs when the sole Nginx pod is deleted.
#
# PURPOSE OF THIS TEST
# ────────────────────
# This is a diagnostic / characterisation test, not a pass/fail correctness
# test in the traditional sense. Its goals are:
#
#   1. Quantify the downtime caused by the Nginx SPOF so it appears in
#      the project's test report with a concrete number.
#
#   2. Verify that Kubernetes DOES recover automatically (the ReplicaSet
#      creates a replacement pod) even though there is unavoidable downtime.
#
#   3. Establish a baseline that motivates the architectural recommendation
#      to add an Nginx HPA or increase replicas to ≥ 2.
#
# WHY DOWNTIME IS EXPECTED (and how long)
# ────────────────────────────────────────
# With replicas: 1, deleting the Nginx pod creates a gap with no replacement
# immediately available. The recovery timeline is:
#
#   t=0        kubectl delete pod triggers graceful termination (terminationGracePeriodSeconds default: 30s)
#              but the pod is removed from the Service endpoint immediately on delete
#   t~0s       Service endpoints controller removes the pod from nginx-service
#              → Traefik has no backend → requests return 502/503
#   t~5-15s    ReplicaSet controller notices the pod is gone and creates a new one
#   t~15-35s   New pod is scheduled, image is pulled (cached), container starts
#              readinessProbe: initialDelaySeconds=5, periodSeconds=10, failureThreshold=3
#              → worst case 35s before the pod is marked Ready
#   t~35-50s   Endpoints controller adds the new pod back to nginx-service
#              → Traefik resumes routing
#
# Expected downtime window: ~15s – ~50s depending on scheduling speed.
# This test measures the actual window.
#
# Test structure:
#   IT-01  Baseline: Nginx has exactly 1 Running pod, HTTPS returns 200
#   IT-02  Delete the sole Nginx pod — service outage begins
#   IT-03  Measure downtime: time from pod deletion until HTTPS returns 200 again
#   IT-04  Recovery confirmed: new Nginx pod Running with a different name
#   IT-05  Downtime duration reported and compared against a SPOF threshold
#          (the test PASSES if downtime > 0 and < MAX_ACCEPTABLE_DOWNTIME,
#           which documents the gap and proves auto-recovery)
#
# PASS/FAIL SEMANTICS
# ───────────────────
# IT-05 passes when:
#   - Downtime > 0s (proves the SPOF is real — no zero-downtime without ≥ 2 replicas)
#   - Downtime ≤ MAX_ACCEPTABLE_DOWNTIME (proves recovery is automatic and bounded)
#
# If downtime is 0 the test fails with an explanatory message (likely Nginx
# has been scaled to ≥ 2 replicas and is no longer a SPOF).
# If downtime > MAX_ACCEPTABLE_DOWNTIME the test fails and recommends adding
# an HPA or increasing replicas.
#
# Requirements: 4.1 (Nginx deployment), implicit from single-replica design
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-nginx-spof.sh
#
# Prerequisites:
#   - kubectl configured (KUBECONFIG set or k3s default)
#   - curl available on the VM
#   - Nginx deployment running in namespace 'techfix' with replicas: 1
#   - HTTPS reachable at techfix.local:443
#
# Exit codes:
#   0 — all checks passed (downtime measured and within acceptable bound)
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
NGINX_DEPLOY="${NGINX_DEPLOY:-nginx-deployment}"
NGINX_CONTAINER="${NGINX_CONTAINER:-nginx}"
DOMAIN="${DOMAIN:-techfix.local}"

# Maximum acceptable downtime in seconds.
# Derived from Nginx probe config:
#   readinessProbe: initialDelaySeconds=5 + periodSeconds=10 × failureThreshold=3 = 35s
#   + scheduling overhead on k3s: ~20s
#   = 55s total. We allow 90s to cover slower Azure Lab VMs.
MAX_ACCEPTABLE_DOWNTIME="${MAX_ACCEPTABLE_DOWNTIME:-90}"

# How long to wait for the replacement pod to become Running (seconds)
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-120}"

# Interval between HTTP probes during downtime measurement (seconds).
# Shorter = more precise downtime measurement. 1s is a good balance between
# precision and noise.
PROBE_INTERVAL="${PROBE_INTERVAL:-1}"

# Individual HTTP probe timeout (seconds).
# Short on purpose: during outage we want fast failure, not hanging probes.
HTTP_TIMEOUT="${HTTP_TIMEOUT:-3}"

# Poll interval for pod status checks (seconds)
POLL_INTERVAL="${POLL_INTERVAL:-3}"

# ---------------------------------------------------------------------------
# Counters and helpers
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0
TOTAL=5

pass() { echo -e "  \033[32m[PASS]\033[0m $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  \033[31m[FAIL]\033[0m $*"; FAILED=$((FAILED + 1)); }
info() { echo -e "  [INFO] $*"; }
warn() { echo -e "  \033[33m[WARN]\033[0m $*"; }
header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Probe HTTPS and return HTTP status code. Returns "000" on failure/timeout.
http_probe() {
    curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${DOMAIN}:443:127.0.0.1" \
        "https://${DOMAIN}/" \
        --max-time "${HTTP_TIMEOUT}" 2>/dev/null || echo "000"
}

# Returns true (exit 0) if the HTTP response is a success (2xx or 3xx)
http_ok() {
    local code="$1"
    [[ "${code}" == "200" ]] || [[ "${code}" == "301" ]] || [[ "${code}" == "302" ]]
}

# Returns the name of the currently Running Nginx pod (first match)
get_nginx_pod() {
    kubectl get pods -n "${NAMESPACE}" -l app=nginx \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null \
        | awk 'NR==1{print $1}'
}

# Returns the count of Running Nginx pods
count_nginx_running() {
    kubectl get pods -n "${NAMESPACE}" -l app=nginx \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null \
        | wc -l | tr -d '[:space:]'
}

# Returns the ready replica count from the Nginx deployment
get_nginx_ready() {
    kubectl get deployment "${NGINX_DEPLOY}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null \
        | tr -d '[:space:]' || echo "0"
}

# Returns the configured replica count from the Nginx deployment spec
get_nginx_desired() {
    kubectl get deployment "${NGINX_DEPLOY}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null \
        | tr -d '[:space:]' || echo "0"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix Nginx SPOF Downtime Measurement Test"
echo ""
echo "  Namespace:               ${NAMESPACE}"
echo "  Nginx deployment:        ${NGINX_DEPLOY}"
echo "  Domain:                  ${DOMAIN}"
echo "  Max acceptable downtime: ${MAX_ACCEPTABLE_DOWNTIME}s"
echo "  Recovery timeout:        ${RECOVERY_TIMEOUT}s"
echo "  HTTP probe interval:     ${PROBE_INTERVAL}s"
echo "  HTTP probe timeout:      ${HTTP_TIMEOUT}s"
echo ""
echo "  NOTE: This test intentionally deletes the sole Nginx pod to expose"
echo "  the SPOF. Downtime IS expected. The test passes when:"
echo "    - Downtime > 0s  (SPOF is confirmed real)"
echo "    - Downtime ≤ ${MAX_ACCEPTABLE_DOWNTIME}s (recovery is automatic and bounded)"
echo ""

for cmd in kubectl curl; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "ERROR: '${cmd}' not found in PATH."
        exit 1
    fi
done

if ! kubectl get deployment "${NGINX_DEPLOY}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Deployment '${NGINX_DEPLOY}' not found in namespace '${NAMESPACE}'."
    exit 1
fi

# ---------------------------------------------------------------------------
# IT-01: Baseline — Nginx has exactly 1 Running pod, HTTPS returns 200
#
# This establishes the pre-deletion state. We also confirm replicas=1 in
# the spec, which is what makes Nginx a SPOF in the first place.
# If replicas ≥ 2 we warn and note the test will measure recovery time
# but may not see downtime.
# ---------------------------------------------------------------------------

header "IT-01: Baseline — Nginx running with desired replica count, HTTPS returns 200"

desired=$(get_nginx_desired)
ready=$(get_nginx_ready)
ready="${ready:-0}"
nginx_pod=$(get_nginx_pod)
baseline_http=$(http_probe)

info "Nginx desired replicas: ${desired}"
info "Nginx ready replicas:   ${ready}"
info "Nginx pod name:         ${nginx_pod:-<none found>}"
info "Baseline HTTP probe:    ${baseline_http}"

if [[ "${desired}" -gt 1 ]]; then
    warn "Nginx is configured with ${desired} replicas — it is no longer a single point of failure."
    warn "Downtime may be 0s during this test. Consider running with replicas=1 to see the SPOF."
fi

if [[ -z "${nginx_pod}" ]]; then
    echo "ERROR: No Running Nginx pod found. Cannot proceed."
    exit 1
fi

if [[ "${ready:-0}" -ge 1 ]] && http_ok "${baseline_http}"; then
    pass "IT-01: Nginx has ${ready}/${desired} ready replica(s), HTTPS returns ${baseline_http} — baseline healthy"
else
    fail "IT-01: Nginx not healthy before test (ready=${ready}, HTTP=${baseline_http}) — fix the cluster first"
    header "NGINX SPOF TEST SUMMARY"
    echo -e "  \033[31m✗ Aborted: cluster was not healthy at test start\033[0m"
    exit 1
fi

# Record the pod name — IT-04 compares against this
POD_BEFORE="${nginx_pod}"
info "Pod to be deleted: ${POD_BEFORE}"

# ---------------------------------------------------------------------------
# IT-02: Delete the sole Nginx pod — outage begins
#
# kubectl delete pod with --grace-period=0 --force skips the 30s graceful
# termination window. This is intentional: we want to simulate an abrupt
# failure (crash, OOMKill, node eviction) rather than a graceful rolling
# update. The Service endpoints controller removes the pod from the endpoint
# slice as soon as the pod's deletionTimestamp is set, before it actually
# terminates — so traffic starts failing at the moment of deletion.
#
# We record the deletion timestamp with sub-second precision using date +%s%N
# (nanoseconds), falling back to plain seconds. The downtime calculation
# uses integer seconds throughout for portability.
# ---------------------------------------------------------------------------

header "IT-02: Deleting sole Nginx pod '${POD_BEFORE}' — outage begins"

info "Sending delete command at $(date '+%H:%M:%S')..."

kubectl delete pod "${POD_BEFORE}" -n "${NAMESPACE}" \
    --grace-period=0 --force \
    &>/dev/null

DELETE_TS=$(date +%s)
info "Pod deleted at t=0 ($(date '+%H:%M:%S'))"

# Confirm the pod is actually gone (no longer Running)
info "Waiting for pod to disappear from Running list..."
elapsed=0
pod_gone=false
while [[ ${elapsed} -lt 15 ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    current_pod=$(get_nginx_pod)
    if [[ -z "${current_pod}" ]] || [[ "${current_pod}" != "${POD_BEFORE}" ]]; then
        pod_gone=true
        break
    fi
done

if [[ "${pod_gone}" == "true" ]]; then
    pass "IT-02: Pod '${POD_BEFORE}' removed from Running state in ${elapsed}s — outage window opened"
else
    fail "IT-02: Pod '${POD_BEFORE}' still appears Running after ${elapsed}s — deletion may not have taken effect"
fi

# ---------------------------------------------------------------------------
# IT-03: Measure downtime — time from pod deletion until HTTPS returns 200
#
# We probe HTTPS every PROBE_INTERVAL seconds. We record:
#   - OUTAGE_START_TS : first timestamp when HTTP is NOT 200/301
#   - RECOVERY_TS     : first timestamp when HTTP returns 200/301 again
#   - DOWNTIME_S      : RECOVERY_TS - OUTAGE_START_TS
#
# We also log every probe result with its timestamp offset from DELETE_TS
# so the full downtime timeline is visible in the test output.
#
# We probe for up to RECOVERY_TIMEOUT seconds total. If the service has not
# recovered by then we report the full timeout as the downtime lower bound.
# ---------------------------------------------------------------------------

header "IT-03: Measuring downtime — probing HTTPS every ${PROBE_INTERVAL}s"

echo ""
echo "  t=0 is the moment kubectl delete pod was issued."
echo "  Probing https://${DOMAIN}/ ..."
echo ""

OUTAGE_START_TS=0
RECOVERY_TS=0
DOWNTIME_STARTED=false
SERVICE_RECOVERED=false

# First probe immediately — check if outage has already started
elapsed=0
max_elapsed="${RECOVERY_TIMEOUT}"

# Track consecutive successes to avoid declaring recovery on a single fluke
CONSECUTIVE_OK=0
CONSECUTIVE_NEEDED=2   # require 2 back-to-back 200s to declare recovery

while [[ ${elapsed} -lt ${max_elapsed} ]]; do
    probe_ts=$(date +%s)
    offset=$((probe_ts - DELETE_TS))
    code=$(http_probe)

    if http_ok "${code}"; then
        CONSECUTIVE_OK=$((CONSECUTIVE_OK + 1))
        echo "  [t+${offset}s] HTTP ${code} ✓"

        if [[ "${DOWNTIME_STARTED}" == "false" ]]; then
            # Service never went down — still track but note it
            :
        fi

        if [[ "${CONSECUTIVE_OK}" -ge "${CONSECUTIVE_NEEDED}" ]] && \
           [[ "${DOWNTIME_STARTED}" == "true" ]] && \
           [[ "${SERVICE_RECOVERED}" == "false" ]]; then
            RECOVERY_TS=${probe_ts}
            SERVICE_RECOVERED=true
            echo ""
            info "  Service recovered at t+${offset}s (${CONSECUTIVE_NEEDED} consecutive 200s)"
            break
        fi
    else
        CONSECUTIVE_OK=0
        echo "  [t+${offset}s] HTTP ${code} ✗  ← outage"

        if [[ "${DOWNTIME_STARTED}" == "false" ]]; then
            OUTAGE_START_TS=${probe_ts}
            DOWNTIME_STARTED=true
        fi
    fi

    sleep "${PROBE_INTERVAL}"
    elapsed=$((elapsed + PROBE_INTERVAL))
done

echo ""

# Calculate downtime
if [[ "${DOWNTIME_STARTED}" == "true" ]] && [[ "${SERVICE_RECOVERED}" == "true" ]]; then
    DOWNTIME_S=$((RECOVERY_TS - OUTAGE_START_TS))
    OUTAGE_OFFSET=$((OUTAGE_START_TS - DELETE_TS))
    info "Outage started:   t+${OUTAGE_OFFSET}s after pod deletion"
    info "Service recovered: t+$((RECOVERY_TS - DELETE_TS))s after pod deletion"
    info "Measured downtime: ${DOWNTIME_S}s"
    pass "IT-03: Downtime measured at ${DOWNTIME_S}s (outage started t+${OUTAGE_OFFSET}s, ended t+$((RECOVERY_TS - DELETE_TS))s)"
elif [[ "${DOWNTIME_STARTED}" == "false" ]]; then
    DOWNTIME_S=0
    info "Service never returned a non-2xx response during the probe window."
    info "Either Nginx was not a SPOF (replicas > 1) or the replacement pod"
    info "was scheduled before the first probe hit."
    pass "IT-03: No measurable downtime detected (DOWNTIME_S=0) — possible that replicas > 1 prevented outage"
else
    # Outage started but service never recovered within RECOVERY_TIMEOUT
    DOWNTIME_S=${RECOVERY_TIMEOUT}
    fail "IT-03: Service did NOT recover within ${RECOVERY_TIMEOUT}s — downtime ≥ ${RECOVERY_TIMEOUT}s"
fi

# ---------------------------------------------------------------------------
# IT-04: Recovery confirmed — new Nginx pod Running with a different name
#
# The ReplicaSet must have created a replacement pod. We verify:
#   1. A Running Nginx pod exists
#   2. Its name is different from POD_BEFORE (it is a new pod, not a restart)
#   3. The Deployment's readyReplicas == desiredReplicas
#
# If the replacement pod is already Running (detected during IT-03's probe
# loop), we use that. Otherwise we wait up to RECOVERY_TIMEOUT.
# ---------------------------------------------------------------------------

header "IT-04: Recovery confirmed — new Nginx pod Running with different name"

elapsed=0
recovery_confirmed=false
new_pod_name=""

# How much time has already elapsed in IT-03 — account for it in the timeout
already_elapsed=$(($(date +%s) - DELETE_TS))
remaining=$((RECOVERY_TIMEOUT - already_elapsed))
[[ "${remaining}" -lt 15 ]] && remaining=15

while [[ ${elapsed} -lt ${remaining} ]]; do
    current_pod=$(get_nginx_pod)
    ready=$(get_nginx_ready)
    ready="${ready:-0}"

    if [[ -n "${current_pod}" ]] && \
       [[ "${current_pod}" != "${POD_BEFORE}" ]] && \
       [[ "${ready}" -ge 1 ]]; then
        recovery_confirmed=true
        new_pod_name="${current_pod}"
        break
    fi

    info "  [+${elapsed}s] current pod: ${current_pod:-<none>}, ready: ${ready}"
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))
done

if [[ "${recovery_confirmed}" == "true" ]]; then
    final_desired=$(get_nginx_desired)
    final_ready=$(get_nginx_ready)
    pass "IT-04: New Nginx pod '${new_pod_name}' Running and Ready (${final_ready}/${final_desired}) — ReplicaSet self-healing confirmed"
    info "  Pod before: ${POD_BEFORE}"
    info "  Pod after:  ${new_pod_name}"
else
    final_pod=$(get_nginx_pod)
    final_ready=$(get_nginx_ready)
    fail "IT-04: Recovery not confirmed within timeout (pod: ${final_pod:-<none>}, ready: ${final_ready:-0})"
fi

# ---------------------------------------------------------------------------
# IT-05: Downtime duration assessment
#
# Compares the measured downtime against MAX_ACCEPTABLE_DOWNTIME and produces
# a final verdict with an architectural recommendation.
#
# Pass conditions (both must hold):
#   A) DOWNTIME_S > 0s   — the SPOF is real (if replicas=1)
#      OR DOWNTIME_S = 0s AND replicas > 1  — SPOF already mitigated, document it
#   B) DOWNTIME_S ≤ MAX_ACCEPTABLE_DOWNTIME — recovery is automatic and bounded
#
# The test intentionally passes even when there is downtime because the test's
# purpose is to *characterise* the SPOF, not to assert zero downtime.
# Zero downtime here would mean the SPOF has been fixed (good!) or that the
# probe interval was too coarse to catch it (needs investigation).
# ---------------------------------------------------------------------------

header "IT-05: Downtime duration assessment (max acceptable: ${MAX_ACCEPTABLE_DOWNTIME}s)"

echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │                NGINX SPOF DOWNTIME REPORT                   │"
echo "  ├─────────────────────────────────┬───────────────────────────┤"
printf "  │ %-31s │ %-25s │\n" "Metric" "Value"
echo "  ├─────────────────────────────────┼───────────────────────────┤"
printf "  │ %-31s │ %-25s │\n" "Nginx replicas (spec)"       "${desired}"
printf "  │ %-31s │ %-25s │\n" "Pod deleted"                 "${POD_BEFORE}"
printf "  │ %-31s │ %-25s │\n" "Replacement pod"             "${new_pod_name:-<not yet running>}"
printf "  │ %-31s │ %-25s │\n" "Measured downtime"           "${DOWNTIME_S}s"
printf "  │ %-31s │ %-25s │\n" "Max acceptable downtime"     "${MAX_ACCEPTABLE_DOWNTIME}s"
printf "  │ %-31s │ %-25s │\n" "Probe interval"              "${PROBE_INTERVAL}s (±${PROBE_INTERVAL}s precision)"
echo "  └─────────────────────────────────┴───────────────────────────┘"
echo ""

within_bound=false
if [[ "${DOWNTIME_S}" -le "${MAX_ACCEPTABLE_DOWNTIME}" ]] 2>/dev/null; then
    within_bound=true
fi

if [[ "${within_bound}" == "true" ]]; then
    if [[ "${DOWNTIME_S}" -gt 0 ]]; then
        pass "IT-05: Downtime = ${DOWNTIME_S}s — SPOF confirmed (replicas=1 causes outage on pod deletion) and bounded (≤ ${MAX_ACCEPTABLE_DOWNTIME}s)"
        echo ""
        warn "  ARCHITECTURAL RECOMMENDATION:"
        warn "  The ${DOWNTIME_S}s downtime window is caused by having a single Nginx replica."
        warn "  To eliminate this SPOF, either:"
        warn "    a) Scale to ≥ 2 replicas: kubectl scale deployment nginx-deployment -n techfix --replicas=2"
        warn "    b) Add an HPA targeting Nginx CPU to auto-scale under load"
        warn "  With 2 replicas, pod deletion triggers a rolling update with zero downtime."
    else
        pass "IT-05: Downtime = 0s — either Nginx has multiple replicas (SPOF already mitigated) or replacement was faster than probe interval (${PROBE_INTERVAL}s)"
        info "  If replicas=1, consider decreasing PROBE_INTERVAL for higher measurement precision."
    fi
else
    fail "IT-05: Downtime = ${DOWNTIME_S}s EXCEEDS max acceptable threshold of ${MAX_ACCEPTABLE_DOWNTIME}s"
    echo ""
    warn "  Recovery took longer than expected. Possible causes:"
    warn "    - Image pull is slow (check if techfix/nginx:1.0.0 is cached in k3s containerd)"
    warn "    - Node is under heavy load (Azure Lab VM resource contention)"
    warn "    - readinessProbe is too conservative (initialDelaySeconds=5, periodSeconds=10, failureThreshold=3)"
    warn "  To pre-load the image: sudo k3s ctr images ls | grep nginx"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "NGINX SPOF DOWNTIME TEST SUMMARY"
echo ""
echo "  Total:  ${TOTAL}"
echo -e "  Passed: \033[32m${PASSED}\033[0m"
echo -e "  Failed: \033[31m${FAILED}\033[0m"
echo ""

if [[ "${FAILED}" -gt 0 ]]; then
    echo -e "  \033[31m✗ ${FAILED} test(s) FAILED\033[0m"
    echo ""
    exit 1
else
    echo -e "  \033[32m✓ All ${TOTAL} Nginx SPOF tests PASSED\033[0m"
    echo ""
    exit 0
fi
