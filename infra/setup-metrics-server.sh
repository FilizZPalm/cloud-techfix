#!/usr/bin/env bash
# infra/setup-metrics-server.sh
#
# Installs metrics-server on a k3s single-node cluster and verifies that
# kubectl top nodes returns real CPU and memory data (not "<unknown>").
#
# Requirements: 6.1
#
# What this script does:
#   1. Checks that kubectl is reachable and KUBECONFIG is set
#   2. Skips apply if the metrics-server Deployment already exists (idempotent)
#   3. Applies k8s/metrics-server.yaml (patched for k3s --kubelet-insecure-tls)
#   4. Waits up to 2 minutes for the metrics-server pod to reach Running state
#   5. Verifies that `kubectl top nodes` returns real data (not "<unknown>")
#
# Usage:
#   sudo bash infra/setup-metrics-server.sh
#   # or, if KUBECONFIG is already set in the environment:
#   bash infra/setup-metrics-server.sh
#
# This script is idempotent:
#   - If the metrics-server Deployment already exists in kube-system the apply
#     step is skipped entirely.

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Path to the metrics-server manifest relative to the repo root.
# The script resolves the repo root as the directory two levels above this
# script (infra/ → repo root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
METRICS_MANIFEST="${REPO_ROOT}/k8s/metrics-server.yaml"

POD_READY_TIMEOUT=120   # seconds — 2 minutes
POD_POLL_INTERVAL=5     # seconds between kubectl get pods polls

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

log "=== metrics-server setup started ==="

# Ensure we can run as root or that KUBECONFIG is already configured
if [[ "$(id -u)" -ne 0 ]] && [[ -z "${KUBECONFIG:-}" ]]; then
    err "Run as root (sudo bash $0) or set KUBECONFIG before calling this script"
fi

# When running as root on a k3s node, use the k3s kubeconfig unless the caller
# has already exported a different KUBECONFIG.
if [[ "$(id -u)" -eq 0 ]] && [[ -z "${KUBECONFIG:-}" ]]; then
    K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if [[ -f "${K3S_KUBECONFIG}" ]]; then
        export KUBECONFIG="${K3S_KUBECONFIG}"
        log "KUBECONFIG set to ${K3S_KUBECONFIG}"
    else
        err "k3s kubeconfig not found at ${K3S_KUBECONFIG}. Ensure k3s is installed first (infra/setup-k3s.sh)"
    fi
fi

# Verify kubectl is available
if ! command -v kubectl &>/dev/null; then
    err "kubectl not found. Ensure k3s is installed and kubectl is in PATH (or use: /usr/local/bin/kubectl)"
fi

# Verify the manifest file exists
if [[ ! -f "${METRICS_MANIFEST}" ]]; then
    err "metrics-server manifest not found: ${METRICS_MANIFEST}"
fi

# Verify the cluster is reachable
if ! kubectl cluster-info &>/dev/null; then
    err "Cannot reach Kubernetes API server. Check that k3s is running: systemctl status k3s"
fi

log "Cluster is reachable"

# ---------------------------------------------------------------------------
# Step 1: Idempotency check — skip if metrics-server already deployed
# ---------------------------------------------------------------------------

log "Step 1: Checking if metrics-server is already installed..."

if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    log "metrics-server Deployment already exists in kube-system — skipping apply"
    SKIP_APPLY=true
else
    SKIP_APPLY=false
    log "metrics-server not found — will apply manifest"
fi

# ---------------------------------------------------------------------------
# Step 2: Apply the manifest
# ---------------------------------------------------------------------------

if [[ "${SKIP_APPLY}" == "false" ]]; then
    log "Step 2: Applying ${METRICS_MANIFEST}..."
    kubectl apply -f "${METRICS_MANIFEST}" \
        || err "kubectl apply failed for ${METRICS_MANIFEST}"
    log "metrics-server manifest applied"
else
    log "Step 2: Skipped (Deployment already exists)"
fi

# ---------------------------------------------------------------------------
# Step 3: Wait for metrics-server pod to reach Running state (timeout: 2 min)
# ---------------------------------------------------------------------------

log "Step 3: Waiting for metrics-server pod to reach Running state (timeout: ${POD_READY_TIMEOUT}s)..."

elapsed=0
pod_running=false

while [[ ${elapsed} -lt ${POD_READY_TIMEOUT} ]]; do
    # Look for a pod whose name starts with "metrics-server" in kube-system.
    # The pod is considered Running when the STATUS column shows "Running" and
    # the READY column is not "0/<n>" (i.e., at least one container is ready).
    pod_status=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
        | grep "^metrics-server" || true)

    if echo "${pod_status}" | grep -q "Running"; then
        # Additional check: ensure at least one container is ready (READY = x/x, x > 0)
        if echo "${pod_status}" | awk '{print $2}' | grep -qvE "^0/"; then
            pod_running=true
            break
        fi
    fi

    log "metrics-server pod not yet Running — retrying in ${POD_POLL_INTERVAL}s (${elapsed}s elapsed)..."
    sleep "${POD_POLL_INTERVAL}"
    elapsed=$(( elapsed + POD_POLL_INTERVAL ))
done

if [[ "${pod_running}" == "false" ]]; then
    warn "metrics-server pod did not reach Running state within ${POD_READY_TIMEOUT}s"
    warn "Current pod state:"
    kubectl get pods -n kube-system | grep metrics-server || true
    warn "Pod logs (if available):"
    kubectl logs -n kube-system -l k8s-app=metrics-server --tail=30 2>/dev/null || true
    err "metrics-server failed to start. Check: kubectl describe pods -n kube-system -l k8s-app=metrics-server"
fi

log "metrics-server pod is Running (${elapsed}s elapsed)"

# ---------------------------------------------------------------------------
# Step 4: Verify kubectl top nodes returns real data (not "<unknown>")
# ---------------------------------------------------------------------------

log "Step 4: Verifying kubectl top nodes returns CPU and memory data..."

# The metrics API can take a few extra seconds to become available even after
# the pod is Running. Retry for up to 60 additional seconds.
TOP_TIMEOUT=60
top_elapsed=0
top_ok=false

while [[ ${top_elapsed} -lt ${TOP_TIMEOUT} ]]; do
    top_output=$(kubectl top nodes 2>&1 || true)

    # Success condition: output contains at least one data line with actual
    # numbers (e.g. "node-name   250m   6%   512Mi   4%") and no "<unknown>" values.
    if echo "${top_output}" | grep -qvE "^NAME|^Error|<unknown>"; then
        # Verify the line looks like a real metrics line (has m for millicores or Mi for memory)
        if echo "${top_output}" | grep -qE "[0-9]+m[[:space:]]"; then
            top_ok=true
            break
        fi
    fi

    log "kubectl top nodes not yet returning data — retrying in 5s (${top_elapsed}s elapsed)..."
    sleep 5
    top_elapsed=$(( top_elapsed + 5 ))
done

if [[ "${top_ok}" == "false" ]]; then
    warn "kubectl top nodes output:"
    echo "${top_output}"
    err "kubectl top nodes did not return valid CPU/memory data within ${TOP_TIMEOUT}s. \
Check metrics-server logs: kubectl logs -n kube-system -l k8s-app=metrics-server"
fi

# ---------------------------------------------------------------------------
# Step 5: Verification summary
# ---------------------------------------------------------------------------

log ""
log "=== Verification summary ==="
log ""
log "kubectl top nodes:"
kubectl top nodes || warn "kubectl top nodes failed at summary step"

log ""
log "metrics-server pod status:"
kubectl get pods -n kube-system -l k8s-app=metrics-server -o wide || warn "kubectl get pods failed"

log ""
log "=== metrics-server setup completed successfully ==="
log "  Manifest applied : ${METRICS_MANIFEST}"
log "  Pod status       : Running"
log "  kubectl top nodes: OK (CPU and memory data available)"
log ""
log "Next steps:"
log "  4.3 Verify Traefik Ingress Controller"
log "  Apply HPA manifest: kubectl apply -f k8s/laravel-hpa.yaml"
