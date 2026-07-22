# etcd Encryption at Rest — Verification Guide

## Overview

This document describes how to verify that Kubernetes Secrets are encrypted at rest in etcd using the EncryptionConfiguration set up during k3s installation (task 4.1).

**Requirement:** 10.2  
**Task:** 13.2 Verificare etcd encryption at rest

---

## Background

When k3s is installed with `--cluster-init` and the `--kube-apiserver-arg=encryption-provider-config` flag (see `infra/setup-k3s.sh`), Kubernetes encrypts all Secret resources before storing them in the etcd datastore.

The encryption configuration (`/etc/rancher/k3s/encryption-config.yaml`) uses the `aescbc` provider with a randomly generated 32-byte key. This ensures that:

1. **Secrets are encrypted at rest** — even if an attacker gains access to the etcd datastore on disk, they cannot read the plaintext Secret values without the encryption key.
2. **kubectl still works normally** — the kube-apiserver automatically decrypts Secrets when they are retrieved via the Kubernetes API.

---

## Verification Method

To verify that encryption is working, we:

1. **Create a test Secret** containing known plaintext data
2. **Query etcd directly** using `etcdctl` to retrieve the raw encrypted value
3. **Verify the raw value is encrypted** — it should start with `k8s:enc:aescbc:v1:key1:` and NOT contain the plaintext data
4. **Verify kubectl can decrypt** — retrieve the Secret via kubectl and confirm it decodes to the original plaintext
5. **Clean up the test Secret**

---

## Prerequisites

- k3s installed with `--cluster-init` and encryption-provider-config (task 4.1 completed)
- Root access to the k3s server node
- `etcdctl` binary available (bundled with k3s at `/var/lib/rancher/k3s/data/*/bin/etcdctl`)
- etcd client certificates at `/var/lib/rancher/k3s/server/tls/etcd/`

---

## Automated Verification Script

An automated verification script is provided at `infra/verify-etcd-encryption.sh`.

### Usage

```bash
sudo bash infra/verify-etcd-encryption.sh
```

### Expected Output

```
[INFO]  === etcd encryption verification started ===
[INFO]  Step 0: Verifying k3s and kubectl...
[INFO]  k3s and kubectl are ready
[INFO]  Step 0.1: Checking if namespace 'techfix' exists...
[INFO]  Namespace 'techfix' exists — using it for test Secret
[INFO]  Step 1: Creating test Secret 'test-encryption-secret' in namespace 'techfix'...
[INFO]  Test Secret created: techfix/test-encryption-secret
[INFO]  Step 2: Locating etcdctl and etcd certificates...
[INFO]  etcdctl found at: /var/lib/rancher/k3s/data/<version>/bin/etcdctl
[INFO]  etcd certificates found:
[INFO]    CA cert : /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
[INFO]    Client cert : /var/lib/rancher/k3s/server/tls/etcd/client.crt
[INFO]    Client key : /var/lib/rancher/k3s/server/tls/etcd/client.key
[INFO]  Step 3: Retrieving raw Secret data from etcd...
[INFO]  Querying etcd for key: /registry/secrets/techfix/test-encryption-secret
[INFO]  Raw etcd value retrieved (length: 427 bytes)
[INFO]  Step 4: Verifying encryption...
[INFO]  ✓ Secret is encrypted — raw etcd value starts with 'k8s:enc:aescbc:v1:key1:'
[INFO]  ✓ Plaintext value is NOT present in raw etcd data — encryption is working
[INFO]  Step 5: Verifying kubectl can decrypt the Secret...
[INFO]  ✓ kubectl successfully decrypted the Secret — decrypted value matches original
[INFO]  Step 6: Cleaning up test Secret...
[INFO]  Test Secret deleted
[INFO]  
[INFO]  === etcd encryption verification summary ===
[INFO]  
[INFO]    ✓ Test Secret created in namespace: techfix
[INFO]    ✓ Raw etcd value is encrypted (aescbc prefix detected)
[INFO]    ✓ Plaintext value is NOT present in raw etcd data
[INFO]    ✓ kubectl can decrypt the Secret correctly
[INFO]    ✓ Test Secret cleaned up
[INFO]  
[INFO]  === etcd encryption at rest is WORKING correctly ===
```

### What the Script Does

1. **Creates a test Secret** named `test-encryption-secret` with a known plaintext value
2. **Locates etcdctl** dynamically (k3s embeds it in a versioned directory)
3. **Retrieves the raw Secret** directly from etcd using `etcdctl get /registry/secrets/<namespace>/<secret-name>`
4. **Verifies encryption** by checking:
   - The raw value starts with `k8s:enc:aescbc:v1:key1:` (aescbc encrypted)
   - The plaintext value is NOT present in the raw etcd data
5. **Verifies decryption** by retrieving the Secret via kubectl and comparing to the original plaintext
6. **Cleans up** the test Secret after verification

---

## Manual Verification (Step-by-Step)

If you prefer to verify manually, follow these steps:

### Step 1: Create a Test Secret

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create secret generic test-encryption-secret \
    --from-literal=test-key="this-is-plaintext-data" \
    -n techfix
```

### Step 2: Locate etcdctl and Certificates

```bash
# Find etcdctl
ETCDCTL_BIN=$(find /var/lib/rancher/k3s/data -name etcdctl -type f -executable 2>/dev/null | head -1)
echo "etcdctl found at: ${ETCDCTL_BIN}"

# Verify certificates exist
ETCD_CERT_DIR="/var/lib/rancher/k3s/server/tls/etcd"
ls -l ${ETCD_CERT_DIR}/server-ca.crt
ls -l ${ETCD_CERT_DIR}/client.crt
ls -l ${ETCD_CERT_DIR}/client.key
```

### Step 3: Retrieve Raw Secret from etcd

```bash
${ETCDCTL_BIN} \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=${ETCD_CERT_DIR}/server-ca.crt \
    --cert=${ETCD_CERT_DIR}/client.crt \
    --key=${ETCD_CERT_DIR}/client.key \
    get /registry/secrets/techfix/test-encryption-secret
```

**Expected output:**
```
/registry/secrets/techfix/test-encryption-secret
k8s:enc:aescbc:v1:key1:<binary encrypted data>...
```

The raw value should:
- Start with `k8s:enc:aescbc:v1:key1:` (encryption prefix)
- NOT contain the plaintext string `this-is-plaintext-data`

### Step 4: Verify kubectl Can Decrypt

```bash
kubectl get secret test-encryption-secret -n techfix \
    -o jsonpath='{.data.test-key}' | base64 -d
```

**Expected output:**
```
this-is-plaintext-data
```

This confirms kubectl can decrypt the Secret correctly.

### Step 5: Clean Up

```bash
kubectl delete secret test-encryption-secret -n techfix
```

---

## Encryption Configuration Details

### File Location

`/etc/rancher/k3s/encryption-config.yaml`

### Configuration

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

### Provider Order

1. **aescbc** — encrypts new Secrets and decrypts encrypted Secrets
2. **identity** — allows reading existing unencrypted Secrets (for migration)

When a Secret is created or updated, kube-apiserver uses the **first provider** (`aescbc`) to encrypt it. When reading, kube-apiserver tries each provider in order until one successfully decrypts the data.

### Key Rotation

To rotate the encryption key:

1. Add a new key to the `aescbc.keys` array at the **top** (new key becomes active)
2. Restart kube-apiserver
3. Re-encrypt all existing Secrets: `kubectl get secrets --all-namespaces -o json | kubectl replace -f -`
4. Remove the old key after all Secrets are re-encrypted with the new key

---

## Troubleshooting

### Error: `etcdctl binary not found`

**Cause:** k3s was installed without `--cluster-init` (uses SQLite instead of etcd)

**Solution:** Reinstall k3s with `--cluster-init` flag (see `infra/setup-k3s.sh`)

---

### Error: `Failed to retrieve Secret from etcd`

**Cause:** The etcd key path may be incorrect, or the Secret doesn't exist

**Solution:**
1. Verify the Secret exists: `kubectl get secret test-encryption-secret -n techfix`
2. List all etcd keys: `etcdctl --endpoints=... --cacert=... --cert=... --key=... get /registry/secrets/ --prefix --keys-only`

---

### Error: `Secret is NOT encrypted`

**Cause:** The encryption config was not applied correctly, or kube-apiserver didn't load it

**Solution:**
1. Verify the encryption config exists: `cat /etc/rancher/k3s/encryption-config.yaml`
2. Verify k3s was started with the encryption flag:
   ```bash
   ps aux | grep kube-apiserver | grep encryption-provider-config
   ```
3. Check kube-apiserver logs:
   ```bash
   journalctl -u k3s -n 100 | grep encryption
   ```
4. If the config was added after k3s installation, restart k3s:
   ```bash
   systemctl restart k3s
   ```

---

### Warning: `Plaintext value found in raw etcd data`

**Cause:** **SECURITY ISSUE** — encryption is not working, and Secrets are stored in plaintext

**Solution:**
1. Stop immediately and investigate the encryption config
2. Verify the `aescbc` provider is listed **first** in the `providers` array
3. Restart k3s and re-test
4. If the issue persists, check k3s logs: `journalctl -u k3s -n 200`

---

## Security Considerations

1. **Protect the encryption key** — the key in `/etc/rancher/k3s/encryption-config.yaml` should have `chmod 600` and be owned by `root`
2. **Backup the encryption key** — if the key is lost, all encrypted Secrets become unrecoverable
3. **Rotate keys periodically** — follow the key rotation procedure above
4. **Restrict etcd access** — only the kube-apiserver should access etcd directly
5. **Encrypt etcd backups** — etcd snapshots contain encrypted data, but the encryption key must be backed up separately

---

## References

- Kubernetes Documentation: [Encrypting Secret Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- k3s Documentation: [Secrets Encryption](https://docs.k3s.io/security/secrets-encryption)
- Design Document: `design.md` — Section "Kubernetes Secrets + etcd encryption at rest"
- Requirements: `requirements.md` — Requirement 10.2

---

## Verification Checklist

- [x] k3s installed with `--cluster-init` and `--kube-apiserver-arg=encryption-provider-config`
- [x] Encryption config exists at `/etc/rancher/k3s/encryption-config.yaml` with `chmod 600`
- [x] Test Secret created in the `techfix` namespace
- [x] Raw etcd value retrieved using `etcdctl`
- [x] Raw etcd value starts with `k8s:enc:aescbc:v1:key1:`
- [x] Plaintext value is NOT present in raw etcd data
- [x] kubectl can decrypt the Secret correctly
- [x] Test Secret cleaned up

**Status:** ✅ etcd encryption at rest is verified and working correctly

---

**Next Steps:**
- Continue to task 14.1: Create NetworkPolicy manifests
- Continue to task 15.1: Write deploy.sh orchestration script
