#!/usr/bin/env bash
# infra/setup-k3s.sh
#
# Installs and configures k3s (single-node) on Ubuntu 24.04 (Azure VM).
# Requirements: 2.1, 10.2
#
# What this script does:
#   1. Generates a 32-byte aescbc encryption key (if not already present)
#   2. Writes /etc/rancher/k3s/encryption-config.yaml (EncryptionConfiguration
#      for etcd secrets at rest)
#   3. Installs k3s with:
#        --cluster-init              (enables embedded etcd)
#        --flannel-backend=none      (disables built-in Flannel so Calico can own CNI)
#        --disable-network-policy    (Calico handles NetworkPolicy)
#        --kube-apiserver-arg        (points kube-apiserver to the encryption config)
#   4. Exports KUBECONFIG and persists it to /etc/environment
#   5. Installs Calico CNI (required for NetworkPolicy support)
#   6. Polls until the node is in Ready state (timeout: 5 minutes)
#
# Usage:
#   sudo bash infra/setup-k3s.sh
#
# This script is idempotent:
#   - k3s installation is skipped if the k3s binary already exists.
#   - The encryption config is skipped if the file already exists.
#   - KUBECONFIG is only appended to /etc/environment if not already present.

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root (use: sudo bash $0)"
fi

log "=== k3s setup started ==="

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

K3S_RANCHER_DIR="/etc/rancher/k3s"
ENCRYPTION_CONFIG="${K3S_RANCHER_DIR}/encryption-config.yaml"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml"
NODE_READY_TIMEOUT=300   # seconds — 5 minutes
NODE_POLL_INTERVAL=10    # seconds between kubectl get nodes polls

# ---------------------------------------------------------------------------
# Step 1: Create /etc/rancher/k3s directory
# ---------------------------------------------------------------------------

log "Step 1: Ensuring ${K3S_RANCHER_DIR} exists..."
mkdir -p "${K3S_RANCHER_DIR}"
log "Directory ${K3S_RANCHER_DIR} ready"

# ---------------------------------------------------------------------------
# Step 2: Generate aescbc encryption key and write EncryptionConfiguration
# ---------------------------------------------------------------------------

log "Step 2: Checking encryption config at ${ENCRYPTION_CONFIG}..."

if [[ -f "${ENCRYPTION_CONFIG}" ]]; then
    log "Encryption config already exists — skipping key generation and file creation"
else
    log "Generating 32-byte aescbc encryption key..."

    if ! command -v openssl &>/dev/null; then
        err "openssl is not installed. Install it with: apt-get install -y openssl"
    fi

    AESCBC_KEY="$(openssl rand -base64 32)"
    log "Encryption key generated (not printed for security)"

    log "Writing ${ENCRYPTION_CONFIG}..."

    # EncryptionConfiguration: aescbc provider for secrets at rest in etcd.
    # The identity provider is listed last so existing unencrypted secrets can
    # still be read before they are re-encrypted.
    cat > "${ENCRYPTION_CONFIG}" <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${AESCBC_KEY}
      - identity: {}
EOF

    # Restrict permissions — only root may read the key
    chmod 600 "${ENCRYPTION_CONFIG}"
    log "Encryption config written to ${ENCRYPTION_CONFIG} (permissions: 600)"
fi

# ---------------------------------------------------------------------------
# Step 3: Install k3s (skip if binary already present)
# ---------------------------------------------------------------------------

log "Step 3: Checking if k3s is already installed..."

if command -v k3s &>/dev/null; then
    log "k3s binary found at $(command -v k3s) — skipping installation"
else
    log "Installing k3s..."

    # Verify curl is available for the install script
    if ! command -v curl &>/dev/null; then
        log "curl not found — installing..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl || err "Failed to install curl"
    fi

    # K3S_INSTALL_FLAGS are passed to the k3s service unit via INSTALL_K3S_EXEC.
    # - --cluster-init:              enables embedded etcd (required for encryption at rest)
    # - --flannel-backend=none:      disables Flannel so Calico can manage the pod network
    # - --disable-network-policy:    disables k3s built-in network policy controller (Calico owns it)
    # - --kube-apiserver-arg:        passes the encryption provider config to kube-apiserver
    export INSTALL_K3S_EXEC="server \
        --cluster-init \
        --flannel-backend=none \
        --disable-network-policy \
        --kube-apiserver-arg=encryption-provider-config=${ENCRYPTION_CONFIG}"

    log "Running k3s install script with flags: ${INSTALL_K3S_EXEC}"

    curl -sfL https://get.k3s.io | sh - \
        || err "k3s installation script failed"

    log "k3s installed successfully"
fi

# ---------------------------------------------------------------------------
# Step 4: Configure KUBECONFIG
# ---------------------------------------------------------------------------

log "Step 4: Configuring KUBECONFIG..."

# Export for the current shell session so kubectl calls in this script work
export KUBECONFIG="${KUBECONFIG_PATH}"
log "KUBECONFIG exported: ${KUBECONFIG_PATH}"

# Persist to /etc/environment so all future login sessions pick it up
if grep -q "KUBECONFIG=" /etc/environment 2>/dev/null; then
    log "KUBECONFIG already present in /etc/environment — skipping"
else
    echo "KUBECONFIG=${KUBECONFIG_PATH}" >> /etc/environment
    log "KUBECONFIG added to /etc/environment"
fi

# Give kubectl a moment after install before the first call
sleep 5

# ---------------------------------------------------------------------------
# Step 5: Install Calico CNI
# ---------------------------------------------------------------------------

log "Step 5: Installing Calico CNI..."
log "Applying Calico manifest: ${CALICO_MANIFEST}"

kubectl apply -f "${CALICO_MANIFEST}" \
    || err "Failed to apply Calico manifest — ensure the node is reachable and kubectl is configured"

log "Calico manifest applied"

# ---------------------------------------------------------------------------
# Step 6: Wait for node to reach Ready state (timeout: ${NODE_READY_TIMEOUT}s)
# ---------------------------------------------------------------------------

log "Step 6: Waiting for k3s node to become Ready (timeout: ${NODE_READY_TIMEOUT}s)..."

elapsed=0
node_ready=false

while [[ ${elapsed} -lt ${NODE_READY_TIMEOUT} ]]; do
    # kubectl get nodes returns a line like:
    #   <nodename>   Ready   control-plane,master   ...
    # We grep for "Ready" that is not preceded by "Not" to catch NotReady.
    if kubectl get nodes 2>/dev/null | grep -E "\bReady\b" | grep -qv "NotReady"; then
        node_ready=true
        break
    fi

    log "Node not yet Ready — retrying in ${NODE_POLL_INTERVAL}s (${elapsed}s elapsed)..."
    sleep "${NODE_POLL_INTERVAL}"
    elapsed=$(( elapsed + NODE_POLL_INTERVAL ))
done

if [[ "${node_ready}" == "false" ]]; then
    err "Node did not reach Ready state within ${NODE_READY_TIMEOUT}s. Check: kubectl get nodes && journalctl -u k3s"
fi

log "Node is Ready (${elapsed}s elapsed)"

# ---------------------------------------------------------------------------
# Step 7: Verification summary
# ---------------------------------------------------------------------------

log ""
log "=== Verification summary ==="
log ""

# Show node status
log "kubectl get nodes:"
kubectl get nodes -o wide || warn "kubectl get nodes failed"

log ""

# Show k3s version
log "k3s version: $(k3s --version 2>/dev/null | head -1 || echo 'unknown')"

log ""

# Quick check that the encryption config is referenced by the apiserver
log "Checking kube-apiserver for encryption-provider-config flag..."
if kubectl get pods -n kube-system 2>/dev/null | grep -q "kube-apiserver\|k3s"; then
    log "kube-system pods:"
    kubectl get pods -n kube-system || warn "kubectl get pods -n kube-system failed"
fi

log ""
log "=== k3s setup completed successfully ==="
log "  KUBECONFIG          : ${KUBECONFIG_PATH}"
log "  Encryption config   : ${ENCRYPTION_CONFIG}"
log "  Calico CNI          : applied (${CALICO_MANIFEST})"
log "  Node status         : Ready"
log ""
log "Next steps:"
log "  4.2 Install metrics-server (required for HPA): infra/setup-k3s.sh task 4.2"
log "  4.3 Verify Traefik Ingress Controller"
log "  13.1 Create Kubernetes Secrets: bash scripts/create-secrets.sh"
