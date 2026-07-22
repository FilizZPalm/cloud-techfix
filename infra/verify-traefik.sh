#!/usr/bin/env bash
# infra/verify-traefik.sh
#
# Verifies that the Traefik Ingress Controller is running and that ports 80
# and 443 are listening on the VM.
#
# Requirements: 7.1
#
# What this script checks:
#   1. At least one Traefik pod is in Running state in namespace kube-system
#   2. Port 80 is listening on the VM (HTTP entrypoint)
#   3. Port 443 is listening on the VM (HTTPS/websecure entrypoint)
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash infra/verify-traefik.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (see [ERROR] lines for details)

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; }
warn() { echo "[WARN]  $*"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    warn "KUBECONFIG was not set — defaulting to ${KUBECONFIG}"
fi

if [[ ! -f "${KUBECONFIG}" ]]; then
    err "KUBECONFIG file not found: ${KUBECONFIG}"
    err "Ensure k3s is installed and run this script as root or with the correct KUBECONFIG."
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    err "kubectl not found in PATH. Ensure k3s is installed."
    exit 1
fi

log "=== Traefik Ingress Controller verification started ==="
log "KUBECONFIG: ${KUBECONFIG}"

# ---------------------------------------------------------------------------
# Tracking variables for final summary
# ---------------------------------------------------------------------------

traefik_running=false
port_80_listening=false
port_443_listening=false

# ---------------------------------------------------------------------------
# Check 1: Traefik pod in Running state in kube-system
# ---------------------------------------------------------------------------

log ""
log "--- Check 1: Traefik pod status (namespace: kube-system) ---"

traefik_pods="$(kubectl get pods -n kube-system 2>/dev/null | grep traefik || true)"

if [[ -z "${traefik_pods}" ]]; then
    err "No Traefik pods found in namespace kube-system."
    err "Run: kubectl get pods -n kube-system"
else
    log "Traefik pods found:"
    echo "${traefik_pods}" | while IFS= read -r line; do
        log "  ${line}"
    done

    # Check that at least one pod is in Running state
    if echo "${traefik_pods}" | grep -q "Running"; then
        traefik_running=true
        log "At least one Traefik pod is in Running state."
    else
        err "No Traefik pod is currently in Running state."
        err "Check pod events: kubectl describe pods -n kube-system -l app.kubernetes.io/name=traefik"
    fi
fi

# ---------------------------------------------------------------------------
# Check 2: Port 80 listening on the VM
# ---------------------------------------------------------------------------

log ""
log "--- Check 2: Port 80 (HTTP) ---"

port_80_output="$(ss -tlnp 2>/dev/null | grep ':80' || true)"

if [[ -n "${port_80_output}" ]]; then
    port_80_listening=true
    log "Port 80 is listening:"
    echo "${port_80_output}" | while IFS= read -r line; do
        log "  ${line}"
    done
else
    err "Port 80 is NOT listening on this VM."
    err "Traefik may not have bound the HTTP entrypoint. Check: kubectl logs -n kube-system -l app.kubernetes.io/name=traefik"
fi

# ---------------------------------------------------------------------------
# Check 3: Port 443 listening on the VM
# ---------------------------------------------------------------------------

log ""
log "--- Check 3: Port 443 (HTTPS) ---"

port_443_output="$(ss -tlnp 2>/dev/null | grep ':443' || true)"

if [[ -n "${port_443_output}" ]]; then
    port_443_listening=true
    log "Port 443 is listening:"
    echo "${port_443_output}" | while IFS= read -r line; do
        log "  ${line}"
    done
else
    err "Port 443 is NOT listening on this VM."
    err "Traefik may not have bound the HTTPS entrypoint. Check: kubectl logs -n kube-system -l app.kubernetes.io/name=traefik"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log ""
log "=== Verification summary ==="
log ""
log "  Traefik pod Running  : $( [[ "${traefik_running}"      == "true" ]] && echo "YES" || echo "NO  <-- FAILED" )"
log "  Port 80  listening   : $( [[ "${port_80_listening}"    == "true" ]] && echo "YES" || echo "NO  <-- FAILED" )"
log "  Port 443 listening   : $( [[ "${port_443_listening}"   == "true" ]] && echo "YES" || echo "NO  <-- FAILED" )"
log ""

# ---------------------------------------------------------------------------
# Exit non-zero if any check failed
# ---------------------------------------------------------------------------

if [[ "${traefik_running}" == "false" ]] || \
   [[ "${port_80_listening}" == "false" ]] || \
   [[ "${port_443_listening}" == "false" ]]; then
    err "One or more Traefik verification checks FAILED."
    err "Review the [ERROR] lines above and check: kubectl get pods -n kube-system"
    exit 1
fi

log "All checks passed. Traefik Ingress Controller is ready."
log ""
log "Next step: deploy the application and verify TLS — bash scripts/create-secrets.sh"
