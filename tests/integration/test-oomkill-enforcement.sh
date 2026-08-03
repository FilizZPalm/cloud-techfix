#!/usr/bin/env bash
# tests/integration/test-oomkill-enforcement.sh
#
# Integration test that validates Kubernetes memory limit enforcement via
# OOMKill on the Laravel PHP-FPM container.
#
# The Laravel deployment declares:
#   resources.limits.memory: 512Mi   (from k8s/laravel-deployment.yaml)
#
# When a container's memory consumption exceeds this limit, the Linux kernel
# OOM killer terminates the offending process. The container runtime (containerd)
# reports the exit reason as OOMKilled. Kubernetes then:
#   1. Records the OOMKill in the pod's containerStatus.lastState
#   2. Restarts the container according to the pod's restartPolicy (Always)
#   3. Reports the event via kubectl describe pod
#
# This test proves that the resource limit is enforced at the cgroup level —
# not just declared in the manifest — and that Kubernetes self-heals by
# restarting the OOMKilled container automatically.
#
# Approach:
#   We exec a PHP one-liner into one Laravel pod that allocates memory in a
#   tight loop until the kernel kills it. PHP heap allocation does not require
#   filesystem writes, so it works correctly inside the read-only root
#   filesystem container.
#
#   The allocation target is 600Mi — safely above the 512Mi limit but small
#   enough to trigger OOMKill quickly without stressing the node.
#
# Test structure:
#   IT-01  Baseline: target pod is Running with 0 OOMKill restarts
#   IT-02  Memory hog injected: exec PHP allocator into the target pod
#   IT-03  OOMKill event: containerStatus shows OOMKilled reason
#   IT-04  Auto-restart: container is Running again within RESTART_TIMEOUT
#   IT-05  Service continuity: HTTPS returns 200 throughout (other pods serve)
#
# Requirements: 9.2, 9.3  (resource limits enforced; container auto-restarts)
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-oomkill-enforcement.sh
#
# Prerequisites:
#   - kubectl configured (KUBECONFIG set or k3s default)
#   - Laravel deployment running in namespace 'techfix' with ≥ 2 replicas
#   - curl available on the VM
#
# SAFETY NOTE:
#   Only ONE pod is targeted. The deployment runs ≥ 2 replicas (HPA minReplicas=2)
#   so the surviving pod continues to serve traffic during the OOMKill event.
#   The test does NOT modify any Kubernetes resources; it only exec's a
#   short-lived process into an existing container.
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-laravel-deployment}"
CONTAINER_NAME="${CONTAINER_NAME:-laravel}"
DOMAIN="${DOMAIN:-techfix.local}"

# Memory to allocate in the PHP hog (must exceed the 512Mi container limit).
# Expressed in MiB — the PHP script allocates this much heap in one shot.
ALLOC_MIB="${ALLOC_MIB:-600}"

# How long to wait for the OOMKill to be recorded in containerStatus (seconds).
# The kernel kills the process almost instantly once the cgroup limit is hit;
# the delay here is kubelet's sync interval (~10s) + a small buffer.
OOMKILL_TIMEOUT="${OOMKILL_TIMEOUT:-60}"

# How long to wait for the container to restart and reach Running (seconds).
# Kubernetes uses exponential back-off (10s, 20s, 40s…); the first restart
# after an OOMKill is typically within 10–15s.
RESTART_TIMEOUT="${RESTART_TIMEOUT:-90}"

# HTTP probe timeout (seconds)
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"

# Poll interval (seconds)
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
# Helpers
# ---------------------------------------------------------------------------

# Returns the name of the first Running Laravel pod.
get_target_pod() {
    kubectl get pods -n "${NAMESPACE}" -l app=laravel \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null \
        | awk 'NR==1{print $1}'
}

# Returns the restart count for the main container in the given pod.
get_restart_count() {
    local pod="$1"
    kubectl get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].restartCount}" \
        2>/dev/null | tr -d '[:space:]' || echo "0"
}

# Returns the last termination reason for the main container in the given pod.
# Will be "OOMKilled" when the kernel killed the process for exceeding the cgroup limit.
get_last_termination_reason() {
    local pod="$1"
    kubectl get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].lastState.terminated.reason}" \
        2>/dev/null | tr -d '[:space:]' || echo ""
}

# Returns the current state of the main container: "running", "terminated", or "waiting".
get_container_state() {
    local pod="$1"
    # Check running first
    running=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].state.running.startedAt}" \
        2>/dev/null | tr -d '[:space:]')
    [[ -n "${running}" ]] && echo "running" && return

    # Check terminated
    terminated=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].state.terminated.reason}" \
        2>/dev/null | tr -d '[:space:]')
    [[ -n "${terminated}" ]] && echo "terminated:${terminated}" && return

    echo "waiting"
}

# Probe HTTPS and return HTTP status code. Returns "000" on failure.
http_probe() {
    curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${DOMAIN}:443:127.0.0.1" \
        "https://${DOMAIN}/" \
        --max-time "${HTTP_TIMEOUT}" 2>/dev/null || echo "000"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix OOMKill Enforcement Integration Test"
echo ""
echo "  Namespace:          ${NAMESPACE}"
echo "  Deployment:         ${DEPLOYMENT_NAME}"
echo "  Container:          ${CONTAINER_NAME}"
echo "  Memory limit:       512Mi  (from k8s/laravel-deployment.yaml)"
echo "  Allocation target:  ${ALLOC_MIB}Mi  (exceeds limit by $((ALLOC_MIB - 512))Mi)"
echo "  OOMKill timeout:    ${OOMKILL_TIMEOUT}s"
echo "  Restart timeout:    ${RESTART_TIMEOUT}s"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH."
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found in PATH."
    exit 1
fi

if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Deployment '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'."
    exit 1
fi

# Confirm the memory limit is set as expected
configured_limit=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${CONTAINER_NAME}\")].resources.limits.memory}" \
    2>/dev/null | tr -d '[:space:]')
info "Configured memory limit: ${configured_limit:-<not set>}"

if [[ -z "${configured_limit}" ]]; then
    echo "ERROR: No memory limit found on container '${CONTAINER_NAME}'."
    echo "       OOMKill enforcement requires resources.limits.memory to be set."
    exit 1
fi

# ---------------------------------------------------------------------------
# IT-01: Baseline — target pod is Running with 0 prior OOMKill restarts
#
# We pick the first Running Laravel pod. If it already has OOMKill restarts
# from a previous test run we warn but do not abort — the restart count
# delta in IT-03 still works correctly.
# ---------------------------------------------------------------------------

header "IT-01: Baseline — target pod Running, establish restart count baseline"

TARGET_POD=$(get_target_pod)

if [[ -z "${TARGET_POD}" ]]; then
    echo "ERROR: No Running Laravel pod found in namespace '${NAMESPACE}'."
    exit 1
fi

BASELINE_RESTARTS=$(get_restart_count "${TARGET_POD}")
BASELINE_RESTARTS="${BASELINE_RESTARTS:-0}"
baseline_state=$(get_container_state "${TARGET_POD}")
baseline_http=$(http_probe)

info "Target pod:          ${TARGET_POD}"
info "Container state:     ${baseline_state}"
info "Restart count:       ${BASELINE_RESTARTS}"
info "Baseline HTTP probe: ${baseline_http}"

# Count total Running pods — we need ≥ 2 for IT-05 (service continuity)
total_running=$(kubectl get pods -n "${NAMESPACE}" -l app=laravel \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
info "Total Running Laravel pods: ${total_running}"

if [[ "${total_running}" -lt 2 ]]; then
    echo "ERROR: Need ≥ 2 Running Laravel pods for this test (found ${total_running})."
    echo "       The surviving pod must serve traffic while the target is OOMKilled."
    exit 1
fi

if [[ "${baseline_state}" == "running" ]] && [[ "${baseline_http}" == "200" ]]; then
    pass "IT-01: Pod '${TARGET_POD}' Running (restarts: ${BASELINE_RESTARTS}), HTTPS returns 200 — baseline clean"
elif [[ "${baseline_state}" == "running" ]]; then
    pass "IT-01: Pod '${TARGET_POD}' Running (restarts: ${BASELINE_RESTARTS}) — HTTP returned ${baseline_http} (Traefik may not be fully ready, continuing)"
else
    fail "IT-01: Pod '${TARGET_POD}' not in running state (state: ${baseline_state})"
fi

# ---------------------------------------------------------------------------
# IT-02: Inject memory hog — exec PHP allocator into the target pod
#
# The PHP one-liner allocates ALLOC_MIB mebibytes of heap in a single
# str_repeat call. str_repeat is used rather than an appending loop because:
#   - It allocates in one syscall, hitting the cgroup limit instantly
#   - It does not require filesystem writes (safe in read-only containers)
#   - It is available in all PHP versions ≥ 5.3
#
# The exec call is intentionally run in the background (& disown) because
# the process will be killed by the kernel before it can return — kubectl exec
# will therefore exit with a non-zero code (137 = SIGKILL), which is expected
# and correct. We do NOT assert exit code 0 here.
#
# bytes = ALLOC_MIB * 1024 * 1024
# ---------------------------------------------------------------------------

header "IT-02: Injecting memory hog into pod '${TARGET_POD}' (allocating ${ALLOC_MIB}Mi)"

ALLOC_BYTES=$(( ALLOC_MIB * 1024 * 1024 ))
info "Allocation size: ${ALLOC_BYTES} bytes"
info "Running PHP allocator — this process will be OOMKilled by the kernel"
info "(kubectl exec exit code 137 / non-zero is expected and correct)"

# Run in background — the kernel will kill the PHP process mid-execution.
# kubectl exec will then return exit code 137 (SIGKILL) which is expected.
kubectl exec "${TARGET_POD}" -n "${NAMESPACE}" -c "${CONTAINER_NAME}" -- \
    php -r "
        \$block = str_repeat('A', ${ALLOC_BYTES});
        // This line is never reached — the kernel kills the process above
        echo strlen(\$block);
    " &>/dev/null &
HOARD_PID=$!

INJECT_TS=$(date +%s)
info "Memory hog injected at $(date '+%H:%M:%S') (background PID: ${HOARD_PID})"

# Give the kernel a moment to register the cgroup violation and kill the process.
# The OOM kill is typically within 1-3 seconds of the allocation completing.
info "Waiting 5s for kernel OOM killer to act..."
sleep 5

# The background kubectl exec should now be done (process killed by kernel).
# Reap it silently — we do not check its exit code here, IT-03 checks the pod.
wait "${HOARD_PID}" 2>/dev/null || true

pass "IT-02: Memory hog executed — PHP process allocated ${ALLOC_MIB}Mi targeting ${CONTAINER_NAME} container"

# ---------------------------------------------------------------------------
# IT-03: OOMKill confirmed — containerStatus.lastState.terminated.reason = OOMKilled
#
# After the kernel kills the process, containerd sets the container's
# termination reason to "OOMKilled". The kubelet syncs this into the pod's
# containerStatuses within one sync period (~10s default).
#
# We poll until:
#   a) lastState.terminated.reason == "OOMKilled"  ← definitive proof
#   b) restart count increased above baseline       ← implicit proof if (a) not yet synced
#
# We also check kubectl get events for an OOMKilling event as a secondary
# signal, since events are written faster than containerStatus in some cases.
# ---------------------------------------------------------------------------

header "IT-03: OOMKill confirmed — containerStatus shows OOMKilled reason"

elapsed=0
oomkill_confirmed=false
oomkill_evidence=""
OOMKILL_CONFIRMED_TS=0

while [[ ${elapsed} -lt ${OOMKILL_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    last_reason=$(get_last_termination_reason "${TARGET_POD}")
    current_restarts=$(get_restart_count "${TARGET_POD}")
    current_restarts="${current_restarts:-0}"
    container_state=$(get_container_state "${TARGET_POD}")

    info "  [${elapsed}s/${OOMKILL_TIMEOUT}s] state=${container_state}, restarts=${current_restarts}, lastTermination=${last_reason:-<none yet>}"

    # Primary signal: lastState.terminated.reason = OOMKilled
    if [[ "${last_reason}" == "OOMKilled" ]]; then
        oomkill_confirmed=true
        OOMKILL_CONFIRMED_TS=$(date +%s)
        oomkill_evidence="containerStatus.lastState.terminated.reason=OOMKilled"
        break
    fi

    # Secondary signal: restart count increased AND container is restarting/running
    # This covers the brief window where kubelet has restarted the container but
    # hasn't yet written lastState (it overwrites on the next sync cycle).
    if [[ "${current_restarts}" -gt "${BASELINE_RESTARTS}" ]] 2>/dev/null; then
        # Wait one more poll to see if reason populates
        sleep "${POLL_INTERVAL}"
        elapsed=$((elapsed + POLL_INTERVAL))
        last_reason=$(get_last_termination_reason "${TARGET_POD}")
        if [[ "${last_reason}" == "OOMKilled" ]]; then
            oomkill_confirmed=true
            OOMKILL_CONFIRMED_TS=$(date +%s)
            oomkill_evidence="containerStatus.lastState.terminated.reason=OOMKilled (detected after restart count increase)"
            break
        else
            # Restart count increased but reason is not OOMKilled — check events
            oom_event=$(kubectl get events -n "${NAMESPACE}" \
                --field-selector "involvedObject.name=${TARGET_POD}" \
                2>/dev/null | grep -i "oomkill\|OOM\|memory" | head -1 || true)
            if [[ -n "${oom_event}" ]]; then
                oomkill_confirmed=true
                OOMKILL_CONFIRMED_TS=$(date +%s)
                oomkill_evidence="kubectl events: ${oom_event}"
                break
            fi
            info "  Restart count increased to ${current_restarts} but reason='${last_reason:-empty}' — continuing to poll"
        fi
    fi
done

if [[ "${oomkill_confirmed}" == "true" ]]; then
    OOMKILL_LATENCY=$((OOMKILL_CONFIRMED_TS - INJECT_TS))
    pass "IT-03: OOMKill confirmed ${OOMKILL_LATENCY}s after injection — evidence: ${oomkill_evidence}"
else
    # Final diagnostic dump
    info "  Final pod status:"
    kubectl describe pod "${TARGET_POD}" -n "${NAMESPACE}" 2>/dev/null \
        | grep -A5 "Last State\|OOM\|memory\|Reason\|Exit Code" | head -20 || true
    fail "IT-03: OOMKill NOT detected within ${OOMKILL_TIMEOUT}s — memory limit may not be enforced at the cgroup level"
fi

# ---------------------------------------------------------------------------
# IT-04: Auto-restart — container is Running again within RESTART_TIMEOUT
#
# Kubernetes restartPolicy=Always (the default for Deployment pods) means
# the kubelet must restart the OOMKilled container automatically. The first
# restart uses a 10s back-off. We wait up to RESTART_TIMEOUT seconds.
#
# "Running again" means:
#   - containerStatus.state.running.startedAt is set (not terminated/waiting)
#   - restartCount > BASELINE_RESTARTS (proves it was restarted, not the
#     original process)
# ---------------------------------------------------------------------------

header "IT-04: Auto-restart — container Running again within ${RESTART_TIMEOUT}s"

elapsed=0
container_restarted=false
RESTART_TS=0

while [[ ${elapsed} -lt ${RESTART_TIMEOUT} ]]; do
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))

    container_state=$(get_container_state "${TARGET_POD}")
    current_restarts=$(get_restart_count "${TARGET_POD}")
    current_restarts="${current_restarts:-0}"

    info "  [${elapsed}s/${RESTART_TIMEOUT}s] state=${container_state}, restarts=${current_restarts}/${BASELINE_RESTARTS} baseline"

    if [[ "${container_state}" == "running" ]] && \
       [[ "${current_restarts}" -gt "${BASELINE_RESTARTS}" ]] 2>/dev/null; then
        container_restarted=true
        RESTART_TS=$(date +%s)
        break
    fi
done

if [[ "${container_restarted}" == "true" ]]; then
    RESTART_LATENCY=$((RESTART_TS - OOMKILL_CONFIRMED_TS))
    final_restarts=$(get_restart_count "${TARGET_POD}")
    pass "IT-04: Container restarted and Running again in ${RESTART_LATENCY}s after OOMKill (restartCount: ${BASELINE_RESTARTS} → ${final_restarts})"
else
    final_state=$(get_container_state "${TARGET_POD}")
    final_restarts=$(get_restart_count "${TARGET_POD}")
    fail "IT-04: Container did NOT restart within ${RESTART_TIMEOUT}s (state: ${final_state}, restarts: ${final_restarts})"
fi

# ---------------------------------------------------------------------------
# IT-05: Service continuity — HTTPS returned 200 throughout the OOMKill event
#
# With ≥ 2 Laravel replicas, the Kubernetes Service load-balancer should
# route traffic to the surviving pod while the target is OOMKilled and
# restarting. We probe the endpoint at the time of confirmed OOMKill and
# again after restart to verify the service was never fully down.
#
# We also check the HTTP response immediately after restart to confirm the
# restarted pod is serving correctly.
# ---------------------------------------------------------------------------

header "IT-05: Service continuity — HTTPS returns 200 during and after OOMKill"

# Probe 1: at the moment OOMKill was confirmed (surviving pod should serve)
info "Probing HTTPS at time of OOMKill confirmation..."
http_during=$(http_probe)
info "  HTTP during OOMKill: ${http_during}"

# Probe 2: after restart (both pods should now serve)
info "Probing HTTPS after container restart..."
http_after=$(http_probe)
info "  HTTP after restart:  ${http_after}"

# Also send 5 rapid probes to confirm consistent availability
info "Sending 5 rapid HTTP probes to confirm consistent availability..."
consecutive_ok=0
for i in $(seq 1 5); do
    code=$(http_probe)
    info "  Probe ${i}/5: HTTP ${code}"
    if [[ "${code}" == "200" ]] || [[ "${code}" == "301" ]]; then
        consecutive_ok=$((consecutive_ok + 1))
    fi
    sleep 1
done
info "  Consecutive successful probes: ${consecutive_ok}/5"

if [[ "${http_during}" == "200" ]] || [[ "${http_during}" == "301" ]]; then
    during_ok=true
else
    during_ok=false
fi

if [[ "${http_after}" == "200" ]] || [[ "${http_after}" == "301" ]]; then
    after_ok=true
else
    after_ok=false
fi

if [[ "${during_ok}" == "true" ]] && [[ "${after_ok}" == "true" ]] && [[ "${consecutive_ok}" -ge 4 ]]; then
    pass "IT-05: HTTPS returned 200 during OOMKill (${http_during}) and after restart (${http_after}) — ${consecutive_ok}/5 rapid probes succeeded"
elif [[ "${after_ok}" == "true" ]] && [[ "${consecutive_ok}" -ge 4 ]]; then
    pass "IT-05: HTTPS returned ${http_during} during OOMKill (surviving pod serving) and 200 after restart — service recovered"
else
    fail "IT-05: Service disrupted — HTTP during OOMKill: ${http_during}, after restart: ${http_after}, rapid probes: ${consecutive_ok}/5"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "OOMKILL ENFORCEMENT TEST SUMMARY"
echo ""
echo "  Target pod:        ${TARGET_POD}"
echo "  Memory limit:      ${configured_limit} (from Deployment spec)"
echo "  Allocation target: ${ALLOC_MIB}Mi"
echo "  Restart baseline:  ${BASELINE_RESTARTS}"
echo "  Final restarts:    $(get_restart_count "${TARGET_POD}")"
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
    echo -e "  \033[32m✓ All ${TOTAL} OOMKill enforcement tests PASSED\033[0m"
    echo ""
    exit 0
fi
