#!/usr/bin/env bash
# scripts/verify-etcd-encryption.sh
#
# Verifies that Kubernetes Secrets are encrypted at rest in etcd using the
# EncryptionConfiguration set up in task 4.1 (setup-k3s.sh).
#
# Requirements: 10.2
# Task: 13.2 Verificare etcd encryption at rest
#
# What this script does:
#   1. Creates a test Secret in the techfix namespace
#   2. Retrieves the Secret data directly from etcd using etcdctl
#   3. Verifies that the raw etcd value is encrypted (aescbc prefix, no plaintext)
#   4. Verifies that kubectl can still decrypt and read the Secret correctly
#   5. Cleans up the test Secret
#
# Usage:
#   sudo bash scripts/verify-etcd-encryption.sh
#
# Prerequisites:
#   - k3s installed with --cluster-init and encryption-provider-config
#   - KUBECONFIG=/etc/rancher/k3s/k3s.yaml
#   - etcdctl available (bundled with k3s at /var/lib/rancher/k3s/data/.../bin/etcdctl)

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

log "=== etcd encryption at rest — verification ==="
log ""

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
ETCD_CERT_DIR="/var/lib/rancher/k3s/server/tls/etcd"
ETCD_ENDPOINT="https://127.0.0.1:2379"
TEST_SECRET_NAME="etcd-encryption-test"
TEST_SECRET_VALUE="plaintext-canary-value-must-not-appear-in-etcd"
NAMESPACE="techfix"

# Track pass/fail for final summary
CHECKS_PASSED=0
CHECKS_FAILED=0

pass() { log "✓ $*"; CHECKS_PASSED=$((CHECKS_PASSED + 1)); }
fail() { log "✗ $*"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

# ---------------------------------------------------------------------------
# Step 0: Verify k3s and kubectl are operational
# ---------------------------------------------------------------------------

log "Step 0: Verifying k3s cluster is ready..."

if ! command -v k3s &>/dev/null; then
    err "k3s binary not found. Run infra/setup-k3s.sh first."
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
    err "KUBECONFIG not found at ${KUBECONFIG_PATH}. Is k3s installed?"
fi

if ! kubectl cluster-info &>/dev/null; then
    err "kubectl cannot connect to the cluster."
fi

pass "k3s cluster is reachable"

# ---------------------------------------------------------------------------
# Step 0.1: Verify encryption-provider-config is active
# ---------------------------------------------------------------------------

log "Step 0.1: Verifying encryption-provider-config flag is active..."

if ps aux | grep -q "[e]ncryption-provider-config"; then
    pass "kube-apiserver running with encryption-provider-config"
else
    warn "Cannot confirm encryption-provider-config flag in running processes"
fi

# Check the encryption config file exists
ENCRYPTION_CONFIG="/etc/rancher/k3s/encryption-config.yaml"
if [[ -f "${ENCRYPTION_CONFIG}" ]]; then
    pass "Encryption config file exists at ${ENCRYPTION_CONFIG}"
else
    err "Encryption config file not found at ${ENCRYPTION_CONFIG}. Run infra/setup-k3s.sh first."
fi

# ---------------------------------------------------------------------------
# Step 1: Determine namespace and create test Secret
# ---------------------------------------------------------------------------

log "Step 1: Creating test Secret..."

if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    log "  Using namespace: ${NAMESPACE}"
else
    warn "Namespace '${NAMESPACE}' does not exist — falling back to 'default'"
    NAMESPACE="default"
fi

# Clean up any previous test Secret (idempotent)
kubectl delete secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found=true &>/dev/null

# Create the test Secret with known plaintext
kubectl create secret generic "${TEST_SECRET_NAME}" \
    --from-literal=canary="${TEST_SECRET_VALUE}" \
    -n "${NAMESPACE}" \
    || err "Failed to create test Secret"

pass "Test Secret '${TEST_SECRET_NAME}' created in namespace '${NAMESPACE}'"

# Wait for etcd persistence
sleep 2

# ---------------------------------------------------------------------------
# Step 2: Locate etcdctl binary and certificates
# ---------------------------------------------------------------------------

log "Step 2: Locating etcdctl and etcd TLS certificates..."

ETCDCTL_BIN=""
for etcdctl_path in /var/lib/rancher/k3s/data/*/bin/etcdctl; do
    if [[ -x "${etcdctl_path}" ]]; then
        ETCDCTL_BIN="${etcdctl_path}"
        break
    fi
done

if [[ -z "${ETCDCTL_BIN}" ]]; then
    err "etcdctl not found. k3s must be installed with --cluster-init (etcd mode)."
fi

log "  etcdctl: ${ETCDCTL_BIN}"

# Verify etcd certificates
ETCD_CA_CERT="${ETCD_CERT_DIR}/server-ca.crt"
ETCD_CERT="${ETCD_CERT_DIR}/client.crt"
ETCD_KEY="${ETCD_CERT_DIR}/client.key"

for cert_file in "${ETCD_CA_CERT}" "${ETCD_CERT}" "${ETCD_KEY}"; do
    if [[ ! -f "${cert_file}" ]]; then
        err "etcd certificate missing: ${cert_file}"
    fi
done

pass "etcdctl and TLS certificates located"

# ---------------------------------------------------------------------------
# Step 3: Read the raw Secret from etcd
# ---------------------------------------------------------------------------

log "Step 3: Reading raw Secret data from etcd..."

ETCD_KEY_PATH="/registry/secrets/${NAMESPACE}/${TEST_SECRET_NAME}"
log "  etcd key: ${ETCD_KEY_PATH}"

ETCD_RAW_VALUE=$(
    "${ETCDCTL_BIN}" \
        --endpoints="${ETCD_ENDPOINT}" \
        --cacert="${ETCD_CA_CERT}" \
        --cert="${ETCD_CERT}" \
        --key="${ETCD_KEY}" \
        get "${ETCD_KEY_PATH}" \
        2>/dev/null || echo ""
)

if [[ -z "${ETCD_RAW_VALUE}" ]]; then
    err "Failed to retrieve Secret from etcd. Check etcd connectivity and key path."
fi

log "  Raw value retrieved (${#ETCD_RAW_VALUE} bytes)"

# ---------------------------------------------------------------------------
# Step 4: Verify the data is encrypted (aescbc)
# ---------------------------------------------------------------------------

log "Step 4: Verifying encryption..."

# Check 4a: Raw value contains the aescbc encryption prefix
ENCRYPTION_PREFIX="k8s:enc:aescbc:v1:key1:"

if echo "${ETCD_RAW_VALUE}" | grep -qF "${ENCRYPTION_PREFIX}"; then
    pass "Raw etcd value contains aescbc encryption prefix"
else
    fail "Raw etcd value does NOT contain expected encryption prefix '${ENCRYPTION_PREFIX}'"
    log "  First 80 chars: ${ETCD_RAW_VALUE:0:80}"
fi

# Check 4b: Plaintext canary value is NOT present in raw data
if echo "${ETCD_RAW_VALUE}" | grep -qF "${TEST_SECRET_VALUE}"; then
    fail "SECURITY: Plaintext canary value found in raw etcd data — encryption NOT working!"
else
    pass "Plaintext canary value is NOT present in raw etcd data"
fi

# ---------------------------------------------------------------------------
# Step 5: Verify kubectl can decrypt the Secret via Kubernetes API
# ---------------------------------------------------------------------------

log "Step 5: Verifying kubectl decryption via Kubernetes API..."

DECODED_VALUE=$(
    kubectl get secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.data.canary}' 2>/dev/null | base64 -d 2>/dev/null || echo ""
)

if [[ "${DECODED_VALUE}" == "${TEST_SECRET_VALUE}" ]]; then
    pass "kubectl decrypts the Secret correctly — value matches original plaintext"
else
    fail "kubectl decryption mismatch (expected: '${TEST_SECRET_VALUE}', got: '${DECODED_VALUE}')"
fi

# ---------------------------------------------------------------------------
# Step 6: Clean up the test Secret
# ---------------------------------------------------------------------------

log "Step 6: Cleaning up..."

kubectl delete secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found=true &>/dev/null \
    || warn "Could not delete test Secret"

pass "Test Secret cleaned up"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log ""
log "=========================================="
log "  etcd Encryption Verification Summary"
log "=========================================="
log ""
log "  Checks passed: ${CHECKS_PASSED}"
log "  Checks failed: ${CHECKS_FAILED}"
log ""

if [[ "${CHECKS_FAILED}" -eq 0 ]]; then
    log "  ✓ RESULT: etcd encryption at rest is WORKING correctly"
    log ""
    log "  Secrets stored in etcd are encrypted with aescbc provider."
    log "  The kube-apiserver decrypts them transparently via the Kubernetes API."
    log ""
    exit 0
else
    log "  ✗ RESULT: etcd encryption verification FAILED"
    log ""
    log "  Troubleshooting:"
    log "    1. Verify /etc/rancher/k3s/encryption-config.yaml exists and is correct"
    log "    2. Verify k3s was started with --kube-apiserver-arg=encryption-provider-config"
    log "    3. Check k3s logs: journalctl -u k3s | grep -i encrypt"
    log "    4. Restart k3s: systemctl restart k3s"
    log ""
    exit 1
fi
