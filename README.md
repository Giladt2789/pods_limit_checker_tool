# Kubernetes Pod Limits Checker

A simple tool to identify Kubernetes containers across all namespaces that are missing CPU and/or memory resource limits.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start Guide](#quick-start-guide)
- [Getting Started](#getting-started)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Using a Container Registry](#using-a-container-registry)
- [Wrapper Scripts Reference](#wrapper-scripts-reference)
- [Testing and Verification](#testing-and-verification)
- [Pod Annotation Feature](#pod-annotation-feature)
- [Local Docker Usage Examples](#local-docker-usage-examples)
- [Output Format](#output-format)
- [Running as a Cron Job](#running-as-a-cron-job)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker installed on your system
- Access to a Kubernetes cluster (kubeconfig properly configured - wwas fully tested on minikube)
- For local testing: Minikube (optional)


## Possible approaches to address the problem: Continuous Monitoring Approaches

1. **Cronjob (Periodic Polling)**:
Runs your script at fixed intervals (e.g., every 5 minutes)
Simple to implement and debug
Trade-off: Has a detection gap between runs—a pod could exist for several minutes before being flagged
Good for: Non-critical monitoring where delayed detection is acceptable

2. **Controller/Operator (Event-Driven)**
A long-running Pod or Deployment that watches the Kubernetes API in real-time
Uses client libraries with watch mechanisms (like client-go, Python client, etc.)
Detects new pods immediately via API events
Good for: Immediate detection and enforcement

3. **Webhook (Admission Controller)**
Intercepts pod creation requests before they're created
Can prevent pods without limits from being admitted to the cluster
Most proactive approach—blocking instead of just monitoring
Good for: Enforcement rather than just detection

### Important note about solution choosing:
I've decided to go with a cronjob format, rather than an operator or a webhook due to simplicity, fast delivery and the proper understanding that there are better and more suitable solutions out there (paid and free).  

## Quick Start Guide

### One-Command Deployment (Recommended)

The easiest way to get started is using the automated wrapper scripts (given that there's a k8s cluster, minikube in my testing case):

**For Kubernetes Deployment (Production):**

```bash
# Deploy only core resources (recommended for production)
./deploy.sh
```

**For Testing with Test Workloads:**

```bash
# Deploy core resources + test workloads for verification
./deploy.sh --with-test-workloads
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
- ✓ Deploying Kubernetes manifests (core + optional test workloads)
- ✓ Verification and error handling

### Manual Quick Start

If you prefer manual control:

**For Local Testing with Docker:**

```bash
# 1. Clone the repository
git clone https://github.com/Giladt2789/pods_limit_checker_tool.git
cd pods_limit_checker_tool

# 2. Build the image
docker build -t k8s-pod-limits-checker:latest .

# Important note: I understand that it's not preferable to work with latest tag (mostly around security reasons, bugs being tested and evaluated etc.), and it's better to work specific version. Yet, for the purpose of this task - i've decided to work with latest and explain the reason here.

# 3. Prior to testing - create a dummy ./kube/config file (if not existing already):
mkdir -p ~/.kube && touch ~/.kube/config

# 4. Run once to test
docker run --rm -v ~/.kube/config:/root/.kube/config:ro k8s-pod-limits-checker
```

**For Kubernetes Deployment (Minikube/kind/Docker Desktop):**

```bash
# 1. Clone and build
git clone https://github.com/Giladt2789/pods_limit_checker_tool.git
cd pods_limit_checker_tool
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
git clone https://github.com/Giladt2789/pods_limit_checker_tool.git
cd pods_limit_checker_tool
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

Change `annotate: "false"` to `annotate: "true"`, save and exit. The change will take effect on the next scheduled CronJob run (no pod restart needed).

To trigger an immediate test:

```bash
kubectl create job --from=cronjob/pod-monitor test-annotate
```

See the [Pod Annotation Feature](#pod-annotation-feature) section for full details.

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
./deploy.sh [OPTIONS]
```

**Options:**

- `--with-test-workloads` - Deploy test workloads for testing the pod limits checker
- `--help`, `-h` - Show help message

**Examples:**

```bash
# Deploy only core resources (recommended for production)
./deploy.sh

# Deploy with test workloads for testing and verification
./deploy.sh --with-test-workloads
```

**What it does:**

1. Checks for required tools (docker, kubectl)
2. Detects cluster type (Minikube, kind, Docker Desktop, or remote)
3. Builds the Docker image
4. Loads the image into your cluster (if needed)
5. Deploys core Kubernetes manifests
6. Optionally deploys test workloads (with `--with-test-workloads`)
7. Verifies the deployment
8. Shows useful commands for monitoring

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

## Testing and Verification

### Test Workloads

Four test deployment manifests are included to help verify the pod limits checker works correctly:

1. **[test-deployment-cpu-only.yaml](manifests/test-deployment-cpu-only.yaml)** - Pod with only CPU limit (missing memory limit)
   - Namespace: `no-memory-limit`
   - Should be flagged with missing memory limit

2. **[test-deployment-memory-only.yaml](manifests/test-deployment-memory-only.yaml)** - Pod with only memory limit (missing CPU limit)
   - Namespace: `no-cpu-limit`
   - Should be flagged with missing CPU limit

3. **[test-deployment-no-limits.yaml](manifests/test-deployment-no-limits.yaml)** - Pod with no resource limits
   - Namespace: `no-limits-global`
   - Should be flagged with missing both CPU and memory limits

4. **[test-deployment-all-limits.yaml](manifests/test-deployment-all-limits.yaml)** - Pod with all limits (compliant)
   - Namespace: `all-limits`
   - Should NOT be flagged (has both CPU and memory limits)

### Deploying Test Workloads

**Using the automated script:**

```bash
./deploy.sh --with-test-workloads
```

**Manual deployment:**

```bash
kubectl apply -f manifests/test-deployment-cpu-only.yaml
kubectl apply -f manifests/test-deployment-memory-only.yaml
kubectl apply -f manifests/test-deployment-no-limits.yaml
kubectl apply -f manifests/test-deployment-all-limits.yaml
```

### Verifying Results

**1. Trigger a manual CronJob run:**

```bash
kubectl create job --from=cronjob/pod-monitor test-run-1
```

**2. Check the logs:**

```bash
kubectl logs -l app=pod-monitor --tail=100
```

**Expected output should include:**

```
NAMESPACE          POD_NAME                     CONTAINER_NAME    MISSING_CPU    MISSING_MEMORY
no-cpu-limit       test-memory-only-xxx         nginx             YES            NO
no-memory-limit    test-cpu-only-xxx            nginx             NO             YES
no-limits-global   test-no-limits-xxx           nginx             YES            YES
```

The `all-limits` namespace should NOT appear (since it's compliant).

**3. Check pod status in test namespaces:**

```bash
kubectl get pods -n no-cpu-limit
kubectl get pods -n no-memory-limit
kubectl get pods -n no-limits-global
kubectl get pods -n all-limits
```

**4. If annotations are enabled, check for warning annotations:**

```bash
# Check specific pod
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations}'

# Check all pods in a namespace
kubectl get pods -n no-cpu-limit -o custom-columns=NAME:.metadata.name,WARNINGS:.metadata.annotations.warning
```

### Cleaning Up Test Workloads

**Using the automated script:**

```bash
./cleanup.sh
```

This automatically removes test workloads and their namespaces if they exist.

**Manual cleanup:**

```bash
kubectl delete namespace no-cpu-limit
kubectl delete namespace no-memory-limit
kubectl delete namespace no-limits-global
kubectl delete namespace all-limits
```

## Pod Annotation Feature

The tool can automatically annotate pods that are missing resource limits. This is an **opt-in/opt-out** feature controlled via ConfigMap.

### Enabling Annotations

Edit the ConfigMap to enable annotations:

```bash
kubectl edit configmap pod-monitor-config
```

Change `annotate: "false"` to `annotate: "true"`:

```yaml
data:
  log-level: "INFO"
  output-type: "json"
  annotate: "true"    # Changed from "false" to "true"
```

Save and exit. The CronJob will use the new setting on its next scheduled run.

### Disabling Annotations

To disable annotations, edit the ConfigMap and change `annotate: "true"` to `annotate: "false"`:

```bash
kubectl edit configmap pod-monitor-config
# Change annotate to "false"
```

### Annotation Types

When enabled, pods are annotated based on what limits are missing:

- `warning: no-cpu-limit` - CPU limit is missing
- `warning: no-memory-limit` - Memory limit is missing
- `warning: no-limits` - Both CPU and memory limits are missing

### Viewing Pod Annotations

**View annotations for a specific pod:**

```bash
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 annotations:
```

**View annotations in table format:**

```bash
kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,WARNING:.metadata.annotations.warning
```

**Check if a pod has warning annotations:**

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations.warning}'
```

### Important Notes

- The annotation feature requires the ClusterRole to have `patch` permissions on pods (already configured in [clusterrole.yaml](manifests/clusterrole.yaml))
- Annotations are applied during each CronJob run when the feature is enabled
- Changing the ConfigMap setting takes effect on the next CronJob execution (no pod restart needed)
- This is a **ConfigMap-driven** feature - you should NOT edit the [cronjob.yaml](manifests/cronjob.yaml) to enable/disable annotations

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

### Annotations not working

If you've enabled annotations in the ConfigMap but pods are not being annotated:

**1. Verify the ConfigMap setting:**

```bash
kubectl get configmap pod-monitor-config -o yaml
```

Ensure `annotate: "true"` is set in the data section.

**2. Check ClusterRole has patch permissions:**

```bash
kubectl get clusterrole pod-monitor-role -o yaml
```

Ensure the role includes `patch` verb:

```yaml
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch", "patch"]
```

**3. Trigger a new CronJob run:**

ConfigMap changes take effect on the next scheduled run. To test immediately:

```bash
kubectl create job --from=cronjob/pod-monitor test-annotate-1
```

**4. Check the logs for annotation messages:**

```bash
kubectl logs -l app=pod-monitor --tail=50 | grep -i annotat
```

You should see messages like:
- `Annotated pod <pod-name> in namespace <namespace> with: no-cpu-limit`
- `Annotated pod <pod-name> in namespace <namespace> with: no-memory-limit`
- `Annotated pod <pod-name> in namespace <namespace> with: no-limits`

**5. Verify annotations were applied:**

```bash
kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,WARNING:.metadata.annotations.warning
```

**6. Check ServiceAccount permissions:**

```bash
kubectl auth can-i patch pods --as=system:serviceaccount:default:pod-monitor-sa --all-namespaces
```

Should return `yes`.

### Test workloads not being flagged

If test workloads are deployed but not appearing in the checker output:

**1. Verify pods are running:**

```bash
kubectl get pods --all-namespaces -l test=pod-limits-checker
```

**2. Check if the CronJob has run:**

```bash
kubectl get jobs -l app=pod-monitor
```

If no jobs exist or the latest job is old, trigger a manual run:

```bash
kubectl create job --from=cronjob/pod-monitor test-run-2
```

**3. Check the logs:**

```bash
kubectl logs -l app=pod-monitor --tail=100
```

**4. Verify the test deployments have the expected resource limits:**

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].resources.limits}'
```
