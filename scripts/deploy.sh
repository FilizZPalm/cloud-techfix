#!/usr/bin/env bash
# scripts/deploy.sh
# Full deployment orchestration script for TechFix Kubernetes manifests.
#
# This script deploys the entire TechFix application stack to the k3s cluster
# in the correct dependency order, waits for rollouts to complete, and displays
# the final cluster state.
#
# Requirements: 4.1, 4.2, 6.1, 7.1

set -euo pipefail

# ANSI color codes for readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl command not found. Please install kubectl."
        exit 1
    fi
}

# Function to check if k8s cluster is reachable
check_cluster() {
    log_info "Checking cluster connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is k3s running?"
        exit 1
    fi
    log_success "Cluster is reachable"
}

# Detect the k3s node host IP in the pod network (typically 10.42.0.1)
# This IP is used by pods to reach MariaDB instances running on the host VM
detect_node_ip() {
    log_info "Detecting k3s node host IP in pod network..."
    
    # Try to get the InternalIP of the node
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    
    if [[ -z "$NODE_IP" ]]; then
        log_error "Failed to detect node IP. Cannot proceed."
        exit 1
    fi
    
    log_success "Node IP detected: ${NODE_IP}"
    echo "$NODE_IP"
}

# Apply manifests with error handling
apply_manifest() {
    local manifest_path="$1"
    local description="$2"
    
    log_info "Applying ${description}: ${manifest_path}"
    
    if [[ ! -f "$manifest_path" ]]; then
        log_error "Manifest file not found: ${manifest_path}"
        exit 1
    fi
    
    if kubectl apply -f "$manifest_path"; then
        log_success "${description} applied successfully"
    else
        log_error "Failed to apply ${description}: ${manifest_path}"
        exit 1
    fi
}

# Wait for a deployment to be ready
wait_for_deployment() {
    local deployment_name="$1"
    local namespace="$2"
    local timeout="${3:-300}" # Default 5 minutes
    
    log_info "Waiting for deployment ${deployment_name} in namespace ${namespace} to be ready..."
    
    if kubectl rollout status deployment/"${deployment_name}" -n "${namespace}" --timeout="${timeout}s"; then
        log_success "Deployment ${deployment_name} is ready"
        return 0
    else
        log_error "Deployment ${deployment_name} failed to become ready within ${timeout}s"
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting TechFix Kubernetes deployment..."
    echo ""
    
    # Pre-flight checks
    check_kubectl
    check_cluster
    echo ""
    
    # Detect node IP
    NODE_IP=$(detect_node_ip)
    log_info "MariaDB will be accessed via node IP: ${NODE_IP}:3306 (Primary) and ${NODE_IP}:3307 (Replica)"
    echo ""
    
    # Change to project root directory (parent of scripts/)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    cd "${PROJECT_ROOT}"
    
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "K8s manifests directory: ${PROJECT_ROOT}/k8s"
    echo ""
    
    # Deployment order (strict dependencies):
    # 1. Namespace — must exist before any namespaced resources
    # 2. ConfigMaps — referenced by Deployments
    # 3. NetworkPolicies — security controls (can be applied early)
    # 4. Deployments — the actual application pods
    # 5. Services — expose the pods internally
    # 6. HPA — autoscaling rules (depends on Deployments)
    # 7. Ingress — external traffic routing (depends on Services)
    
    log_info "=== Phase 1: Namespace ==="
    apply_manifest "${PROJECT_ROOT}/k8s/namespace.yaml" "Namespace"
    echo ""
    
    log_info "=== Phase 2: ConfigMaps ==="
    apply_manifest "${PROJECT_ROOT}/k8s/configmaps/nginx-config.yaml" "Nginx ConfigMap"
    echo ""
    
    log_info "=== Phase 3: NetworkPolicies ==="
    apply_manifest "${PROJECT_ROOT}/k8s/network-policies.yaml" "NetworkPolicies"
    echo ""
    
    log_info "=== Phase 4: Deployments ==="
    apply_manifest "${PROJECT_ROOT}/k8s/laravel-deployment.yaml" "Laravel Deployment"
    apply_manifest "${PROJECT_ROOT}/k8s/nginx-deployment.yaml" "Nginx Deployment"
    echo ""
    
    log_info "=== Phase 5: Services ==="
    apply_manifest "${PROJECT_ROOT}/k8s/services.yaml" "Services"
    echo ""
    
    log_info "=== Phase 6: HPA (HorizontalPodAutoscaler) ==="
    apply_manifest "${PROJECT_ROOT}/k8s/laravel-hpa.yaml" "Laravel HPA"
    echo ""
    
    log_info "=== Phase 7: Ingress ==="
    apply_manifest "${PROJECT_ROOT}/k8s/ingress.yaml" "Ingress"
    echo ""
    
    # Wait for deployments to be ready
    log_info "=== Waiting for deployments to be ready ==="
    
    ROLLOUT_FAILED=0
    
    if ! wait_for_deployment "laravel-deployment" "techfix" 300; then
        ROLLOUT_FAILED=1
    fi
    
    if ! wait_for_deployment "nginx-deployment" "techfix" 300; then
        ROLLOUT_FAILED=1
    fi
    
    echo ""
    
    if [[ $ROLLOUT_FAILED -eq 1 ]]; then
        log_error "One or more deployments failed to become ready"
        log_warn "Check pod logs with: kubectl logs -n techfix <pod-name>"
        log_warn "Check pod status with: kubectl describe pod -n techfix <pod-name>"
        exit 1
    fi
    
    # Display final cluster state
    log_info "=== Final Cluster State ==="
    echo ""
    
    log_info "All resources in namespace 'techfix':"
    kubectl get all -n techfix
    echo ""
    
    log_info "Pods status:"
    kubectl get pods -n techfix -o wide
    echo ""
    
    log_info "HPA status:"
    kubectl get hpa -n techfix
    echo ""
    
    log_info "Ingress status:"
    kubectl get ingress -n techfix
    echo ""
    
    log_success "TechFix deployment completed successfully!"
    log_info "Access the application via the Ingress Controller (Traefik) at https://techfix.local (or configured domain)"
    log_info "Ensure DNS resolution points techfix.local to the cluster node IP: ${NODE_IP}"
}

# Run main function
main "$@"
