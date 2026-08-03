#!/usr/bin/env bash
# tests/integration/test-network-policy-lateral-movement.sh
#
# Integration test that validates NetworkPolicy enforcement against lateral
# movement attacks — i.e., a rogue pod inside the 'techfix' namespace cannot
# directly reach the Laravel PHP-FPM service or the Nginx pod, even though
# all three pods share the same namespace.
#
# Three NetworkPolicies are under test:
#
#   Policy 1 — allow-nginx-to-laravel (Ingress on Laravel:9000)
#     Only pods with label app=nginx may connect to Laravel:9000.
#     Any other pod in the namespace must be blocked.
#
#   Policy 2 — laravel-egress-policy (Egress from Laravel pods)
#     Laravel pods may only reach MariaDB(:3306/:3307) and DNS(:53).
#     Connections to any other pod (e.g. Nginx) must be blocked.
#
#   Policy 3 — allow-ingress-to-nginx (Ingress on Nginx:8080)
#     Only pods in kube-system (Traefik) may reach Nginx:8080.
#     Any pod inside the techfix namespace must be blocked.
#
# Test structure:
#   IT-01  Attacker pod → Laravel:9000           must be BLOCKED
#   IT-02  Attacker pod → Nginx:8080             must be BLOCKED
#   IT-03  Laravel pod  → Nginx:8080 (egress)    must be BLOCKED
#   IT-04  Nginx pod    → Laravel:9000 (control) must be ALLOWED
#
# Requirements: 8.1, 8.2, 8.3, 8.4
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-network-policy-lateral-movement.sh
#
# Prerequisites:
#   - kubectl configured with access to the cluster (KUBECONFIG set or k3s default)
#   - Namespace 'techfix' exists with Laravel and Nginx deployments running
#   - Calico CNI installed (NetworkPolicy enforcement)
#   - Internet access from the VM to pull curlimages/curl (or image already cached)
#
# The test creates a temporary 'attacker' pod in the techfix namespace using the
# curlimages/curl image, runs connection probes, and deletes the pod on exit.
# The pod carries no special labels, so no NetworkPolicy whitelists it.
#
# Exit codes:
#   0 — all integration checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
ATTACKER_POD="${ATTACKER_POD:-netpol-attacker}"
ATTACKER_IMAGE="${ATTACKER_IMAGE:-curlimages/curl:8.5.0}"

# Services as seen from inside the cluster
LARAVEL_HOST="${LARAVEL_HOST:-laravel-service}"
LARAVEL_PORT="${LARAVEL_PORT:-9000}"
NGINX_HOST="${NGINX_HOST:-nginx-service}"
NGINX_PORT="${NGINX_PORT:-8080}"

# How long to wait for the attacker pod to become Running
ATTACKER_POD_TIMEOUT="${ATTACKER_POD_TIMEOUT:-60}"

# Timeout for each individual connection probe (seconds).
# Short on purpose: a blocked connection should time out quickly.
PROBE_TIMEOUT="${PROBE_TIMEOUT:-5}"

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

# ---------------------------------------------------------------------------
# Cleanup — always delete the attacker pod on exit
# ---------------------------------------------------------------------------

cleanup() {
    if kubectl get pod "${ATTACKER_POD}" -n "${NAMESPACE}" &>/dev/null 2>&1; then
        info "Deleting attacker pod '${ATTACKER_POD}'..."
        kubectl delete pod "${ATTACKER_POD}" -n "${NAMESPACE}" \
            --grace-period=0 --force &>/dev/null 2>&1 || true
        info "Attacker pod deleted"
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix NetworkPolicy Lateral Movement Integration Test"
echo ""
echo "  Namespace:       ${NAMESPACE}"
echo "  Attacker pod:    ${ATTACKER_POD} (image: ${ATTACKER_IMAGE})"
echo "  Laravel target:  ${LARAVEL_HOST}:${LARAVEL_PORT}"
echo "  Nginx target:    ${NGINX_HOST}:${NGINX_PORT}"
echo "  Probe timeout:   ${PROBE_TIMEOUT}s per connection"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH."
    exit 1
fi

# Verify namespace exists
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Namespace '${NAMESPACE}' not found."
    exit 1
fi

# Verify NetworkPolicies are deployed
for policy in allow-nginx-to-laravel laravel-egress-policy allow-ingress-to-nginx; do
    if ! kubectl get networkpolicy "${policy}" -n "${NAMESPACE}" &>/dev/null; then
        echo "ERROR: NetworkPolicy '${policy}' not found in namespace '${NAMESPACE}'."
        echo "       Deploy k8s/network-policies.yaml before running this test."
        exit 1
    fi
    info "NetworkPolicy '${policy}' found"
done

# Verify Laravel and Nginx deployments are running
for deploy in laravel-deployment nginx-deployment; do
    ready=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "${ready}" -lt 1 ]] 2>/dev/null; then
        echo "ERROR: Deployment '${deploy}' has no ready replicas in namespace '${NAMESPACE}'."
        exit 1
    fi
    info "Deployment '${deploy}' has ${ready} ready replica(s)"
done

# ---------------------------------------------------------------------------
# Spawn the attacker pod
#
# The pod runs as a long-lived sleep so we can exec individual probe commands
# into it. It carries no app= label, so no NetworkPolicy whitelists it as
# a permitted source (neither app=nginx nor a kube-system namespace selector).
# ---------------------------------------------------------------------------

header "Spawning attacker pod '${ATTACKER_POD}' in namespace '${NAMESPACE}'"

# Delete any leftover pod from a previous run
if kubectl get pod "${ATTACKER_POD}" -n "${NAMESPACE}" &>/dev/null 2>&1; then
    info "Stale pod found — deleting before re-creating..."
    kubectl delete pod "${ATTACKER_POD}" -n "${NAMESPACE}" \
        --grace-period=0 --force &>/dev/null 2>&1 || true
    sleep 3
fi

# Create the attacker pod. We use a minimal curl image to keep the footprint
# small. The pod is explicitly not given any labels that match existing
# NetworkPolicy selectors.
kubectl run "${ATTACKER_POD}" \
    --image="${ATTACKER_IMAGE}" \
    --restart=Never \
    --namespace="${NAMESPACE}" \
    --labels="role=test-attacker" \
    --command -- sleep 120 \
    &>/dev/null

info "Attacker pod created — waiting for Running state (timeout: ${ATTACKER_POD_TIMEOUT}s)..."

elapsed=0
pod_ready=false

while [[ ${elapsed} -lt ${ATTACKER_POD_TIMEOUT} ]]; do
    phase=$(kubectl get pod "${ATTACKER_POD}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)

    if [[ "${phase}" == "Running" ]]; then
        pod_ready=true
        break
    fi

    sleep 3
    elapsed=$((elapsed + 3))
    info "  [${elapsed}s] Pod phase: ${phase:-Pending}"
done

if [[ "${pod_ready}" != "true" ]]; then
    echo "ERROR: Attacker pod did not reach Running state within ${ATTACKER_POD_TIMEOUT}s."
    echo "       Check image pull status: kubectl describe pod ${ATTACKER_POD} -n ${NAMESPACE}"
    exit 1
fi

info "Attacker pod is Running"

# ---------------------------------------------------------------------------
# Helper: run a TCP connection probe from the attacker pod.
#
# Uses curl with --max-time to avoid hanging. For FastCGI (Laravel:9000) there
# is no HTTP server, so curl will get a connection refused OR a timeout
# depending on whether the NetworkPolicy drops the packet.
#
# Returns:
#   "blocked"  — connection timed out or was refused (NetworkPolicy dropped it)
#   "allowed"  — connection succeeded (curl received any response, even an error)
# ---------------------------------------------------------------------------

probe_from_attacker() {
    local host="$1"
    local port="$2"

    # We use curl's --connect-timeout instead of --max-time so we measure only
    # the TCP handshake, not any data transfer. A dropped packet causes a
    # timeout; a refused connection returns immediately with exit code 7.
    # Both outcomes mean "not reachable" from the attacker's perspective.
    local exit_code
    kubectl exec "${ATTACKER_POD}" -n "${NAMESPACE}" -- \
        curl --silent --output /dev/null \
             --connect-timeout "${PROBE_TIMEOUT}" \
             "http://${host}:${port}/" \
        2>/dev/null
    exit_code=$?

    # curl exit codes:
    #   0  — connected and got a response       → allowed
    #   7  — connection refused                 → blocked (port unreachable)
    #   28 — operation timed out                → blocked (packet dropped by policy)
    #   52 — empty reply from server            → allowed (connected, no HTTP)
    #   56 — recv failure                       → allowed (connected, FastCGI reset)
    # Anything that reached the server (0, 52, 56) counts as "allowed".
    # Anything that never reached it (7, 28, and other network errors) is "blocked".
    case "${exit_code}" in
        0|52|56) echo "allowed" ;;
        *)       echo "blocked" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: run a TCP connection probe from INSIDE a Laravel pod (egress test).
#
# We use kubectl exec on the running Laravel deployment. The Laravel image
# does not contain curl, but it has php with fsockopen available.
# ---------------------------------------------------------------------------

probe_from_laravel() {
    local host="$1"
    local port="$2"

    local exit_code
    kubectl exec -n "${NAMESPACE}" deployment/laravel-deployment -c laravel -- \
        php -r "
            \$sock = @fsockopen('${host}', ${port}, \$errno, \$errstr, ${PROBE_TIMEOUT});
            if (\$sock) { fclose(\$sock); exit(0); } else { exit(1); }
        " 2>/dev/null
    exit_code=$?

    if [[ "${exit_code}" -eq 0 ]]; then
        echo "allowed"
    else
        echo "blocked"
    fi
}

# ---------------------------------------------------------------------------
# IT-01: Attacker pod → Laravel:9000 must be BLOCKED
#
# The NetworkPolicy 'allow-nginx-to-laravel' only permits ingress to
# Laravel:9000 from pods with label app=nginx. The attacker pod has no such
# label, so Calico must drop the connection.
#
# Requirements: 8.1, 8.2
# ---------------------------------------------------------------------------

header "IT-01: Attacker pod → Laravel:9000 (must be BLOCKED by allow-nginx-to-laravel)"

info "Probing ${LARAVEL_HOST}:${LARAVEL_PORT} from attacker pod (timeout ${PROBE_TIMEOUT}s)..."
result=$(probe_from_attacker "${LARAVEL_HOST}" "${LARAVEL_PORT}")
info "Probe result: ${result}"

if [[ "${result}" == "blocked" ]]; then
    pass "IT-01: Attacker pod CANNOT reach Laravel:${LARAVEL_PORT} — NetworkPolicy 'allow-nginx-to-laravel' is enforced"
else
    fail "IT-01: Attacker pod CAN reach Laravel:${LARAVEL_PORT} — NetworkPolicy 'allow-nginx-to-laravel' is NOT enforced"
fi

# ---------------------------------------------------------------------------
# IT-02: Attacker pod → Nginx:8080 must be BLOCKED
#
# The NetworkPolicy 'allow-ingress-to-nginx' only permits ingress to
# Nginx:8080 from pods in the kube-system namespace (Traefik). A pod inside
# the techfix namespace must be blocked regardless of its labels.
#
# Requirements: 8.3, 8.4
# ---------------------------------------------------------------------------

header "IT-02: Attacker pod → Nginx:8080 (must be BLOCKED by allow-ingress-to-nginx)"

info "Probing ${NGINX_HOST}:${NGINX_PORT} from attacker pod (timeout ${PROBE_TIMEOUT}s)..."
result=$(probe_from_attacker "${NGINX_HOST}" "${NGINX_PORT}")
info "Probe result: ${result}"

if [[ "${result}" == "blocked" ]]; then
    pass "IT-02: Attacker pod CANNOT reach Nginx:${NGINX_PORT} — NetworkPolicy 'allow-ingress-to-nginx' is enforced"
else
    fail "IT-02: Attacker pod CAN reach Nginx:${NGINX_PORT} — NetworkPolicy 'allow-ingress-to-nginx' is NOT enforced"
fi

# ---------------------------------------------------------------------------
# IT-03: Laravel pod → Nginx:8080 must be BLOCKED (egress)
#
# The NetworkPolicy 'laravel-egress-policy' whitelists egress only to
# MariaDB(:3306/:3307) and DNS(:53). A connection from a Laravel pod to
# Nginx inside the same namespace must be dropped.
#
# This test catches the "confused deputy" scenario: a compromised Laravel
# process cannot reach Nginx to forge or inspect requests.
#
# Requirements: 8.3, 8.4
# ---------------------------------------------------------------------------

header "IT-03: Laravel pod → Nginx:8080 (must be BLOCKED by laravel-egress-policy)"

info "Probing ${NGINX_HOST}:${NGINX_PORT} from Laravel pod (timeout ${PROBE_TIMEOUT}s)..."
result=$(probe_from_laravel "${NGINX_HOST}" "${NGINX_PORT}")
info "Probe result: ${result}"

if [[ "${result}" == "blocked" ]]; then
    pass "IT-03: Laravel pod CANNOT reach Nginx:${NGINX_PORT} — egress NetworkPolicy is enforced"
else
    fail "IT-03: Laravel pod CAN reach Nginx:${NGINX_PORT} — egress NetworkPolicy is NOT enforced"
fi

# ---------------------------------------------------------------------------
# IT-04: Nginx pod → Laravel:9000 must be ALLOWED (control check)
#
# This is the positive / control case: the legitimate traffic path that the
# application depends on must still work. If this fails, the NetworkPolicy
# is blocking legitimate traffic and the application would be broken.
#
# The Nginx pod carries label app=nginx, which is the only label permitted by
# 'allow-nginx-to-laravel'.
#
# Requirements: 8.1, 8.2
# ---------------------------------------------------------------------------

header "IT-04: Nginx pod → Laravel:9000 (must be ALLOWED — control check)"

info "Probing ${LARAVEL_HOST}:${LARAVEL_PORT} from Nginx pod (timeout ${PROBE_TIMEOUT}s)..."

# The Nginx image contains curl (nginx:1.25-alpine includes it)
nginx_exit_code=0
kubectl exec -n "${NAMESPACE}" deployment/nginx-deployment -c nginx -- \
    curl --silent --output /dev/null \
         --connect-timeout "${PROBE_TIMEOUT}" \
         "http://${LARAVEL_HOST}:${LARAVEL_PORT}/" \
    2>/dev/null || nginx_exit_code=$?

# curl exit codes 0, 52 (empty reply — FastCGI), 56 (recv failure — FastCGI reset)
# all indicate the TCP connection succeeded. Exit codes 7 (refused) and 28 (timeout)
# indicate the connection was blocked.
case "${nginx_exit_code}" in
    0|52|56)
        pass "IT-04: Nginx pod CAN reach Laravel:${LARAVEL_PORT} — legitimate traffic path is intact"
        ;;
    7)
        fail "IT-04: Connection refused from Nginx to Laravel:${LARAVEL_PORT} — check if Laravel pods are ready"
        ;;
    28)
        fail "IT-04: Connection timed out from Nginx to Laravel:${LARAVEL_PORT} — NetworkPolicy may be over-blocking"
        ;;
    *)
        fail "IT-04: Unexpected curl exit code ${nginx_exit_code} from Nginx to Laravel:${LARAVEL_PORT}"
        ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "NETWORK POLICY LATERAL MOVEMENT TEST SUMMARY"
echo ""
echo "  Policies tested:"
echo "    allow-nginx-to-laravel   — ingress to Laravel:9000 (IT-01, IT-04)"
echo "    allow-ingress-to-nginx   — ingress to Nginx:8080   (IT-02)"
echo "    laravel-egress-policy    — egress from Laravel pods (IT-03)"
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
    echo -e "  \033[32m✓ All ${TOTAL} NetworkPolicy lateral movement tests PASSED\033[0m"
    echo ""
    exit 0
fi
