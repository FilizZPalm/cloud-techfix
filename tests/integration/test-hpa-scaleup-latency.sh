#!/usr/bin/env bash
# tests/integration/test-hpa-scaleup-latency.sh
#
# Integration test that measures and validates the latency of each phase of
# the HPA scale-up pipeline under load:
#
#   Phase 1 — CPU breach      : time from load start until avg CPU exceeds 70%
#   Phase 2 — HPA decision    : time from CPU breach until HPA increases desiredReplicas
#   Phase 3 — Pod scheduling  : time from HPA decision until first new pod is Running
#   Phase 4 — Full capacity   : time from HPA decision until ALL new pods are Running
#
# The existing test-hpa-scaling.sh only checks *whether* scale-up happens.
# This test checks *how fast* each phase completes and asserts upper bounds
# derived from the HPA spec (stabilizationWindowSeconds: 15, periodSeconds: 15)
# plus reasonable scheduling overhead for a single-node k3s cluster.
#
# Timeline thresholds (configurable via env vars):
#   CPU_BREACH_TIMEOUT      : 60s  — load must push CPU above threshold within 1 min
#   HPA_DECISION_TIMEOUT    : 45s  — HPA must react within 45s of CPU breach
#                                    (stabilizationWindow=15s + 2 scrape intervals)
#   FIRST_POD_READY_TIMEOUT : 60s  — first new pod Running within 60s of HPA decision
#   FULL_CAPACITY_TIMEOUT   : 90s  — all new pods Running within 90s of HPA decision
#
# Test structure:
#   IT-01  Baseline: HPA at minReplicas (2), CPU below threshold
#   IT-02  CPU breach: avg utilization exceeds 70% within CPU_BREACH_TIMEOUT
#   IT-03  HPA decision latency: desiredReplicas increases within HPA_DECISION_TIMEOUT
#   IT-04  First-pod latency: first new pod Running within FIRST_POD_READY_TIMEOUT
#   IT-05  Full-capacity latency: all new pods Running within FULL_CAPACITY_TIMEOUT
#   IT-06  No HTTP errors during the entire scale-up window
#
# Requirements: 6.1, 6.2, 6.3, 12.2, 12.4
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-hpa-scaleup-latency.sh
#
# Prerequisites:
#   - k6 installed and in PATH
#   - kubectl configured (KUBECONFIG set or k3s default)
#   - metrics-server running (HPA requires it for CPU metrics)
#   - HPA 'laravel-hpa' deployed in namespace 'techfix'
#   - scripts/load-test.js present in the project root
#   - curl available on the VM
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
HPA_NAME="${HPA_NAME:-laravel-hpa}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-laravel-deployment}"
LOAD_TEST_SCRIPT="${LOAD_TEST_SCRIPT:-scripts/load-test.js}"
DOMAIN="${DOMAIN:-techfix.local}"

# HPA spec values (must match k8s/laravel-hpa.yaml)
HPA_MIN_REPLICAS="${HPA_MIN_REPLICAS:-2}"
HPA_MAX_REPLICAS="${HPA_MAX_REPLICAS:-10}"
HPA_CPU_TARGET="${HPA_CPU_TARGET:-70}"          # percent

# Phase latency thresholds (seconds)
CPU_BREACH_TIMEOUT="${CPU_BREACH_TIMEOUT:-60}"
HPA_DECISION_TIMEOUT="${HPA_DECISION_TIMEOUT:-45}"
FIRST_POD_READY_TIMEOUT="${FIRST_POD_READY_TIMEOUT:-60}"
FULL_CAPACITY_TIMEOUT="${FULL_CAPACITY_TIMEOUT:-90}"

# Polling interval for replica / CPU checks (seconds)
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# HTTP probe timeout (seconds)
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"

# Temp files
K6_OUTPUT_FILE="/tmp/k6-latency-test-output.txt"
HTTP_ERROR_LOG="/tmp/k6-latency-http-errors.txt"

# ---------------------------------------------------------------------------
# Counters and helpers
# ---------------------------------------------------------------------------

PASSED=0
FAILED=0
TOTAL=6

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
# Cleanup
# ---------------------------------------------------------------------------

K6_PID=""
HTTP_PROBE_PID=""

cleanup() {
    if [[ -n "${K6_PID}" ]] && kill -0 "${K6_PID}" 2>/dev/null; then
        info "Stopping k6 (PID ${K6_PID})..."
        kill "${K6_PID}" 2>/dev/null || true
        wait "${K6_PID}" 2>/dev/null || true
    fi
    if [[ -n "${HTTP_PROBE_PID}" ]] && kill -0 "${HTTP_PROBE_PID}" 2>/dev/null; then
        kill "${HTTP_PROBE_PID}" 2>/dev/null || true
        wait "${HTTP_PROBE_PID}" 2>/dev/null || true
    fi
    rm -f "${K6_OUTPUT_FILE}" "${HTTP_ERROR_LOG}" 2>/dev/null || true
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Returns the HPA's current desiredReplicas field.
# This is what the HPA controller has *decided*, before pods are created.
get_hpa_desired() {
    kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.desiredReplicas}' 2>/dev/null \
        | tr -d '[:space:]' || echo "0"
}

# Returns the HPA's currentReplicas (pods already running / being replaced).
get_hpa_current() {
    kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.currentReplicas}' 2>/dev/null \
        | tr -d '[:space:]' || echo "0"
}

# Returns the average CPU utilization % as reported by the HPA.
# The HPA surfaces this in .status.currentMetrics[0].resource.current.averageUtilization.
get_hpa_cpu() {
    kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' \
        2>/dev/null | tr -d '[:space:]' || echo "0"
}

# Returns the number of Running pods for the Laravel deployment.
get_running_pods() {
    kubectl get pods -n "${NAMESPACE}" -l app=laravel \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null \
        | wc -l | tr -d '[:space:]'
}

# Returns space-separated names of all Laravel pods (any phase).
get_all_pod_names() {
    kubectl get pods -n "${NAMESPACE}" -l app=laravel \
        --no-headers 2>/dev/null \
        | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//'
}

# Probe HTTPS and return HTTP status code. Returns "000" on failure.
http_probe() {
    curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${DOMAIN}:443:127.0.0.1" \
        "https://${DOMAIN}/" \
        --max-time "${HTTP_TIMEOUT}" 2>/dev/null || echo "000"
}

# Background loop: probe HTTP every 2s and log any non-2xx/3xx to error file.
# Runs until the process is killed by cleanup().
continuous_http_probe() {
    local errors=0
    : > "${HTTP_ERROR_LOG}"   # truncate / create
    while true; do
        code=$(curl -sk -o /dev/null -w "%{http_code}" \
            --resolve "${DOMAIN}:443:127.0.0.1" \
            "https://${DOMAIN}/" \
            --max-time "${HTTP_TIMEOUT}" 2>/dev/null || echo "000")
        if [[ "${code}" != "200" ]] && [[ "${code}" != "301" ]] && [[ "${code}" != "302" ]]; then
            errors=$((errors + 1))
            echo "${code}" >> "${HTTP_ERROR_LOG}"
        fi
        sleep 2
    done
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix HPA Scale-Up Latency Integration Test"
echo ""
echo "  Namespace:              ${NAMESPACE}"
echo "  HPA:                    ${HPA_NAME}"
echo "  Deployment:             ${DEPLOYMENT_NAME}"
echo "  Load script:            ${LOAD_TEST_SCRIPT}"
echo "  HPA CPU target:         ${HPA_CPU_TARGET}%"
echo "  HPA min/max replicas:   ${HPA_MIN_REPLICAS} / ${HPA_MAX_REPLICAS}"
echo ""
echo "  Phase latency thresholds:"
echo "    CPU breach timeout:      ${CPU_BREACH_TIMEOUT}s"
echo "    HPA decision timeout:    ${HPA_DECISION_TIMEOUT}s  (after CPU breach)"
echo "    First pod ready timeout: ${FIRST_POD_READY_TIMEOUT}s  (after HPA decision)"
echo "    Full capacity timeout:   ${FULL_CAPACITY_TIMEOUT}s  (after HPA decision)"
echo ""

for cmd in kubectl k6 curl bc; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "ERROR: '${cmd}' not found in PATH."
        exit 1
    fi
done

if [[ ! -f "${LOAD_TEST_SCRIPT}" ]]; then
    echo "ERROR: Load test script not found: ${LOAD_TEST_SCRIPT}"
    exit 1
fi

if ! kubectl get hpa "${HPA_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: HPA '${HPA_NAME}' not found in namespace '${NAMESPACE}'."
    exit 1
fi

if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Deployment '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'."
    exit 1
fi

# Verify metrics-server is available — HPA cannot work without it
metrics_available=$(kubectl top pods -n "${NAMESPACE}" &>/dev/null && echo "yes" || echo "no")
if [[ "${metrics_available}" == "no" ]]; then
    echo "ERROR: 'kubectl top pods' failed — metrics-server may not be running."
    echo "       Deploy k8s/metrics-server.yaml or run infra/setup-metrics-server.sh first."
    exit 1
fi
info "metrics-server is available"

# ---------------------------------------------------------------------------
# IT-01: Baseline — HPA at minReplicas, CPU below threshold
#
# Before starting the load we need to confirm the cluster is idle so the
# latency measurements start from a clean, well-defined state. If the cluster
# is already under load the phase timers would be meaningless.
# ---------------------------------------------------------------------------

header "IT-01: Baseline — HPA at minReplicas (${HPA_MIN_REPLICAS}), CPU below ${HPA_CPU_TARGET}%"

baseline_desired=$(get_hpa_desired)
baseline_current=$(get_hpa_current)
baseline_cpu=$(get_hpa_cpu)
baseline_running=$(get_running_pods)

info "HPA desired: ${baseline_desired}, current: ${baseline_current}"
info "CPU utilization (HPA): ${baseline_cpu:-<not yet scraped>}%"
info "Running Laravel pods: ${baseline_running}"

# Capture pod names before load — used in the timeline summary
PODS_BEFORE=$(get_all_pod_names)
info "Pod names before load: ${PODS_BEFORE}"

baseline_ok=true

if [[ "${baseline_desired:-0}" -ne "${HPA_MIN_REPLICAS}" ]] 2>/dev/null; then
    info "WARNING: HPA desiredReplicas=${baseline_desired}, expected ${HPA_MIN_REPLICAS}"
    info "         Waiting 30s for HPA to settle back to minReplicas..."
    sleep 30
    baseline_desired=$(get_hpa_desired)
    if [[ "${baseline_desired:-0}" -ne "${HPA_MIN_REPLICAS}" ]] 2>/dev/null; then
        baseline_ok=false
    fi
fi

# CPU threshold: warn if already above target (test may have inflated timers)
# but don't fail — a brief spike is not uncommon right after boot.
if [[ -n "${baseline_cpu}" ]] && [[ "${baseline_cpu}" -ge "${HPA_CPU_TARGET}" ]] 2>/dev/null; then
    info "WARNING: CPU already at ${baseline_cpu}% (≥ ${HPA_CPU_TARGET}%) before load starts"
    info "         CPU breach timestamp may be inaccurate for this run"
fi

if [[ "${baseline_ok}" == "true" ]]; then
    pass "IT-01: HPA at ${baseline_desired} replicas (minReplicas=${HPA_MIN_REPLICAS}), baseline is clean"
else
    fail "IT-01: HPA desiredReplicas=${baseline_desired}, expected ${HPA_MIN_REPLICAS} — cluster is not idle"
    info "       Run the test again after the HPA stabilises (scaleDown window is 30s)"
fi

# ---------------------------------------------------------------------------
# Start load and background HTTP error monitor
# ---------------------------------------------------------------------------

header "Starting k6 load test and continuous HTTP error monitor"

# Start background HTTP error monitor — records every non-2xx/3xx response
# seen during the test window. This feeds IT-06.
continuous_http_probe &
HTTP_PROBE_PID=$!
info "HTTP error monitor started (PID ${HTTP_PROBE_PID})"

# Start k6
k6 run "${LOAD_TEST_SCRIPT}" > "${K6_OUTPUT_FILE}" 2>&1 &
K6_PID=$!
LOAD_START_TS=$(date +%s)
info "k6 started (PID ${K6_PID}) at $(date '+%H:%M:%S') — t=0"

# ---------------------------------------------------------------------------
# IT-02: Phase 1 — CPU breach latency
#
# Measures how long after load starts until the HPA sees avg CPU ≥ target.
# This depends on k6 ramp-up speed and the metrics-server scrape interval
# (default 15s in k3s). Threshold: CPU_BREACH_TIMEOUT seconds.
#
# We read CPU from the HPA's .status.currentMetrics because that is the
# value the HPA controller actually uses for its decisions — not kubectl top,
# which shows instantaneous pod-level CPU and may differ from the HPA's view.
# ---------------------------------------------------------------------------

header "IT-02: Phase 1 — CPU breach (avg utilization ≥ ${HPA_CPU_TARGET}% within ${CPU_BREACH_TIMEOUT}s)"

elapsed=0
cpu_breached=false
CPU_BREACH_TS=0
cpu_at_breach=0

while [[ ${elapsed} -lt ${CPU_BREACH_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    current_cpu=$(get_hpa_cpu)
    current_cpu="${current_cpu:-0}"
    desired=$(get_hpa_desired)

    info "  [t+${elapsed}s] HPA CPU: ${current_cpu}%, desired replicas: ${desired}"

    if [[ "${current_cpu}" -ge "${HPA_CPU_TARGET}" ]] 2>/dev/null; then
        cpu_breached=true
        CPU_BREACH_TS=$(date +%s)
        cpu_at_breach="${current_cpu}"
        break
    fi

    # Also accept HPA already deciding to scale up as implicit proof of breach
    if [[ "${desired:-0}" -gt "${HPA_MIN_REPLICAS}" ]] 2>/dev/null; then
        info "  HPA desiredReplicas already increased to ${desired} — CPU breach implicit"
        cpu_breached=true
        CPU_BREACH_TS=$(date +%s)
        cpu_at_breach="≥${HPA_CPU_TARGET} (inferred from HPA decision)"
        break
    fi

    if ! kill -0 "${K6_PID}" 2>/dev/null; then
        info "  k6 exited early — stopping CPU breach poll"
        break
    fi
done

CPU_BREACH_LATENCY=$((CPU_BREACH_TS - LOAD_START_TS))

if [[ "${cpu_breached}" == "true" ]]; then
    pass "IT-02: CPU breached ${HPA_CPU_TARGET}% threshold in ${CPU_BREACH_LATENCY}s (measured: ${cpu_at_breach}%)"
else
    fail "IT-02: CPU did NOT reach ${HPA_CPU_TARGET}% within ${CPU_BREACH_TIMEOUT}s — load may be insufficient or metrics-server is not scraping"
    CPU_BREACH_TS=$(date +%s)   # set to now so subsequent phases still run
fi

# ---------------------------------------------------------------------------
# IT-03: Phase 2 — HPA decision latency
#
# Measures how long after the CPU breach until the HPA controller increases
# desiredReplicas above minReplicas. This is bounded by:
#   stabilizationWindowSeconds: 15  (must stay above threshold for 15s)
#   + one metrics scrape interval   (~15s default)
# So the theoretical minimum is ~15s and a reasonable upper bound is 45s.
#
# We time from CPU_BREACH_TS, not from LOAD_START_TS, so the measurement
# isolates the HPA controller's reaction time only.
# ---------------------------------------------------------------------------

header "IT-03: Phase 2 — HPA decision latency (desiredReplicas > ${HPA_MIN_REPLICAS} within ${HPA_DECISION_TIMEOUT}s of CPU breach)"

HPA_DECISION_PHASE_START=$(date +%s)
elapsed=0
hpa_decided=false
HPA_DECISION_TS=0
replicas_decided=0

while [[ ${elapsed} -lt ${HPA_DECISION_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    desired=$(get_hpa_desired)
    desired="${desired:-0}"
    current_cpu=$(get_hpa_cpu)

    info "  [+${elapsed}s after CPU breach] HPA desired: ${desired}, CPU: ${current_cpu:-?}%"

    if [[ "${desired}" -gt "${HPA_MIN_REPLICAS}" ]] 2>/dev/null; then
        hpa_decided=true
        HPA_DECISION_TS=$(date +%s)
        replicas_decided="${desired}"
        break
    fi

    if ! kill -0 "${K6_PID}" 2>/dev/null; then
        info "  k6 exited early — stopping HPA decision poll"
        break
    fi
done

HPA_DECISION_LATENCY=$((HPA_DECISION_TS - CPU_BREACH_TS))

if [[ "${hpa_decided}" == "true" ]]; then
    threshold_ok=$(echo "${HPA_DECISION_LATENCY} <= ${HPA_DECISION_TIMEOUT}" | bc -l 2>/dev/null || echo "1")
    if [[ "${threshold_ok}" == "1" ]]; then
        pass "IT-03: HPA decided to scale to ${replicas_decided} replicas in ${HPA_DECISION_LATENCY}s after CPU breach (≤ ${HPA_DECISION_TIMEOUT}s threshold)"
    else
        fail "IT-03: HPA decision took ${HPA_DECISION_LATENCY}s — exceeds ${HPA_DECISION_TIMEOUT}s threshold"
    fi
else
    fail "IT-03: HPA did NOT increase desiredReplicas within ${HPA_DECISION_TIMEOUT}s of CPU breach (current desired: $(get_hpa_desired))"
    HPA_DECISION_TS=$(date +%s)   # set to now so subsequent phases still run
fi

# ---------------------------------------------------------------------------
# IT-04: Phase 3 — First-pod ready latency
#
# Measures how long after the HPA decision until the FIRST new pod transitions
# to Running. This covers:
#   - ReplicaSet creating the new pod spec
#   - Scheduler assigning it to the node
#   - kubelet pulling (already cached) image and starting PHP-FPM
#   - initContainer completing (mkdir storage dirs)
#   - readinessProbe succeeding (tcpSocket :9000, initialDelaySeconds: 5)
#
# Since the image is already cached in k3s containerd from build-and-import.sh,
# pull time is ~0. The dominant factor is PHP-FPM startup + initContainer.
# Threshold: FIRST_POD_READY_TIMEOUT (default 60s).
#
# We track new pods by comparing names against PODS_BEFORE. A pod is "new"
# if its name was not in the pre-load set.
# ---------------------------------------------------------------------------

header "IT-04: Phase 3 — First new pod Running within ${FIRST_POD_READY_TIMEOUT}s of HPA decision"

elapsed=0
first_pod_ready=false
FIRST_POD_READY_TS=0
first_new_pod_name=""

while [[ ${elapsed} -lt ${FIRST_POD_READY_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    # Get names of pods currently in Running phase
    running_names=$(kubectl get pods -n "${NAMESPACE}" -l app=laravel \
        --field-selector=status.phase=Running --no-headers 2>/dev/null \
        | awk '{print $1}' | tr '\n' ' ')

    new_running=""
    for pod in ${running_names}; do
        if ! echo "${PODS_BEFORE}" | grep -qw "${pod}"; then
            new_running="${pod}"
            break
        fi
    done

    running_count=$(echo "${running_names}" | wc -w | tr -d '[:space:]')
    info "  [+${elapsed}s after HPA decision] Running pods: ${running_count}, new pod Running: ${new_running:-none yet}"

    if [[ -n "${new_running}" ]]; then
        first_pod_ready=true
        FIRST_POD_READY_TS=$(date +%s)
        first_new_pod_name="${new_running}"
        break
    fi

    if ! kill -0 "${K6_PID}" 2>/dev/null; then
        info "  k6 exited early — stopping first-pod poll"
        break
    fi
done

FIRST_POD_LATENCY=$((FIRST_POD_READY_TS - HPA_DECISION_TS))

if [[ "${first_pod_ready}" == "true" ]]; then
    threshold_ok=$(echo "${FIRST_POD_LATENCY} <= ${FIRST_POD_READY_TIMEOUT}" | bc -l 2>/dev/null || echo "1")
    if [[ "${threshold_ok}" == "1" ]]; then
        pass "IT-04: First new pod '${first_new_pod_name}' Running in ${FIRST_POD_LATENCY}s after HPA decision (≤ ${FIRST_POD_READY_TIMEOUT}s threshold)"
    else
        fail "IT-04: First new pod took ${FIRST_POD_LATENCY}s to reach Running — exceeds ${FIRST_POD_READY_TIMEOUT}s threshold"
    fi
else
    fail "IT-04: No new pod reached Running within ${FIRST_POD_READY_TIMEOUT}s of HPA decision"
    FIRST_POD_READY_TS=$(date +%s)
fi

# ---------------------------------------------------------------------------
# IT-05: Phase 4 — Full capacity latency
#
# Measures how long after the HPA decision until ALL new pods are Running
# (i.e., readyReplicas == desiredReplicas). This is the moment at which the
# cluster is operating at full scaled capacity with no degraded throughput.
#
# The HPA policy allows adding 4 pods per 15s, so with desiredReplicas=6
# (for example), two batches of 4 may be needed. The threshold accounts for
# multiple batches: FULL_CAPACITY_TIMEOUT (default 90s).
# ---------------------------------------------------------------------------

header "IT-05: Phase 4 — Full capacity within ${FULL_CAPACITY_TIMEOUT}s of HPA decision"

elapsed=0
full_capacity=false
FULL_CAPACITY_TS=0
final_replicas=0

while [[ ${elapsed} -lt ${FULL_CAPACITY_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    desired=$(get_hpa_desired)
    desired="${desired:-0}"
    ready=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null | tr -d '[:space:]')
    ready="${ready:-0}"

    info "  [+${elapsed}s after HPA decision] desired=${desired}, readyReplicas=${ready}"

    # Full capacity: all desired replicas are ready AND we have scaled above min
    if [[ "${desired}" -gt "${HPA_MIN_REPLICAS}" ]] && \
       [[ "${ready}" -ge "${desired}" ]] && \
       [[ "${desired}" -gt 0 ]] 2>/dev/null; then
        full_capacity=true
        FULL_CAPACITY_TS=$(date +%s)
        final_replicas="${ready}"
        break
    fi

    if ! kill -0 "${K6_PID}" 2>/dev/null; then
        info "  k6 exited — stopping full-capacity poll"
        # Do a final check after k6 ends
        desired=$(get_hpa_desired)
        ready=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null | tr -d '[:space:]')
        ready="${ready:-0}"
        if [[ "${desired:-0}" -gt "${HPA_MIN_REPLICAS}" ]] && \
           [[ "${ready}" -ge "${desired:-0}" ]] 2>/dev/null; then
            full_capacity=true
            FULL_CAPACITY_TS=$(date +%s)
            final_replicas="${ready}"
        fi
        break
    fi
done

FULL_CAPACITY_LATENCY=$((FULL_CAPACITY_TS - HPA_DECISION_TS))

if [[ "${full_capacity}" == "true" ]]; then
    threshold_ok=$(echo "${FULL_CAPACITY_LATENCY} <= ${FULL_CAPACITY_TIMEOUT}" | bc -l 2>/dev/null || echo "1")
    if [[ "${threshold_ok}" == "1" ]]; then
        pass "IT-05: Full capacity (${final_replicas} pods ready) reached in ${FULL_CAPACITY_LATENCY}s after HPA decision (≤ ${FULL_CAPACITY_TIMEOUT}s threshold)"
    else
        fail "IT-05: Full capacity took ${FULL_CAPACITY_LATENCY}s — exceeds ${FULL_CAPACITY_TIMEOUT}s threshold"
    fi
else
    final_desired=$(get_hpa_desired)
    final_ready=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null | tr -d '[:space:]')
    fail "IT-05: Full capacity NOT reached within ${FULL_CAPACITY_TIMEOUT}s (desired=${final_desired:-?}, ready=${final_ready:-0})"
fi

# Wait for k6 to finish before evaluating HTTP errors
if kill -0 "${K6_PID}" 2>/dev/null; then
    info "Waiting for k6 to complete..."
    wait "${K6_PID}" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# IT-06: No HTTP errors during the scale-up window
#
# Stop the background HTTP probe and count how many non-2xx/3xx responses
# were logged. Zero errors means the HPA scale-up was transparent to users —
# Kubernetes routed traffic only to Ready pods (readiness gate working).
#
# We allow a small tolerance (≤ 3 errors) because there is a brief window
# during pod initialisation where the kube-proxy endpoint table update and
# the readiness probe period (5s) may overlap, causing at most one or two
# requests to hit a pod that is not yet serving. More than 3 errors indicates
# a systematic problem (e.g. requests hitting non-ready pods due to a
# misconfigured readiness probe).
# ---------------------------------------------------------------------------

header "IT-06: HTTP error count during scale-up window (tolerance ≤ 3)"

# Stop the background probe
if [[ -n "${HTTP_PROBE_PID}" ]] && kill -0 "${HTTP_PROBE_PID}" 2>/dev/null; then
    kill "${HTTP_PROBE_PID}" 2>/dev/null || true
    wait "${HTTP_PROBE_PID}" 2>/dev/null || true
    HTTP_PROBE_PID=""
fi

http_error_count=0
if [[ -f "${HTTP_ERROR_LOG}" ]]; then
    http_error_count=$(wc -l < "${HTTP_ERROR_LOG}" | tr -d '[:space:]')
    if [[ "${http_error_count}" -gt 0 ]]; then
        info "  HTTP error codes observed during scale-up:"
        sort "${HTTP_ERROR_LOG}" | uniq -c | while read -r count code; do
            info "    HTTP ${code} × ${count}"
        done
    fi
fi
info "  Total non-2xx/3xx responses during scale-up: ${http_error_count}"

if [[ "${http_error_count}" -le 3 ]] 2>/dev/null; then
    pass "IT-06: HTTP errors during scale-up = ${http_error_count} (≤ 3 tolerance) — scale-up was transparent to users"
else
    fail "IT-06: ${http_error_count} HTTP errors observed during scale-up — readiness probes may not be filtering unready pods correctly"
fi

# ---------------------------------------------------------------------------
# Summary — timeline table + pass/fail counts
# ---------------------------------------------------------------------------

LOAD_END_TS=$(date +%s)
TOTAL_ELAPSED=$((LOAD_END_TS - LOAD_START_TS))

header "HPA SCALE-UP LATENCY TEST SUMMARY"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │                  Scale-Up Timeline                          │"
echo "  ├──────────────────────────────┬──────────────┬──────────────┤"
echo "  │ Phase                        │ Latency (s)  │ Threshold    │"
echo "  ├──────────────────────────────┼──────────────┼──────────────┤"

# Phase 1: load start → CPU breach
p1=$((CPU_BREACH_TS - LOAD_START_TS))
printf "  │ %-28s │ %12s │ %12s │\n" \
    "Phase 1: CPU breach" \
    "${p1}s" \
    "≤ ${CPU_BREACH_TIMEOUT}s"

# Phase 2: CPU breach → HPA decision
p2="${HPA_DECISION_LATENCY:-?}"
printf "  │ %-28s │ %12s │ %12s │\n" \
    "Phase 2: HPA decision" \
    "${p2}s" \
    "≤ ${HPA_DECISION_TIMEOUT}s"

# Phase 3: HPA decision → first pod Running
p3="${FIRST_POD_LATENCY:-?}"
printf "  │ %-28s │ %12s │ %12s │\n" \
    "Phase 3: First pod Running" \
    "${p3}s" \
    "≤ ${FIRST_POD_READY_TIMEOUT}s"

# Phase 4: HPA decision → full capacity
p4="${FULL_CAPACITY_LATENCY:-?}"
printf "  │ %-28s │ %12s │ %12s │\n" \
    "Phase 4: Full capacity" \
    "${p4}s" \
    "≤ ${FULL_CAPACITY_TIMEOUT}s"

echo "  ├──────────────────────────────┼──────────────┼──────────────┤"
printf "  │ %-28s │ %12s │ %12s │\n" \
    "Total test duration" \
    "${TOTAL_ELAPSED}s" \
    ""
echo "  └──────────────────────────────┴──────────────┴──────────────┘"
echo ""
echo "  HTTP errors during scale-up:  ${http_error_count}"
echo "  Final replica count:          ${final_replicas:-$(get_hpa_current)}"
echo "  Pod names before load:        ${PODS_BEFORE}"
echo "  Pod names after scale-up:     $(get_all_pod_names)"
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
    echo -e "  \033[32m✓ All ${TOTAL} scale-up latency tests PASSED\033[0m"
    echo ""
    exit 0
fi
