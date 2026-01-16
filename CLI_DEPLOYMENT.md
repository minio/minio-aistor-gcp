# MinIO AIStor - Command Line Deployment Guide

This guide provides instructions for deploying MinIO AIStor on Google Kubernetes Engine (GKE) using command-line tools as an alternative to the Cloud Console UI.

This CLI deployment uses the GCP Marketplace deployer, which provides:
- ✅ Full GCP Console integration (visible in Kubernetes Engine → Applications)
- ✅ Usage tracking and billing integration
- ✅ Application CRD for centralized resource management
- ✅ Proper marketplace compliance

## Prerequisites

Before you begin, ensure you have:

1. **GKE Cluster**: A running GKE cluster with at least 4 nodes
   - Minimum node specs: 1 CPU, 2GB memory per node
   - Kubernetes version: 1.23 or later

2. **Required Tools**:
   - `gcloud` CLI - [Install](https://cloud.google.com/sdk/docs/install)
   - `kubectl` - [Install](https://kubernetes.io/docs/tasks/tools/)

3. **MinIO AIStor License**: A valid JWT license key (starts with 'eyJ')
   - Contact MinIO for a license: https://min.io/contact

4. **Permissions**: Your GCP user must have:
   - Kubernetes Engine Admin (`roles/container.admin`)
   - Service Account User (`roles/iam.serviceAccountUser`)

## Step 1: Set Up Your Environment

```bash
# Set your GCP project
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Set your cluster name and zone
export CLUSTER_NAME="your-gke-cluster"
export CLUSTER_ZONE="us-central1-a"

# Get cluster credentials
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$CLUSTER_ZONE

# Verify connection
kubectl cluster-info
```

## Step 2: Prepare Configuration

Create a configuration file with your deployment parameters:

```bash
# Create a namespace for MinIO AIStor
export NAMESPACE="minio-aistor"
export APP_INSTANCE_NAME="minio-aistor"

# Set your MinIO license (replace with your actual license)
export LICENSE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'

# Set root credentials (or use auto-generated password)
export MINIO_ACCESS_KEY="admin"
export MINIO_SECRET_KEY="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

# Storage configuration
export MINIO_SERVERS=4
export MINIO_VOLUMES_PER_SERVER=4
export MINIO_STORAGE_SIZE="10Gi"

# Note: Resource limits, service types, storage class, and other advanced
# settings use Helm chart defaults and are not configurable via GCP Marketplace
# schema. To customize these, deploy via Helm chart directly.
```

## Step 3: Create Namespace

```bash
kubectl create namespace "${NAMESPACE}"
```

## Step 4: Create Service Account

```bash
kubectl create serviceaccount "${APP_INSTANCE_NAME}-sa" \
  --namespace "${NAMESPACE}"
```

## Step 5: Apply RBAC Permissions

Create a file named `rbac.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${APP_INSTANCE_NAME}-role
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims", "services", "pods", "secrets", "configmaps", "serviceaccounts"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
- apiGroups: ["aistor.min.io"]
  resources: ["objectstores", "objectstores/status", "objectstores/finalizers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["rolebindings", "roles"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${APP_INSTANCE_NAME}-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${APP_INSTANCE_NAME}-role
subjects:
- kind: ServiceAccount
  name: ${APP_INSTANCE_NAME}-sa
  namespace: ${NAMESPACE}
EOF
```

Apply the RBAC configuration:

```bash
envsubst < rbac.yaml | kubectl apply -f -
```

## Step 6: Deploy Using Application CRD

Create a deployment manifest file named `application.yaml`:

```yaml
apiVersion: app.k8s.io/v1beta1
kind: Application
metadata:
  name: ${APP_INSTANCE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: minio-aistor
  annotations:
    kubernetes-engine.cloud.google.com/icon: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
    marketplace.cloud.google.com/deploy-info: '{"partner_id": "minio-inc-public", "product_id": "aistor"}'
spec:
  descriptor:
    type: "MinIO AIStor"
    version: "1.0.0"
    description: "High-Performance Object Storage for AI/ML Workloads"
    maintainers:
    - name: MinIO Inc
      url: https://min.io
    links:
    - description: User Guide
      url: https://docs.min.io/enterprise/aistor-object-store/
  selector:
    matchLabels:
      app.kubernetes.io/name: minio-aistor
  componentKinds:
  - group: apps/v1
    kind: StatefulSet
  - group: v1
    kind: Service
  - group: v1
    kind: Secret
  - group: v1
    kind: ConfigMap
```

## Step 7: Deploy Using kubectl and Marketplace Deployer

The easiest way to deploy via CLI is using the GCP Marketplace deployer image:

```bash
# Create a configuration secret
kubectl create secret generic ${APP_INSTANCE_NAME}-config \
  --namespace=${NAMESPACE} \
  --from-literal=license="${LICENSE_KEY}" \
  --from-literal=accessKey="${MINIO_ACCESS_KEY}" \
  --from-literal=secretKey="${MINIO_SECRET_KEY}"

# Create deployer job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${APP_INSTANCE_NAME}-deployer
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      serviceAccountName: ${APP_INSTANCE_NAME}-sa
      restartPolicy: OnFailure
      containers:
      - name: deployer
        image: gcr.io/minio-inc-public/aistor/deployer:1.0
        env:
        - name: NAME
          value: "${APP_INSTANCE_NAME}"
        - name: NAMESPACE
          value: "${NAMESPACE}"
        - name: LICENSE
          valueFrom:
            secretKeyRef:
              name: ${APP_INSTANCE_NAME}-config
              key: license
        - name: AISTOR_OBJECTSTORE_SECRETS_ACCESSKEY
          valueFrom:
            secretKeyRef:
              name: ${APP_INSTANCE_NAME}-config
              key: accessKey
        - name: AISTOR_OBJECTSTORE_SECRETS_SECRETKEY
          valueFrom:
            secretKeyRef:
              name: ${APP_INSTANCE_NAME}-config
              key: secretKey
        - name: AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_SERVERS
          value: "${MINIO_SERVERS}"
        - name: AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_VOLUMESPERSERVER
          value: "${MINIO_VOLUMES_PER_SERVER}"
        - name: AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_SIZE
          value: "${MINIO_STORAGE_SIZE}"
EOF
```

## Step 8: Monitor Deployment

```bash
# Watch the deployer job
kubectl get jobs -n ${NAMESPACE} -w

# View deployer logs
kubectl logs -n ${NAMESPACE} job/${APP_INSTANCE_NAME}-deployer -f

# Once complete, check all resources
kubectl get all -n ${NAMESPACE}

# Check operator pods
kubectl get pods -n ${NAMESPACE} -l app=aistor-objectstore-operator

# Check MinIO pods
kubectl get pods -n ${NAMESPACE} -l app=aistor-objectstore

# Check services
kubectl get svc -n ${NAMESPACE}
```

## Step 9: Get Access Information

### Retrieve MinIO Credentials

```bash
# Get credentials from config.env secret
kubectl get secret ${APP_INSTANCE_NAME}-env-config \
  -n ${NAMESPACE} \
  -o jsonpath='{.data.config\.env}' | base64 -d
# Output shows: export MINIO_ROOT_USER="..." and export MINIO_ROOT_PASSWORD="..."
```

### Get Service Endpoints

```bash
# List all services
kubectl get svc -n ${NAMESPACE}

# Get MinIO API endpoint (S3-compatible API on port 80)
kubectl get svc -n ${NAMESPACE} -l v1.min.io/tenant=${APP_INSTANCE_NAME}-store \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
echo

# Get MinIO Console endpoint (Web UI on port 9001)
kubectl get svc -n ${NAMESPACE} -l v1.min.io/console=${APP_INSTANCE_NAME}-store-console \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
echo
```

### Access MinIO Console

If using LoadBalancer service type:
```bash
# Get Console URL
CONSOLE_IP=$(kubectl get svc -n ${NAMESPACE} \
  -l v1.min.io/console=${APP_INSTANCE_NAME}-store-console \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "MinIO Console: http://${CONSOLE_IP}:9001"
```

If using ClusterIP, use port-forward:
```bash
kubectl port-forward -n ${NAMESPACE} \
  svc/$(kubectl get svc -n ${NAMESPACE} -l v1.min.io/console -o name | head -1 | cut -d/ -f2) \
  9001:9001
# Access at: http://localhost:9001
```

## Step 10: Verify Installation

### Test S3 API Access

Using MinIO Client (mc):

```bash
# Install MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Get API endpoint
API_ENDPOINT=$(kubectl get svc -n ${NAMESPACE} -l v1.min.io/tenant \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Configure using MC_HOST (simpler than alias)
export MC_HOST_aistor="http://${MINIO_ACCESS_KEY}:${MINIO_SECRET_KEY}@${API_ENDPOINT}"

# Test operations
mc mb aistor/test-bucket
echo "Hello MinIO AIStor" > test.txt
mc cp test.txt aistor/test-bucket/
mc ls aistor/test-bucket/
mc rm aistor/test-bucket/test.txt
mc rb aistor/test-bucket
```

### Check Cluster Health

```bash
# Check all pods are running
kubectl get pods -n ${NAMESPACE}

# Expected output: All pods in Running state
# - operator pods (adminjob-operator, object-store-operator)
# - MinIO pods with 4 containers each (minio, sidecar, ubbagent, usage-reporter)

# Check ObjectStore status
kubectl get objectstore -n ${NAMESPACE}

# Check MinIO pod logs
kubectl logs -n ${NAMESPACE} ${APP_INSTANCE_NAME}-store-pool-0-0 -c minio | tail -20

# Check usage-reporter logs (billing sidecar)
kubectl logs -n ${NAMESPACE} ${APP_INSTANCE_NAME}-store-pool-0-0 -c usage-reporter
```

## Configuration Reference

### Required Parameters

| Parameter | Environment Variable | Description | Example |
|-----------|---------------------|-------------|---------|
| `namespace` | `NAMESPACE` | Kubernetes namespace | `minio-aistor` |
| `name` | `APP_INSTANCE_NAME` | Application instance name | `minio-aistor` |
| `license` | `LICENSE` | MinIO AIStor license (JWT) | `eyJhbGc...` |

### Optional Parameters

| Parameter | Environment Variable | Default | Description |
|-----------|---------------------|---------|-------------|
| Servers | `AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_SERVERS` | `4` | Number of MinIO servers (4-32) |
| Volumes per server | `AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_VOLUMESPERSERVER` | `4` | Storage volumes per server (1-16) |
| Storage size | `AISTOR_OBJECTSTORE_OBJECTSTORE_POOLS_0_SIZE` | `10Gi` | Size per volume (e.g., 10Gi, 100Gi, 1Ti) |
| Access key | `AISTOR_OBJECTSTORE_SECRETS_ACCESSKEY` | `admin` | MinIO root username |

**Note**: Resource limits (CPU/memory), service types (LoadBalancer/ClusterIP), storage class, and other advanced settings use Helm chart defaults (2Gi memory, 1 CPU per server, LoadBalancer services). To customize these settings, deploy using the Helm chart directly instead of the GCP Marketplace deployer.

## Troubleshooting

### Deployer Job Fails

```bash
# Check deployer logs
kubectl logs -n ${NAMESPACE} job/${APP_INSTANCE_NAME}-deployer

# Common issues:
# - Invalid license format
# - Insufficient cluster resources
# - RBAC permissions missing
```

### Pods Not Starting

```bash
# Describe pod for events
kubectl describe pod -n ${NAMESPACE} ${APP_INSTANCE_NAME}-store-pool-0-0

# Common issues:
# - Insufficient CPU/memory
# - Storage provisioning failure
# - License validation failure
```

### Can't Access Services

```bash
# Check service status
kubectl get svc -n ${NAMESPACE}

# For LoadBalancer, wait for external IP
kubectl get svc -n ${NAMESPACE} -w

# Check firewall rules allow traffic on ports 9000 and 9001
```

## Cleanup

To remove MinIO AIStor:

```bash
# Delete the namespace (removes all resources)
kubectl delete namespace ${NAMESPACE}

# Remove cluster-scoped resources
kubectl delete clusterrole ${APP_INSTANCE_NAME}-role
kubectl delete clusterrolebinding ${APP_INSTANCE_NAME}-rolebinding
```

## Support

- **MinIO Documentation**: https://docs.min.io/enterprise/aistor-object-store/
- **MinIO Support**: https://min.io/support
- **GCP Marketplace Support**: https://cloud.google.com/marketplace/docs/partners

## Additional Resources

- [Complete Parameter Documentation](DEPLOYMENT_PARAMETERS.md)
- [GKE Cluster Requirements](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture)
- [MinIO Client (mc) Documentation](https://min.io/docs/minio/linux/reference/minio-mc.html)
