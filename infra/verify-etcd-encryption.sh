#!/usr/bin/env bash
# infra/verify-etcd-encryption.sh
#
# Verifies that Kubernetes Secrets are encrypted at rest in etcd using the
# EncryptionConfiguration set up in task 4.1 (setup-k3s.sh).
# Requirements: 10.2
#
# What this script does:
#   1. Creates a test Secret in the techfix namespace (or default if techfix doesn't exist)
#   2. Retrieves the Secret data from etcd using etcdctl
#   3. Verifies that the raw etcd value is NOT plaintext (i.e., encrypted with aescbc)
#   4. Verifies that kubectl can still decrypt and read the Secret correctly
#   5. Cleans up the test Secret
#
# Expected outcome:
#   - The raw etcd value should start with "k8s:enc:aescbc:v1:key1:" (encrypted)
#   - The raw etcd value should NOT contain the plaintext test data
#   - kubectl get secret should successfully decode the base64 value
#
# Usage:
#   sudo bash infra/verify-etcd-encryption.sh
#
# Prerequisites:
#   - k3s must be installed with --cluster-init and encryption-provider-config
#   - kubectl must be configured (KUBECONFIG=/etc/rancher/k3s/k3s.yaml)
#   - etcdctl must be available (bundled with k3s at /var/lib/rancher/k3s/data/.../bin/etcdctl)

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

log "=== etcd encryption verification started ==="

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
ETCD_CERT_DIR="/var/lib/rancher/k3s/server/tls/etcd"
ETCD_ENDPOINT="https://127.0.0.1:2379"
TEST_SECRET_NAME="test-encryption-secret"
TEST_SECRET_VALUE="this-is-plaintext-data-that-should-be-encrypted"
NAMESPACE="techfix"

# ---------------------------------------------------------------------------
# Step 0: Verify k3s and kubectl are ready
# ---------------------------------------------------------------------------

log "Step 0: Verifying k3s and kubectl..."

if ! command -v k3s &>/dev/null; then
    err "k3s binary not found. Run infra/setup-k3s.sh first."
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
    err "KUBECONFIG not found at ${KUBECONFIG_PATH}. Run infra/setup-k3s.sh first."
fi

if ! kubectl cluster-info &>/dev/null; then
    err "kubectl cannot connect to the cluster. Check: kubectl cluster-info"
fi

log "k3s and kubectl are ready"

# ---------------------------------------------------------------------------
# Step 0.1: Check if namespace exists, fallback to default
# ---------------------------------------------------------------------------

log "Step 0.1: Checking if namespace '${NAMESPACE}' exists..."

if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    log "Namespace '${NAMESPACE}' exists — using it for test Secret"
else
    warn "Namespace '${NAMESPACE}' does not exist — using 'default' namespace"
    NAMESPACE="default"
fi

# ---------------------------------------------------------------------------
# Step 1: Create a test Secret
# ---------------------------------------------------------------------------

log "Step 1: Creating test Secret '${TEST_SECRET_NAME}' in namespace '${NAMESPACE}'..."

# Delete any existing test Secret first (idempotent)
kubectl delete secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found=true

# Create the test Secret
kubectl create secret generic "${TEST_SECRET_NAME}" \
    --from-literal=test-key="${TEST_SECRET_VALUE}" \
    -n "${NAMESPACE}" \
    || err "Failed to create test Secret"

log "Test Secret created: ${NAMESPACE}/${TEST_SECRET_NAME}"

# Give kube-apiserver a moment to persist the Secret to etcd
sleep 2

# ---------------------------------------------------------------------------
# Step 2: Locate etcdctl and etcd certificates
# ---------------------------------------------------------------------------

log "Step 2: Locating etcdctl and etcd certificates..."

# k3s embeds etcdctl in a versioned directory under /var/lib/rancher/k3s/data/
# We search for it dynamically
ETCDCTL_BIN=""
for etcdctl_path in /var/lib/rancher/k3s/data/*/bin/etcdctl; do
    if [[ -x "${etcdctl_path}" ]]; then
        ETCDCTL_BIN="${etcdctl_path}"
        break
    fi
done

if [[ -z "${ETCDCTL_BIN}" ]]; then
    err "etcdctl binary not found in /var/lib/rancher/k3s/data/*/bin/. Is k3s installed with --cluster-init?"
fi

log "etcdctl found at: ${ETCDCTL_BIN}"

# Verify etcd certificates exist
ETCD_CA_CERT="${ETCD_CERT_DIR}/server-ca.crt"
ETCD_CERT="${ETCD_CERT_DIR}/client.crt"
ETCD_KEY="${ETCD_CERT_DIR}/client.key"

for cert_file in "${ETCD_CA_CERT}" "${ETCD_CERT}" "${ETCD_KEY}"; do
    if [[ ! -f "${cert_file}" ]]; then
        err "etcd certificate not found: ${cert_file}. Is k3s running with --cluster-init?"
    fi
done

log "etcd certificates found:"
log "  CA cert : ${ETCD_CA_CERT}"
log "  Client cert : ${ETCD_CERT}"
log "  Client key : ${ETCD_KEY}"

# ---------------------------------------------------------------------------
# Step 3: Retrieve the Secret from etcd and verify it's encrypted
# ---------------------------------------------------------------------------

log "Step 3: Retrieving raw Secret data from etcd..."

# Kubernetes stores secrets in etcd with key pattern:
#   /registry/secrets/<namespace>/<secret-name>
ETCD_KEY_PATH="/registry/secrets/${NAMESPACE}/${TEST_SECRET_NAME}"

log "Querying etcd for key: ${ETCD_KEY_PATH}"

# Retrieve the raw value from etcd
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
    err "Failed to retrieve Secret from etcd. The Secret may not exist or etcd is not reachable."
fi

log "Raw etcd value retrieved (length: ${#ETCD_RAW_VALUE} bytes)"

# ---------------------------------------------------------------------------
# Step 4: Verify encryption — check for aescbc prefix
# ---------------------------------------------------------------------------

log "Step 4: Verifying encryption..."

# Encrypted secrets should start with "k8s:enc:aescbc:v1:key1:" prefix
ENCRYPTION_PREFIX="k8s:enc:aescbc:v1:key1:"

if [[ "${ETCD_RAW_VALUE}" == "${ENCRYPTION_PREFIX}"* ]]; then
    log "✓ Secret is encrypted — raw etcd value starts with '${ENCRYPTION_PREFIX}'"
else
    log "✗ Secret is NOT encrypted — raw etcd value does not start with expected prefix"
    log "First 100 characters of raw value: ${ETCD_RAW_VALUE:0:100}"
    err "Encryption verification FAILED — etcd encryption at rest is NOT enabled"
fi

# Verify the plaintext value is NOT present in the raw etcd data
if echo "${ETCD_RAW_VALUE}" | grep -qF "${TEST_SECRET_VALUE}"; then
    log "✗ SECURITY ISSUE: Plaintext value '${TEST_SECRET_VALUE}' found in raw etcd data!"
    err "Encryption verification FAILED — plaintext data is stored unencrypted"
else
    log "✓ Plaintext value is NOT present in raw etcd data — encryption is working"
fi

# ---------------------------------------------------------------------------
# Step 5: Verify kubectl can decrypt the Secret
# ---------------------------------------------------------------------------

log "Step 5: Verifying kubectl can decrypt the Secret..."

# Retrieve the Secret via kubectl and decode the base64 value
KUBECTL_SECRET_VALUE=$(
    kubectl get secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.data.test-key}' 2>/dev/null | base64 -d || echo ""
)

if [[ "${KUBECTL_SECRET_VALUE}" == "${TEST_SECRET_VALUE}" ]]; then
    log "✓ kubectl successfully decrypted the Secret — decrypted value matches original"
else
    log "✗ kubectl decryption FAILED — decrypted value does not match"
    log "Expected: '${TEST_SECRET_VALUE}'"
    log "Got: '${KUBECTL_SECRET_VALUE}'"
    err "Decryption verification FAILED"
fi

# ---------------------------------------------------------------------------
# Step 6: Clean up test Secret
# ---------------------------------------------------------------------------

log "Step 6: Cleaning up test Secret..."

kubectl delete secret "${TEST_SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found=true \
    || warn "Failed to delete test Secret (may have been deleted manually)"

log "Test Secret deleted"

# ---------------------------------------------------------------------------
# Step 7: Verification summary
# ---------------------------------------------------------------------------

log ""
log "=== etcd encryption verification summary ==="
log ""
log "  ✓ Test Secret created in namespace: ${NAMESPACE}"
log "  ✓ Raw etcd value is encrypted (aescbc prefix detected)"
log "  ✓ Plaintext value is NOT present in raw etcd data"
log "  ✓ kubectl can decrypt the Secret correctly"
log "  ✓ Test Secret cleaned up"
log ""
log "=== etcd encryption at rest is WORKING correctly ==="
log ""
log "Next steps:"
log "  - Continue to task 14.1: Create NetworkPolicy manifests"
log "  - Continue to task 15.1: Write deploy.sh orchestration script"
