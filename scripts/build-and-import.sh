#!/usr/bin/env bash
# =============================================================================
# TechFix — Build and Import Script
# 
# Builds Docker images for Laravel and Nginx, verifies image sizes, and
# imports them into the k3s containerd runtime.
#
# Requirements: 3.1, 3.2, 3.3
#
# Usage:
#   ./scripts/build-and-import.sh
#
# Prerequisites:
#   - Docker installed and running
#   - k3s installed with containerd runtime
#   - Script executed from project root (TechFix-main/)
#   - sudo access for k3s ctr commands
# =============================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Image tags
LARAVEL_IMAGE="techfix/laravel-app:1.0.0"
NGINX_IMAGE="techfix/nginx:1.0.0"

# Size warning threshold (in MB)
SIZE_THRESHOLD_MB=500

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}TechFix Docker Build and Import${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Function: print_section
# Prints a formatted section header
# -----------------------------------------------------------------------------
print_section() {
    echo ""
    echo -e "${GREEN}>>> $1${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: print_error
# Prints an error message and exits
# -----------------------------------------------------------------------------
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Function: print_warning
# Prints a warning message
# -----------------------------------------------------------------------------
print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# -----------------------------------------------------------------------------
# Function: check_prerequisites
# Verifies that Docker and k3s are available
# -----------------------------------------------------------------------------
check_prerequisites() {
    print_section "Checking prerequisites"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
    fi
    echo -e "  ${GREEN}✓${NC} Docker found: $(docker --version)"
    
    if ! command -v k3s &> /dev/null; then
        print_error "k3s is not installed or not in PATH"
    fi
    echo -e "  ${GREEN}✓${NC} k3s found: $(k3s --version | head -n1)"
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
    fi
    echo -e "  ${GREEN}✓${NC} Docker daemon is running"
    
    if [ ! -d "docker/laravel" ] || [ ! -d "docker/nginx" ]; then
        print_error "Must run script from project root (docker/ directory not found)"
    fi
    echo -e "  ${GREEN}✓${NC} Running from project root"
}

# -----------------------------------------------------------------------------
# Function: build_laravel_image
# Builds the Laravel Docker image with multi-stage Dockerfile
# -----------------------------------------------------------------------------
build_laravel_image() {
    print_section "Building Laravel image: ${LARAVEL_IMAGE}"
    
    if docker build -f docker/laravel/Dockerfile -t "${LARAVEL_IMAGE}" .; then
        echo -e "  ${GREEN}✓${NC} Laravel image built successfully"
    else
        print_error "Failed to build Laravel image"
    fi
}

# -----------------------------------------------------------------------------
# Function: verify_laravel_size
# Checks the size of the Laravel image and warns if > 500MB
# -----------------------------------------------------------------------------
verify_laravel_size() {
    print_section "Verifying Laravel image size"
    
    # Get image size in MB
    # docker image ls outputs size in format like "1.23GB" or "456MB"
    local size_output=$(docker image ls "${LARAVEL_IMAGE}" --format "{{.Size}}")
    
    if [ -z "$size_output" ]; then
        print_error "Could not determine Laravel image size (image not found?)"
    fi
    
    echo "  Image size: ${size_output}"
    
    # Extract numeric value and unit
    local size_value=$(echo "$size_output" | grep -oE '[0-9.]+' | head -n1)
    local size_unit=$(echo "$size_output" | grep -oE '[A-Za-z]+')
    
    # Convert to MB for comparison
    local size_mb=0
    if [ "$size_unit" = "GB" ]; then
        size_mb=$(echo "$size_value * 1024" | bc)
    elif [ "$size_unit" = "MB" ]; then
        size_mb=$(echo "$size_value" | cut -d'.' -f1)
    elif [ "$size_unit" = "kB" ] || [ "$size_unit" = "KB" ]; then
        size_mb=$(echo "$size_value / 1024" | bc)
    else
        size_mb=$(echo "$size_value" | cut -d'.' -f1)
    fi
    
    # Compare with threshold
    if [ $(echo "$size_mb > $SIZE_THRESHOLD_MB" | bc) -eq 1 ]; then
        print_warning "Laravel image size (${size_output}) exceeds ${SIZE_THRESHOLD_MB}MB threshold"
        echo "           Consider optimizing the Dockerfile to reduce image size:"
        echo "           - Remove unnecessary dependencies"
        echo "           - Use .dockerignore to exclude unused files"
        echo "           - Minimize the number of RUN layers"
    else
        echo -e "  ${GREEN}✓${NC} Image size is within acceptable limits"
    fi
}

# -----------------------------------------------------------------------------
# Function: build_nginx_image
# Builds the Nginx Docker image
# -----------------------------------------------------------------------------
build_nginx_image() {
    print_section "Building Nginx image: ${NGINX_IMAGE}"
    
    if docker build -f docker/nginx/Dockerfile -t "${NGINX_IMAGE}" .; then
        echo -e "  ${GREEN}✓${NC} Nginx image built successfully"
    else
        print_error "Failed to build Nginx image"
    fi
}

# -----------------------------------------------------------------------------
# Function: verify_nginx_size
# Checks the size of the Nginx image (informational only)
# -----------------------------------------------------------------------------
verify_nginx_size() {
    print_section "Verifying Nginx image size"
    
    local size_output=$(docker image ls "${NGINX_IMAGE}" --format "{{.Size}}")
    
    if [ -z "$size_output" ]; then
        print_error "Could not determine Nginx image size (image not found?)"
    fi
    
    echo "  Image size: ${size_output}"
    echo -e "  ${GREEN}✓${NC} Nginx image size recorded"
}

# -----------------------------------------------------------------------------
# Function: import_to_k3s
# Imports both images into k3s containerd runtime
# -----------------------------------------------------------------------------
import_to_k3s() {
    print_section "Importing images to k3s containerd"
    
    echo "  Importing Laravel image..."
    if docker save "${LARAVEL_IMAGE}" | sudo k3s ctr images import -; then
        echo -e "  ${GREEN}✓${NC} Laravel image imported to k3s"
    else
        print_error "Failed to import Laravel image to k3s"
    fi
    
    echo ""
    echo "  Importing Nginx image..."
    if docker save "${NGINX_IMAGE}" | sudo k3s ctr images import -; then
        echo -e "  ${GREEN}✓${NC} Nginx image imported to k3s"
    else
        print_error "Failed to import Nginx image to k3s"
    fi
}

# -----------------------------------------------------------------------------
# Function: verify_k3s_images
# Verifies that both images are visible in k3s containerd
# -----------------------------------------------------------------------------
verify_k3s_images() {
    print_section "Verifying images in k3s containerd"
    
    echo "  Checking for techfix images..."
    local k3s_images=$(sudo k3s ctr images list | grep techfix || true)
    
    if [ -z "$k3s_images" ]; then
        print_error "No techfix images found in k3s containerd after import"
    fi
    
    echo "$k3s_images"
    echo ""
    
    # Verify both specific images exist
    if echo "$k3s_images" | grep -q "techfix/laravel-app:1.0.0"; then
        echo -e "  ${GREEN}✓${NC} Laravel image found in k3s"
    else
        print_error "Laravel image not found in k3s containerd"
    fi
    
    if echo "$k3s_images" | grep -q "techfix/nginx:1.0.0"; then
        echo -e "  ${GREEN}✓${NC} Nginx image found in k3s"
    else
        print_error "Nginx image not found in k3s containerd"
    fi
}

# -----------------------------------------------------------------------------
# Main execution flow
# -----------------------------------------------------------------------------
main() {
    check_prerequisites
    build_laravel_image
    verify_laravel_size
    build_nginx_image
    verify_nginx_size
    import_to_k3s
    verify_k3s_images
    
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Build and import completed successfully!${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo ""
    echo "Images are now available in k3s containerd and can be used in Kubernetes deployments."
    echo ""
    echo "Next steps:"
    echo "  1. Create Kubernetes secrets: ./scripts/create-secrets.sh"
    echo "  2. Apply Kubernetes manifests: kubectl apply -f k8s/"
    echo ""
}

# Execute main function
main
