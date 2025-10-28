#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="k8s-pod-limits-checker:latest"

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        print_error "docker not found"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Please ensure your kubeconfig is properly configured"
        exit 1
    fi

    print_success "Prerequisites met"
}

# Build image
build_image() {
    print_info "Building Docker image..."

    if docker build -t "$IMAGE_NAME" . > /dev/null 2>&1; then
        print_success "Image built successfully"
    else
        print_error "Failed to build image"
        print_info "Running build with verbose output..."
        docker build -t "$IMAGE_NAME" .
        exit 1
    fi
}

# Run container locally
run_container() {
    print_info "Running pod limits checker..."
    echo ""

    # Get kubeconfig path
    local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"

    if [ ! -f "$kubeconfig" ]; then
        print_error "Kubeconfig not found at $kubeconfig"
        exit 1
    fi

    # Run with provided arguments or defaults
    docker run --rm -v "$kubeconfig:/root/.kube/config:ro" "$IMAGE_NAME" "$@"

    echo ""
    print_success "Execution completed"
}

# Show usage
show_usage() {
    cat << EOF

Usage: $0 [OPTIONS]

Run the Kubernetes Pod Limits Checker locally using Docker.

Options:
  --output FORMAT        Output format: table, json, csv (default: table)
  --namespace NAME       Check specific namespace (default: all namespaces)
  -n NAME                Short form of --namespace
  --log-level LEVEL      Logging level: DEBUG, INFO, WARNING, ERROR (default: INFO)
  --annotate             Automatically annotate pods with warning labels
  --help                 Show this help message

Examples:
  $0                                    # Run with default settings (table output, all namespaces)
  $0 --output json                      # Output in JSON format
  $0 --namespace kube-system            # Check only kube-system namespace
  $0 -n production --output csv         # Check production namespace, output CSV
  $0 --annotate --namespace default     # Annotate pods in default namespace

EOF
}

# Main execution
main() {
    # Check for help flag
    if [[ "$*" == *"--help"* ]] || [[ "$*" == *"-h"* ]]; then
        show_usage
        exit 0
    fi

    echo ""
    echo "======================================"
    echo "  K8s Pod Limits Checker (Local)     "
    echo "======================================"
    echo ""

    check_prerequisites
    build_image
    run_container "$@"
}

# Run main function
main "$@"
