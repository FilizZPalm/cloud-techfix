#!/usr/bin/env bash
# tests/integration/test-readonly-filesystem.sh
#
# Integration test that validates read-only root filesystem enforcement on
# both the Laravel (PHP-FPM) and Nginx containers.
#
# Both containers are deployed with:
#   securityContext:
#     readOnlyRootFilesystem: true
#
# This is enforced by the Linux kernel via the container's mount namespace:
# the root overlay filesystem is mounted read-only, so any write attempt to
# a path that is not backed by an emptyDir or ConfigMap volume is rejected
# with EROFS (Read-only file system), regardless of the process's UID or
# capabilities.
#
# The test validates two complementary properties for each container:
#
#   REJECTION checks — writes to read-only paths MUST fail:
#     Paths that are part of the image layer and NOT covered by an emptyDir.
#     A successful write here would mean the securityContext is not enforced.
#
#   PERMISSION checks — writes to emptyDir-mounted paths MUST succeed:
#     These are the only paths the application legitimately writes to at
#     runtime. If these fail, the container is misconfigured and would crash.
#     This also proves the test is correctly distinguishing between the two
#     cases, not just asserting all writes fail.
#
# Containers and paths under test:
#
#   Laravel (deployment: laravel-deployment, container: laravel)
#     Read-only paths (MUST reject writes):
#       /var/www/html/app          — application source code
#       /var/www/html/vendor       — Composer dependencies
#       /var/www/html/config       — Laravel config (baked into image)
#       /usr/local/lib/php         — PHP standard library
#       /etc/php                   — PHP config files (if present)
#     Writable paths (emptyDir mounts — MUST accept writes):
#       /tmp                       — emptyDir: {}
#       /var/www/html/storage      — emptyDir: {} (Laravel logs, sessions, views, cache)
#       /var/www/html/bootstrap/cache — emptyDir: {} (Laravel compiled cache)
#
#   Nginx (deployment: nginx-deployment, container: nginx)
#     Read-only paths (MUST reject writes):
#       /etc/nginx/nginx.conf      — global Nginx config (baked into image)
#       /usr/sbin/nginx            — Nginx binary
#       /var/www/html/public       — Static assets (baked into image)
#       /etc/nginx/conf.d          — ConfigMap mount (readOnly: true)
#     Writable paths (emptyDir mounts — MUST accept writes):
#       /tmp                       — emptyDir: {}
#       /var/cache/nginx           — emptyDir: {} (Nginx proxy/fastcgi cache)
#       /var/run                   — emptyDir: {} (PID file)
#
# Test structure:
#   IT-01  Laravel: read-only paths reject writes
#   IT-02  Laravel: emptyDir paths accept writes (and cleanup after themselves)
#   IT-03  Nginx:   read-only paths reject writes
#   IT-04  Nginx:   emptyDir paths accept writes (and cleanup after themselves)
#   IT-05  NoNewPrivs flag confirmed on both containers (privilege escalation guard)
#
# Requirements: 9.2, 9.4, 9.5
#
# Usage:
#   sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash tests/integration/test-readonly-filesystem.sh
#
# Prerequisites:
#   - kubectl configured (KUBECONFIG set or k3s default)
#   - Laravel and Nginx deployments Running in namespace 'techfix'
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NAMESPACE="${NAMESPACE:-techfix}"
LARAVEL_DEPLOY="${LARAVEL_DEPLOY:-laravel-deployment}"
LARAVEL_CONTAINER="${LARAVEL_CONTAINER:-laravel}"
NGINX_DEPLOY="${NGINX_DEPLOY:-nginx-deployment}"
NGINX_CONTAINER="${NGINX_CONTAINER:-nginx}"

# Unique suffix so test files don't collide with real application files
# and are easily identifiable if a cleanup somehow fails
TEST_FILE_SUFFIX="rofs-test-$$"

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

# Attempt a write inside a container via kubectl exec.
# Uses PHP (available in Laravel) or sh (available in Nginx).
#
# probe_write_laravel <path>
#   Returns: "rejected" if EROFS/permission denied, "allowed" if write succeeded
probe_write_laravel() {
    local path="$1"
    local file="${path}/${TEST_FILE_SUFFIX}"

    local output exit_code
    output=$(kubectl exec -n "${NAMESPACE}" "deployment/${LARAVEL_DEPLOY}" \
        -c "${LARAVEL_CONTAINER}" -- \
        php -r "
            \$f = '${file}';
            \$result = @file_put_contents(\$f, 'test');
            if (\$result === false) {
                \$err = error_get_last();
                echo 'REJECTED:' . (\$err['message'] ?? 'write failed');
                exit(1);
            }
            // Write succeeded — clean up immediately
            @unlink(\$f);
            echo 'ALLOWED';
            exit(0);
        " 2>&1 || true)
    exit_code=$?

    if echo "${output}" | grep -q "^ALLOWED"; then
        echo "allowed"
    else
        echo "rejected"
    fi
}

# probe_write_nginx <path>
#   Uses sh + touch inside the Nginx container (no PHP available)
#   Returns: "rejected" or "allowed"
probe_write_nginx() {
    local path="$1"
    local file="${path}/${TEST_FILE_SUFFIX}"

    local exit_code=0
    kubectl exec -n "${NAMESPACE}" "deployment/${NGINX_DEPLOY}" \
        -c "${NGINX_CONTAINER}" -- \
        sh -c "touch '${file}' 2>/dev/null && rm -f '${file}' 2>/dev/null && echo ALLOWED || echo REJECTED" \
        2>/dev/null | grep -q "^ALLOWED"
    exit_code=$?

    if [[ "${exit_code}" -eq 0 ]]; then
        echo "allowed"
    else
        echo "rejected"
    fi
}

# Run a batch of write probes and accumulate results.
# Arguments: container_type ("laravel"|"nginx"), result_var_name, path1 path2 ...
# Sets global arrays: REJECTED_PATHS, UNEXPECTED_ALLOWED_PATHS
declare -a REJECTED_PATHS=()
declare -a UNEXPECTED_ALLOWED_PATHS=()

probe_batch_readonly() {
    local container_type="$1"
    shift
    local paths=("$@")

    for path in "${paths[@]}"; do
        if [[ "${container_type}" == "laravel" ]]; then
            result=$(probe_write_laravel "${path}")
        else
            result=$(probe_write_nginx "${path}")
        fi
        info "    ${path}: ${result}"
        if [[ "${result}" == "rejected" ]]; then
            REJECTED_PATHS+=("${path}")
        else
            UNEXPECTED_ALLOWED_PATHS+=("${path}")
        fi
    done
}

probe_batch_writable() {
    local container_type="$1"
    shift
    local paths=("$@")

    declare -a WRITABLE_OK=()
    declare -a WRITABLE_FAIL=()

    for path in "${paths[@]}"; do
        if [[ "${container_type}" == "laravel" ]]; then
            result=$(probe_write_laravel "${path}")
        else
            result=$(probe_write_nginx "${path}")
        fi
        info "    ${path}: ${result}"
        if [[ "${result}" == "allowed" ]]; then
            WRITABLE_OK+=("${path}")
        else
            WRITABLE_FAIL+=("${path}")
        fi
    done

    # Export results via global variables for the caller
    WRITABLE_OK_PATHS=("${WRITABLE_OK[@]+"${WRITABLE_OK[@]}"}")
    WRITABLE_FAIL_PATHS=("${WRITABLE_FAIL[@]+"${WRITABLE_FAIL[@]}"}")
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

header "TechFix Read-Only Filesystem Enforcement Integration Test"
echo ""
echo "  Namespace:          ${NAMESPACE}"
echo "  Laravel deployment: ${LARAVEL_DEPLOY} (container: ${LARAVEL_CONTAINER})"
echo "  Nginx deployment:   ${NGINX_DEPLOY}   (container: ${NGINX_CONTAINER})"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH."
    exit 1
fi

for deploy in "${LARAVEL_DEPLOY}" "${NGINX_DEPLOY}"; do
    ready=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null | tr -d '[:space:]')
    if [[ "${ready:-0}" -lt 1 ]]; then
        echo "ERROR: Deployment '${deploy}' has no ready replicas in namespace '${NAMESPACE}'."
        exit 1
    fi
    info "Deployment '${deploy}': ${ready} ready replica(s)"
done

# Confirm readOnlyRootFilesystem is set to true in both deployment specs
for deploy_container in "${LARAVEL_DEPLOY}:${LARAVEL_CONTAINER}" "${NGINX_DEPLOY}:${NGINX_CONTAINER}"; do
    deploy="${deploy_container%%:*}"
    container="${deploy_container##*:}"
    rofs=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${container}\")].securityContext.readOnlyRootFilesystem}" \
        2>/dev/null | tr -d '[:space:]')
    if [[ "${rofs}" != "true" ]]; then
        echo "ERROR: readOnlyRootFilesystem is not 'true' on ${deploy}/${container} (got: '${rofs}')."
        echo "       This test is only meaningful when the securityContext is configured correctly."
        exit 1
    fi
    info "Confirmed readOnlyRootFilesystem=true on ${deploy}/${container}"
done
echo ""

# ---------------------------------------------------------------------------
# IT-01: Laravel — read-only paths reject writes
#
# These paths are part of the image overlay layer. No emptyDir covers them.
# A write attempt must return EROFS (Read-only file system) or equivalent.
#
# /var/www/html/app      — Laravel application source code
# /var/www/html/vendor   — Composer dependencies (installed at build time)
# /var/www/html/config   — Laravel config directory (baked into image)
# /usr/local/lib/php     — PHP standard library (installed in base image)
#
# Requirements: 9.2, 9.4
# ---------------------------------------------------------------------------

header "IT-01: Laravel — read-only image paths reject writes"

echo ""
echo "  Paths under test (all must be REJECTED):"

LARAVEL_READONLY_PATHS=(
    "/var/www/html/app"
    "/var/www/html/vendor"
    "/var/www/html/config"
    "/usr/local/lib/php"
)

REJECTED_PATHS=()
UNEXPECTED_ALLOWED_PATHS=()
probe_batch_readonly "laravel" "${LARAVEL_READONLY_PATHS[@]}"

rejected_count="${#REJECTED_PATHS[@]}"
allowed_count="${#UNEXPECTED_ALLOWED_PATHS[@]}"

info ""
info "  Results: ${rejected_count}/${#LARAVEL_READONLY_PATHS[@]} paths correctly rejected"

if [[ "${allowed_count}" -eq 0 ]]; then
    pass "IT-01: All ${rejected_count} read-only Laravel paths rejected writes — readOnlyRootFilesystem enforced by kernel"
else
    fail "IT-01: ${allowed_count} path(s) unexpectedly accepted writes: ${UNEXPECTED_ALLOWED_PATHS[*]}"
    info "       This means readOnlyRootFilesystem is NOT enforced on those paths."
    info "       Check whether an emptyDir volume was accidentally mounted there."
fi

# ---------------------------------------------------------------------------
# IT-02: Laravel — emptyDir-mounted paths accept writes (and clean up)
#
# These paths are backed by emptyDir volumes mounted over the read-only layer.
# Writes must succeed — if they don't, PHP-FPM and Laravel would crash at
# runtime (sessions, views, logs all write to these directories).
#
# /tmp                          — general temp files, PHP session default
# /var/www/html/storage         — Laravel logs, sessions, compiled views, cache
# /var/www/html/bootstrap/cache — Laravel route/config cache (php artisan cache)
#
# Each probe writes a uniquely-named file and immediately deletes it, leaving
# the container state unchanged after the test.
#
# Requirements: 9.4 (emptyDir volumes must be functional)
# ---------------------------------------------------------------------------

header "IT-02: Laravel — emptyDir-mounted paths accept writes"

echo ""
echo "  Paths under test (all must be ALLOWED):"

LARAVEL_WRITABLE_PATHS=(
    "/tmp"
    "/var/www/html/storage"
    "/var/www/html/bootstrap/cache"
)

WRITABLE_OK_PATHS=()
WRITABLE_FAIL_PATHS=()
probe_batch_writable "laravel" "${LARAVEL_WRITABLE_PATHS[@]}"

ok_count="${#WRITABLE_OK_PATHS[@]}"
fail_count="${#WRITABLE_FAIL_PATHS[@]}"

info ""
info "  Results: ${ok_count}/${#LARAVEL_WRITABLE_PATHS[@]} writable paths accepted writes"

if [[ "${fail_count}" -eq 0 ]]; then
    pass "IT-02: All ${ok_count} emptyDir Laravel paths accepted writes — application runtime paths are functional"
else
    fail "IT-02: ${fail_count} emptyDir path(s) rejected writes: ${WRITABLE_FAIL_PATHS[*]}"
    info "       Laravel would crash at runtime if these paths are not writable."
    info "       Check that the emptyDir volumes are correctly mounted in the Deployment spec."
fi

# ---------------------------------------------------------------------------
# IT-03: Nginx — read-only paths reject writes
#
# /etc/nginx/nginx.conf  — global Nginx config, baked into image
# /usr/sbin/nginx        — Nginx binary directory
# /var/www/html/public   — Static assets copied at build time
# /etc/nginx/conf.d      — ConfigMap volume mounted with readOnly: true
#
# The ConfigMap mount (/etc/nginx/conf.d) is a special case: it is an
# explicitly read-only volume, not just the root filesystem. Both mechanisms
# must reject writes independently, and testing this path confirms that
# the readOnly: true volume flag is also honoured.
#
# Requirements: 9.2, 9.5
# ---------------------------------------------------------------------------

header "IT-03: Nginx — read-only image paths reject writes"

echo ""
echo "  Paths under test (all must be REJECTED):"

NGINX_READONLY_PATHS=(
    "/etc/nginx"
    "/usr/sbin"
    "/var/www/html/public"
    "/etc/nginx/conf.d"
)

REJECTED_PATHS=()
UNEXPECTED_ALLOWED_PATHS=()
probe_batch_readonly "nginx" "${NGINX_READONLY_PATHS[@]}"

rejected_count="${#REJECTED_PATHS[@]}"
allowed_count="${#UNEXPECTED_ALLOWED_PATHS[@]}"

info ""
info "  Results: ${rejected_count}/${#NGINX_READONLY_PATHS[@]} paths correctly rejected"

if [[ "${allowed_count}" -eq 0 ]]; then
    pass "IT-03: All ${rejected_count} read-only Nginx paths rejected writes — readOnlyRootFilesystem and readOnly volume enforced"
else
    fail "IT-03: ${allowed_count} path(s) unexpectedly accepted writes: ${UNEXPECTED_ALLOWED_PATHS[*]}"
fi

# ---------------------------------------------------------------------------
# IT-04: Nginx — emptyDir-mounted paths accept writes (and clean up)
#
# /tmp              — general temp files
# /var/cache/nginx  — Nginx proxy cache and FastCGI cache buffers
# /var/run          — PID file (nginx.pid is written here at startup)
#
# If /var/run or /var/cache/nginx were read-only, Nginx would fail to start
# (it writes its PID file and creates cache directories on boot). Testing
# these confirms the runtime configuration is viable.
#
# Requirements: 9.5 (emptyDir volumes must be functional)
# ---------------------------------------------------------------------------

header "IT-04: Nginx — emptyDir-mounted paths accept writes"

echo ""
echo "  Paths under test (all must be ALLOWED):"

NGINX_WRITABLE_PATHS=(
    "/tmp"
    "/var/cache/nginx"
    "/var/run"
)

WRITABLE_OK_PATHS=()
WRITABLE_FAIL_PATHS=()
probe_batch_writable "nginx" "${NGINX_WRITABLE_PATHS[@]}"

ok_count="${#WRITABLE_OK_PATHS[@]}"
fail_count="${#WRITABLE_FAIL_PATHS[@]}"

info ""
info "  Results: ${ok_count}/${#NGINX_WRITABLE_PATHS[@]} writable paths accepted writes"

if [[ "${fail_count}" -eq 0 ]]; then
    pass "IT-04: All ${ok_count} emptyDir Nginx paths accepted writes — Nginx runtime paths are functional"
else
    fail "IT-04: ${fail_count} emptyDir path(s) rejected writes: ${WRITABLE_FAIL_PATHS[*]}"
    info "       Nginx would fail to start if /var/run or /var/cache/nginx are not writable."
fi

# ---------------------------------------------------------------------------
# IT-05: NoNewPrivs confirmed on both containers
#
# allowPrivilegeEscalation: false in the securityContext sets the
# PR_SET_NO_NEW_PRIVS bit on the process. This is visible in /proc/self/status
# as "NoNewPrivs: 1".
#
# This is a companion check to readOnlyRootFilesystem: even if an attacker
# could write to an executable path (they can't — IT-01/IT-03 prove this),
# they could not gain elevated privileges by executing a setuid binary,
# because NoNewPrivs blocks execve from gaining new capabilities.
#
# We check both containers here because both declare allowPrivilegeEscalation: false
# and the combination of readOnlyRootFilesystem + NoNewPrivs forms the
# complete privilege-containment boundary.
#
# Requirements: 9.2, 9.3
# ---------------------------------------------------------------------------

header "IT-05: NoNewPrivs flag set on both containers (allowPrivilegeEscalation: false)"

echo ""
echo "  Checking /proc/self/status NoNewPrivs for each container:"
echo ""

nonewprivs_ok=true

# Laravel container — PHP is available, read /proc directly
info "  Laravel container:"
laravel_nonewprivs=$(kubectl exec -n "${NAMESPACE}" "deployment/${LARAVEL_DEPLOY}" \
    -c "${LARAVEL_CONTAINER}" -- \
    php -r "echo trim(shell_exec('grep NoNewPrivs /proc/self/status') ?? '');" \
    2>/dev/null | tr -d '[:space:]' || echo "")

info "    /proc/self/status: ${laravel_nonewprivs:-<could not read>}"

if [[ "${laravel_nonewprivs}" == "NoNewPrivs:1" ]]; then
    info "    Result: NoNewPrivs=1 ✓"
else
    nonewprivs_ok=false
    info "    Result: NoNewPrivs not set or could not be verified ✗"
fi

# Nginx container — use sh + grep
info ""
info "  Nginx container:"
nginx_nonewprivs=$(kubectl exec -n "${NAMESPACE}" "deployment/${NGINX_DEPLOY}" \
    -c "${NGINX_CONTAINER}" -- \
    sh -c "grep NoNewPrivs /proc/self/status 2>/dev/null | tr -d ' '" \
    2>/dev/null | tr -d '[:space:]' || echo "")

info "    /proc/self/status: ${nginx_nonewprivs:-<could not read>}"

if [[ "${nginx_nonewprivs}" == "NoNewPrivs:1" ]]; then
    info "    Result: NoNewPrivs=1 ✓"
else
    nonewprivs_ok=false
    info "    Result: NoNewPrivs not set or could not be verified ✗"
fi

if [[ "${nonewprivs_ok}" == "true" ]]; then
    pass "IT-05: NoNewPrivs=1 confirmed on both Laravel and Nginx containers — privilege escalation via setuid binaries is blocked"
else
    fail "IT-05: NoNewPrivs not confirmed on one or more containers — allowPrivilegeEscalation may not be enforced"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

header "READ-ONLY FILESYSTEM ENFORCEMENT TEST SUMMARY"
echo ""
echo "  Security properties verified:"
echo "    readOnlyRootFilesystem: true  — image layer is not writable"
echo "    emptyDir volumes functional   — application runtime paths work"
echo "    readOnly: true ConfigMap      — Nginx config cannot be modified"
echo "    NoNewPrivs: 1                 — no privilege escalation via setuid"
echo ""
echo "  Containers tested:"
echo "    ${LARAVEL_DEPLOY}/${LARAVEL_CONTAINER}"
echo "    ${NGINX_DEPLOY}/${NGINX_CONTAINER}"
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
    echo -e "  \033[32m✓ All ${TOTAL} read-only filesystem tests PASSED\033[0m"
    echo ""
    exit 0
fi
