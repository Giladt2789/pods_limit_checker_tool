# Kubernetes Pod Limits Checker

A simple tool to identify Kubernetes containers across all namespaces that are missing CPU and/or memory resource limits.

## Prerequisites

- Docker installed on your system
- Access to a Kubernetes cluster (kubeconfig properly configured)
- For local testing: Minikube (optional)

## Quick Start Guide

### One-Command Deployment (Recommended)

The easiest way to get started is using the automated wrapper scripts:

**For Kubernetes Deployment (Minikube/kind/Docker Desktop):**

```bash
./deploy.sh
```

**For Local Testing (One-time execution):**

```bash
./run-local.sh
```

**To Remove Everything:**

```bash
./cleanup.sh
```

These scripts handle everything automatically including:

- ✓ Checking prerequisites
- ✓ Building Docker images
- ✓ Detecting cluster type (Minikube/kind/Docker Desktop)
- ✓ Loading images into the cluster
- ✓ Deploying Kubernetes manifests
- ✓ Verification and error handling

### Manual Quick Start

If you prefer manual control:

**For Local Testing with Docker:**

```bash
# 1. Clone the repository
git clone <repository-url>
cd k8s-resources-limits-watcher

# 2. Build the image
docker build -t k8s-pod-limits-checker:latest .

# 3. Run once to test
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker
```

**For Kubernetes Deployment (Minikube/kind/Docker Desktop):**

```bash
# 1. Clone and build
git clone <repository-url>
cd k8s-resources-limits-watcher
docker build -t k8s-pod-limits-checker:latest .

# 2. Load image into cluster (Minikube example)
minikube image load k8s-pod-limits-checker:latest

# 3. Deploy
kubectl apply -f manifests/

# 4. Verify
kubectl get cronjob pod-monitor
kubectl logs -l app=pod-monitor --tail=50
```

See detailed instructions below for your specific environment.

## Getting Started

### Step 1: Set Up a Kubernetes Cluster (Optional)

If you don't have a Kubernetes cluster, you can set up a local Minikube cluster:

#### Install Minikube

**On macOS (using Homebrew):**

First, install Homebrew if you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install Minikube:

```bash
brew install minikube
```

**On Linux:**

Download and install Minikube:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

#### Start the Cluster

```bash
minikube start
```

#### Enable metrics-server and Dashboard (Optional)

```bash
minikube addons enable metrics-server && minikube dashboard
```

### Step 2: Clone the Repository

```bash
git clone <repository-url>
cd k8s-resources-limits-watcher
```

### Step 3: Build the Docker Image

```bash
docker build -t k8s-pod-limits-checker:latest .
```

### Step 4: Run the Container

The container needs access to your kubeconfig file to connect to your cluster:

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker
```

That's it! The Docker image includes Python 3.13, all dependencies, and the script itself.

## Kubernetes Deployment

To run this tool as a scheduled CronJob in your Kubernetes cluster:

### Step 1: Build the Docker Image

Build the Docker image locally:

```bash
docker build -t k8s-pod-limits-checker:latest .
```

### Step 2: Load the Image into Your Cluster

**For Minikube:**

```bash
minikube image load k8s-pod-limits-checker:latest
```

**For kind (Kubernetes in Docker):**

```bash
kind load docker-image k8s-pod-limits-checker:latest
```

**For Docker Desktop Kubernetes:**

No additional step needed - Docker Desktop Kubernetes uses the local Docker daemon, so the image is already available.

**For remote/production clusters:**

You need to push the image to a container registry. See the [Using a Container Registry](#using-a-container-registry) section below.

### Step 3: Deploy the Manifests

Deploy all Kubernetes resources:

```bash
kubectl apply -f manifests/
```

This will create:
- **ServiceAccount** ([serviceaccount.yaml](manifests/serviceaccount.yaml)) - Identity for the pod
- **ClusterRole** ([clusterrole.yaml](manifests/clusterrole.yaml)) - Permissions to list/patch pods across all namespaces
- **ClusterRoleBinding** ([clusterrolebinding.yaml](manifests/clusterrolebinding.yaml)) - Binds the role to the service account
- **ConfigMap** ([configmap.yaml](manifests/configmap.yaml)) - Configuration settings
- **CronJob** ([cronjob.yaml](manifests/cronjob.yaml)) - Scheduled job that runs every 5 minutes

The CronJob is pre-configured with:
- Image: `k8s-pod-limits-checker:latest`
- ImagePullPolicy: `IfNotPresent` (uses locally loaded image)
- Schedule: Every 5 minutes
- Resource limits: 128Mi memory, 200m CPU

### Step 4: Configure the CronJob (Optional)

Edit [manifests/configmap.yaml](manifests/configmap.yaml) to customize settings:

```yaml
data:
  log-level: "INFO"          # DEBUG, INFO, WARNING, ERROR
  output-type: "json"        # table, json, csv
  annotate: "false"          # Set to "true" to enable automatic pod annotations
```

To change the schedule, edit [manifests/cronjob.yaml](manifests/cronjob.yaml#L7):

```yaml
schedule: "*/5 * * * *"  # Runs every 5 minutes (cron format)
```

Common schedule examples:
- `"0 * * * *"` - Every hour at minute 0
- `"0 9 * * *"` - Daily at 9:00 AM
- `"0 9 * * 1"` - Every Monday at 9:00 AM
- `"*/30 * * * *"` - Every 30 minutes

Apply the changes:

```bash
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/cronjob.yaml
```

### Verify Deployment

Check the CronJob status:

```bash
kubectl get cronjob pod-monitor
kubectl get jobs -l app=pod-monitor
kubectl get pods -l app=pod-monitor
```

View logs from the most recent job:

```bash
kubectl logs -l app=pod-monitor --tail=50
```

### Enable Pod Annotations

To enable automatic annotation of pods with missing limits, update the ConfigMap:

```bash
kubectl edit configmap pod-monitor-config
```

Change `annotate: "false"` to `annotate: "true"`, then wait for the next scheduled run.

## Using a Container Registry

For production or remote Kubernetes clusters, you need to push the image to a container registry:

### Step 1: Build and Tag with Registry Prefix

```bash
# Build with your registry prefix
docker build -t <your-registry>/k8s-pod-limits-checker:latest .

# Examples:
docker build -t docker.io/myusername/k8s-pod-limits-checker:latest .
docker build -t gcr.io/myproject/k8s-pod-limits-checker:latest .
docker build -t myregistry.azurecr.io/k8s-pod-limits-checker:latest .
```

### Step 2: Push to Registry

```bash
docker push <your-registry>/k8s-pod-limits-checker:latest
```

### Step 3: Update CronJob Manifest

Edit [manifests/cronjob.yaml](manifests/cronjob.yaml#L18) and update the image reference:

**Change from:**
```yaml
image: k8s-pod-limits-checker:latest
imagePullPolicy: IfNotPresent
```

**To:**
```yaml
image: <your-registry>/k8s-pod-limits-checker:latest
imagePullPolicy: Always
```

### Step 4: Deploy

```bash
kubectl apply -f manifests/cronjob.yaml
```

## Wrapper Scripts Reference

Three automated scripts are provided for easy deployment and management:

### deploy.sh - Automated Kubernetes Deployment

Handles the complete deployment process automatically:

```bash
./deploy.sh
```

**What it does:**

1. Checks for required tools (docker, kubectl)
2. Detects cluster type (Minikube, kind, Docker Desktop, or remote)
3. Builds the Docker image
4. Loads the image into your cluster (if needed)
5. Deploys all Kubernetes manifests
6. Verifies the deployment
7. Shows useful commands for monitoring

**Supported cluster types:**

- **Minikube**: Automatically loads image using `minikube image load`
- **kind**: Automatically loads image using `kind load docker-image`
- **Docker Desktop**: Image is immediately available (no loading needed)
- **Remote clusters**: Provides instructions for pushing to a registry

**Exit codes:**

- `0`: Success
- `1`: Error occurred (with detailed error message)

### run-local.sh - Local Docker Execution

Runs the checker once locally using Docker (useful for testing):

```bash
./run-local.sh [OPTIONS]
```

**Examples:**

```bash
# Run with default settings
./run-local.sh

# Check specific namespace with JSON output
./run-local.sh --namespace production --output json

# Annotate pods with warnings
./run-local.sh --annotate

# Debug mode
./run-local.sh --log-level DEBUG
```

**What it does:**

1. Checks prerequisites (docker, kubectl, cluster connectivity)
2. Builds the Docker image
3. Runs the container with your kubeconfig mounted
4. Passes through any command-line arguments

**Supported options:**

- `--output FORMAT`: table, json, csv
- `--namespace NAME` or `-n NAME`: Check specific namespace
- `--log-level LEVEL`: DEBUG, INFO, WARNING, ERROR
- `--annotate`: Add warning annotations to pods
- `--help`: Show usage information

### cleanup.sh - Remove All Resources

Removes all deployed Kubernetes resources:

```bash
./cleanup.sh [--remove-image]
```

**What it does:**

1. Deletes all resources defined in manifests/ directory
2. Optionally removes the image from the cluster (with `--remove-image` flag)

**Examples:**

```bash
# Remove only Kubernetes resources
./cleanup.sh

# Remove resources and cluster image
./cleanup.sh --remove-image
```

**Note:** The local Docker image is not removed by default. To remove it manually:

```bash
docker rmi k8s-pod-limits-checker:latest
```

## Local Docker Usage Examples

### Basic Usage

**Default output (human-readable table):**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker
```

**JSON output (for parsing/piping):**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --output json
```

**CSV output (for spreadsheets):**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --output csv
```

### Advanced Options

**Check specific namespace:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --namespace kube-system
```

Or using the short flag:

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker -n production
```

**Enable debug logging:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --log-level DEBUG
```

**Automatically annotate pods with warnings:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --annotate
```

This will add annotations to pods based on missing limits:

- `warning: no-cpu-limit` - CPU limit is missing
- `warning: no-memory-limit` - Memory limit is missing
- `warning: no-limits` - Both CPU and memory limits are missing

### Combining Options

**Check specific namespace with JSON output:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --namespace production --output json
```

**Annotate pods in specific namespace with JSON output:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --namespace production --annotate --output json
```

**Debug mode with JSON output:**

```bash
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --output json --log-level DEBUG
```

## Output Format

The script checks each container and reports those missing limits. Output includes:
- **NAMESPACE** - Kubernetes namespace
- **POD_NAME** - Name of the pod
- **CONTAINER_NAME** - Name of the container
- **MISSING_CPU** - YES if CPU limit is not set
- **MISSING_MEMORY** - YES if memory limit is not set

### Example Table Output:
```
+-----------+----------+-----------+------------+----------------+
| NAMESPACE | POD NAME | CONTAINER | MISSING CPU| MISSING MEMORY |
+-----------+----------+-----------+------------+----------------+
| default   | web-app  | app       | YES        | NO             |
| default   | web-app  | sidecar   | NO         | YES            |
| kube-sys  | coredns  | coredns   | YES        | YES            |
+-----------+----------+-----------+------------+----------------+
```

## Running as a Cron Job

Add to your crontab to run daily at 9 AM:

```bash
0 9 * * * docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker --output json >> /var/log/k8s_checker.log 2>&1
```

## Logs

Logs are stored in:
- Console output (stdout)
- `~/.k8s_pod_checker/pod_checker.log` (file for background runs)

## Troubleshooting

### CronJob pods fail with "ImagePullBackOff" or "ErrImagePull"

This means Kubernetes cannot find the image. Solutions:

**For Minikube:**
```bash
# Verify the image exists locally
docker images | grep k8s-pod-limits-checker

# Load the image into Minikube
minikube image load k8s-pod-limits-checker:latest

# Verify the image is in Minikube
minikube image ls | grep k8s-pod-limits-checker
```

**For kind:**
```bash
# Load the image into kind
kind load docker-image k8s-pod-limits-checker:latest
```

**For remote clusters:**
- You must push the image to a container registry (see [Using a Container Registry](#using-a-container-registry))
- Ensure the CronJob manifest uses the correct registry URL
- Verify your cluster has pull access to the registry (may need imagePullSecrets)

### CronJob runs but pods fail with permission errors

Check the logs:
```bash
kubectl logs -l app=pod-monitor --tail=50
```

If you see "Forbidden" errors, verify the RBAC permissions:
```bash
kubectl get clusterrole pod-monitor-role -o yaml
kubectl get clusterrolebinding pod-monitor-binding -o yaml
```

Ensure the ClusterRole includes these verbs:
- `get`, `list`, `watch` - for reading pods
- `patch` - for the `--annotate` feature

### "Failed to connect to Kubernetes cluster" (Local Docker)

- Ensure your kubeconfig is properly configured at `~/.kube/config`
- Run `kubectl get pods` to verify connectivity
- Verify the volume mount is correct in the Docker command

### "Permission denied" or "Cannot read kubeconfig" (Local Docker)

- Ensure your kubeconfig has proper permissions
- Check that the kubeconfig path in the volume mount is correct
- Verify your user has RBAC permissions to list pods across namespaces in the cluster

### Docker build fails

- Ensure you have a stable internet connection for downloading dependencies
- Try building with `docker build --no-cache -t k8s-pod-limits-checker .`

### Image exists but CronJob still pulls from registry

Check the `imagePullPolicy` in [manifests/cronjob.yaml](manifests/cronjob.yaml#L19):
- For local images: Use `imagePullPolicy: IfNotPresent` or `Never`
- For registry images: Use `imagePullPolicy: Always`
