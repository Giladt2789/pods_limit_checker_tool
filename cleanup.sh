#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        exit 1
    fi
}

# Delete Kubernetes resources
cleanup_k8s() {
    print_info "Removing Kubernetes resources..."

    if [ ! -d "manifests" ]; then
        print_error "manifests/ directory not found"
        exit 1
    fi

    if kubectl delete -f manifests/ &> /dev/null; then
        print_success "Kubernetes resources removed successfully"
    else
        print_warning "Some resources may not have been removed (this is okay if they don't exist)"
        kubectl delete -f manifests/ 2>&1 | grep -v "NotFound" || true
    fi
}

# Remove image from cluster (optional)
cleanup_image() {
    if [ "$1" = "--remove-image" ]; then
        print_info "Detecting cluster type for image removal..."

        # Get current context
        local context
        context=$(kubectl config current-context 2>/dev/null)

        if [[ "$context" == *"minikube"* ]]; then
            print_info "Removing image from Minikube..."
            if minikube image rm k8s-pod-limits-checker:latest &> /dev/null; then
                print_success "Image removed from Minikube"
            else
                print_warning "Could not remove image from Minikube (may not exist)"
            fi
        else
            print_info "Image cleanup not implemented for this cluster type"
            print_info "You can manually remove the local Docker image with:"
            print_info "  docker rmi k8s-pod-limits-checker:latest"
        fi
    fi
}

# Main execution
main() {
    echo ""
    echo "======================================"
    echo "  K8s Pod Limits Checker Cleanup     "
    echo "======================================"
    echo ""

    check_kubectl
    cleanup_k8s
    cleanup_image "$@"

    echo ""
    print_success "Cleanup completed!"
    echo ""
    print_info "To remove the local Docker image, run:"
    echo "  docker rmi k8s-pod-limits-checker:latest"
    echo ""
}

# Run main function
main "$@"
