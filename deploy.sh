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
NAMESPACE="default"
DEPLOY_TEST_WORKLOADS=false

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

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-test-workloads)
                DEPLOY_TEST_WORKLOADS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --with-test-workloads    Deploy test workloads for testing the pod limits checker"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                       Deploy only core resources (recommended)"
                echo "  $0 --with-test-workloads Deploy core resources and test workloads"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done
}

# Check if required commands exist
check_prerequisites() {
    print_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again."
        exit 1
    fi

    print_success "All prerequisites met"
}

# Detect cluster type
detect_cluster_type() {
    print_info "Detecting Kubernetes cluster type..."

    # Check if kubectl can connect
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Please ensure your kubeconfig is properly configured"
        exit 1
    fi

    # Get current context
    local context
    context=$(kubectl config current-context)

    # Detect cluster type based on context name
    if [[ "$context" == *"minikube"* ]]; then
        CLUSTER_TYPE="minikube"
    elif [[ "$context" == *"kind"* ]]; then
        CLUSTER_TYPE="kind"
    elif [[ "$context" == *"docker-desktop"* ]] || [[ "$context" == "docker-for-desktop" ]]; then
        CLUSTER_TYPE="docker-desktop"
    else
        CLUSTER_TYPE="remote"
    fi

    print_success "Detected cluster type: $CLUSTER_TYPE"
}

# Build Docker image
build_image() {
    print_info "Building Docker image..."

    if docker build -t "$IMAGE_NAME" . > /dev/null 2>&1; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        print_info "Running build with verbose output..."
        docker build -t "$IMAGE_NAME" .
        exit 1
    fi
}

# Load image into cluster
load_image() {
    case "$CLUSTER_TYPE" in
        minikube)
            print_info "Loading image into Minikube..."
            if minikube image load "$IMAGE_NAME" &> /dev/null; then
                print_success "Image loaded into Minikube"
            else
                print_error "Failed to load image into Minikube"
                exit 1
            fi
            ;;
        kind)
            print_info "Loading image into kind cluster..."
            local kind_cluster
            kind_cluster=$(kubectl config current-context | sed 's/kind-//')
            if kind load docker-image "$IMAGE_NAME" --name "$kind_cluster" &> /dev/null; then
                print_success "Image loaded into kind cluster"
            else
                print_error "Failed to load image into kind cluster"
                exit 1
            fi
            ;;
        docker-desktop)
            print_info "Using Docker Desktop - image is already available"
            ;;
        remote)
            print_warning "Remote cluster detected"
            print_warning "You need to push the image to a container registry"
            print_info "Example: docker tag $IMAGE_NAME <registry>/$IMAGE_NAME"
            print_info "         docker push <registry>/$IMAGE_NAME"
            print_info "Then update manifests/cronjob.yaml with the registry URL"
            print_error "Deployment aborted - manual registry setup required"
            exit 1
            ;;
    esac
}

# Verify image availability in cluster
verify_image() {
    case "$CLUSTER_TYPE" in
        minikube)
            print_info "Verifying image in Minikube..."
            if minikube image ls | grep -q "k8s-pod-limits-checker"; then
                print_success "Image verified in Minikube"
            else
                print_warning "Image not found in Minikube (this may be okay)"
            fi
            ;;
        *)
            print_info "Skipping image verification for $CLUSTER_TYPE"
            ;;
    esac
}

# Deploy Kubernetes manifests
deploy_manifests() {
    print_info "Deploying Kubernetes manifests..."

    if [ ! -d "manifests" ]; then
        print_error "manifests/ directory not found"
        exit 1
    fi

    # Deploy core resources (exclude test deployments)
    print_info "Deploying core resources..."
    local core_manifests=(
        "manifests/serviceaccount.yaml"
        "manifests/clusterrole.yaml"
        "manifests/clusterrolebinding.yaml"
        "manifests/configmap.yaml"
        "manifests/cronjob.yaml"
    )

    for manifest in "${core_manifests[@]}"; do
        if [ -f "$manifest" ]; then
            if ! kubectl apply -f "$manifest" &> /dev/null; then
                print_error "Failed to deploy $manifest"
                print_info "Running deployment with verbose output..."
                kubectl apply -f "$manifest"
                exit 1
            fi
        else
            print_warning "Manifest not found: $manifest"
        fi
    done

    print_success "Core manifests deployed successfully"

    # Deploy test workloads if requested
    if [ "$DEPLOY_TEST_WORKLOADS" = true ]; then
        print_info "Deploying test workloads..."

        local test_manifests=(
            "manifests/test-deployment-cpu-only.yaml"
            "manifests/test-deployment-memory-only.yaml"
            "manifests/test-deployment-no-limits.yaml"
            "manifests/test-deployment-all-limits.yaml"
        )

        for manifest in "${test_manifests[@]}"; do
            if [ -f "$manifest" ]; then
                if ! kubectl apply -f "$manifest" &> /dev/null; then
                    print_error "Failed to deploy $manifest"
                    print_info "Running deployment with verbose output..."
                    kubectl apply -f "$manifest"
                    exit 1
                fi
            else
                print_warning "Test manifest not found: $manifest"
            fi
        done

        print_success "Test workloads deployed successfully"
        print_info "Test namespaces created: no-cpu-limit, no-memory-limit, no-limits-global, all-limits"
    else
        print_info "Skipping test workloads (use --with-test-workloads to deploy them)"
    fi
}

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."

    # Check if CronJob exists
    if kubectl get cronjob pod-monitor &> /dev/null; then
        print_success "CronJob 'pod-monitor' is created"
    else
        print_error "CronJob 'pod-monitor' not found"
        exit 1
    fi

    # Check ServiceAccount
    if kubectl get serviceaccount pod-monitor &> /dev/null; then
        print_success "ServiceAccount 'pod-monitor' is created"
    else
        print_warning "ServiceAccount 'pod-monitor' not found"
    fi

    # Check ClusterRole
    if kubectl get clusterrole pod-monitor-role &> /dev/null; then
        print_success "ClusterRole 'pod-monitor-role' is created"
    else
        print_warning "ClusterRole 'pod-monitor-role' not found"
    fi

    # Show CronJob schedule
    local schedule
    schedule=$(kubectl get cronjob pod-monitor -o jsonpath='{.spec.schedule}')
    print_info "CronJob schedule: $schedule"

    print_success "Deployment verification completed"
}

# Show next steps
show_next_steps() {
    echo ""
    print_success "Deployment completed successfully!"
    echo ""
    print_info "Useful commands:"
    echo "  • View CronJob status:       kubectl get cronjob pod-monitor"
    echo "  • View jobs:                 kubectl get jobs -l app=pod-monitor"
    echo "  • View pods:                 kubectl get pods -l app=pod-monitor"
    echo "  • View logs:                 kubectl logs -l app=pod-monitor --tail=50"
    echo "  • Trigger manual run:        kubectl create job --from=cronjob/pod-monitor manual-run-1"
    echo "  • Edit configuration:        kubectl edit configmap pod-monitor-config"
    echo ""

    if [ "$DEPLOY_TEST_WORKLOADS" = true ]; then
        print_info "Test workload commands:"
        echo "  • View all test pods:        kubectl get pods --all-namespaces -l test=pod-limits-checker"
        echo "  • Check no-cpu-limit ns:     kubectl get pods -n no-cpu-limit"
        echo "  • Check no-memory-limit ns:  kubectl get pods -n no-memory-limit"
        echo "  • Check no-limits-global ns: kubectl get pods -n no-limits-global"
        echo "  • Check all-limits ns:       kubectl get pods -n all-limits"
        echo ""
    fi

    print_info "The CronJob will run automatically according to its schedule."
    print_info "To see results immediately, you can trigger a manual run or wait for the next scheduled execution."
    echo ""
}

# Main execution
main() {
    echo ""
    echo "======================================"
    echo "  K8s Pod Limits Checker Deployment  "
    echo "======================================"
    echo ""

    parse_arguments "$@"
    check_prerequisites
    detect_cluster_type
    build_image
    load_image
    verify_image
    deploy_manifests
    verify_deployment
    show_next_steps
}

# Run main function
main "$@"
