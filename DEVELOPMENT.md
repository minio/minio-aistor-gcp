# MinIO AIStor GCP Marketplace - Development Guide

This guide is for developers working on the MinIO AIStor GCP Marketplace package. For deployment instructions, see [README.md](README.md) or [CLI Deployment Guide](CLI_DEPLOYMENT.md).

## Project Structure

```
.
├── chart/                          # Helm chart for MinIO AIStor
│   └── minio-aistor/
│       ├── Chart.yaml             # Chart metadata
│       ├── values.yaml            # Default values
│       ├── charts/                # Subchart dependencies
│       │   ├── aistor-objectstore-operator-5.1.0.tgz
│       │   └── aistor-objectstore-1.0.9.tgz
│       └── templates/             # Kubernetes manifests
│           ├── application.yaml   # GCP Marketplace Application resource
│           ├── configmap.yaml     # Usage reporting configuration
│           └── _helpers.tpl       # Helm template helpers
├── deployer/
│   ├── Dockerfile                 # Deployer container image
│   ├── deploy.sh                  # Deployment script
│   └── deploy_with_tests.sh       # Deployment with validation
├── apptest/                       # Test configuration
│   └── deployer/
│       └── schema.yaml            # Test schema
├── schema.yaml                    # GCP Marketplace schema (user parameters)
├── Makefile                       # Build and deployment tasks
├── README.md                      # User-facing documentation
├── CLI_DEPLOYMENT.md              # CLI deployment guide
├── DEPLOYMENT_PARAMETERS.md       # Parameter reference
├── VERSIONING.md                  # Version strategy
└── DEVELOPMENT.md                 # This file
```

## Prerequisites

Before you begin development, ensure you have:

1. **GCP Project**: A GCP project with billing enabled
2. **Partner Access**: Enrolled in GCP Partner Advantage program
3. **Container Registry**: Access to Google Container Registry (GCR)
4. **Development Tools**:
   - Docker (for building images)
   - kubectl (for Kubernetes operations)
   - helm v3+ (for chart development)
   - gcloud CLI (for GCP operations)
   - mpdev (GCP Marketplace development tool)

## Setup Development Environment

### 1. Install mpdev Tool

The mpdev tool is essential for testing and verifying GCP Marketplace packages:

```bash
# Pull the marketplace tools image
docker pull gcr.io/cloud-marketplace-tools/k8s/dev

# Create an alias for mpdev
alias mpdev='docker run --rm -it \
  -v ~/.config/gcloud:/root/.config/gcloud \
  -v $(PWD):/data \
  gcr.io/cloud-marketplace-tools/k8s/dev'

# Verify installation
mpdev --version
```

### 2. Configure Your GCP Project

```bash
# Set your project
export PROJECT_ID="minio-inc-public"
gcloud config set project $PROJECT_ID

# Authenticate Docker with GCR
gcloud auth configure-docker

# Get credentials for your test cluster
gcloud container clusters get-credentials your-test-cluster --zone=us-central1-a
```

### 3. Verify Project Configuration

Ensure the following files have correct project information:

**Makefile**:
```makefile
REGISTRY ?= gcr.io/minio-inc-public
```

**schema.yaml** (Line ~10):
```yaml
marketplace.cloud.google.com/deploy-info: '{"partner_id": "minio-inc-public", "product_id": "minio-aistor-objectstore"}'
```

**chart/minio-aistor/templates/application.yaml** (Line ~9):
```yaml
marketplace.cloud.google.com/deploy-info: '{"partner_id": "minio-inc-public", "product_id": "minio-aistor-objectstore"}'
```

## Development Workflow

### Step 1: Make Changes

Edit Helm chart templates, schema, or deployer scripts:

```bash
# Common files to modify:
# - chart/minio-aistor/templates/*.yaml
# - chart/minio-aistor/values.yaml
# - schema.yaml
# - deployer/deploy.sh
```

### Step 2: Download Dependencies

If Chart.yaml dependencies changed:

```bash
# Download Helm chart dependencies
cd chart/minio-aistor
helm dependency update
cd ../..

# Or use Makefile
make deps
```

### Step 3: Lint and Validate

```bash
# Lint the Helm chart
make lint

# Test template rendering (dry-run)
make template

# Verify output in /tmp/rendered-templates.yaml
```

### Step 4: Build Deployer Image

```bash
# Build the deployer image
make build

# This creates:
# - gcr.io/minio-inc-public/minio-aistor/deployer:latest
```

### Step 5: Test Locally

```bash
# Option 1: Test with mpdev (requires MinIO license)
export LICENSE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
make install LICENSE_KEY="${LICENSE_KEY}"

# Option 2: Manual extraction and testing
docker create --name temp-deployer gcr.io/minio-inc-public/minio-aistor/deployer:latest
docker cp temp-deployer:/data/chart ./extracted-chart
docker rm temp-deployer

# Install extracted chart
helm install test ./extracted-chart \
  --namespace test-ns \
  --create-namespace \
  --set license="${LICENSE_KEY}"
```

### Step 6: Verify Package

```bash
# Run mpdev verify (checks schema, RBAC, Application CRD)
make verify

# Note: May fail in local Kind cluster due to GCR authentication
# This is expected - will work in real GKE clusters
```

### Step 7: Push to Registry

Once tests pass:

```bash
# Push deployer image to GCR
make push

# Tag with version
docker tag gcr.io/minio-inc-public/minio-aistor/deployer:latest \
  gcr.io/minio-inc-public/minio-aistor/deployer:1.0.0

docker push gcr.io/minio-inc-public/minio-aistor/deployer:1.0.0

# Tag with minor version (GCP Marketplace requirement)
docker tag gcr.io/minio-inc-public/minio-aistor/deployer:latest \
  gcr.io/minio-inc-public/minio-aistor/deployer:1.0

docker push gcr.io/minio-inc-public/minio-aistor/deployer:1.0
```

### Step 8: Cleanup

```bash
# Uninstall test deployment
make uninstall

# Clean local Docker images
make clean

# Remove test namespace
kubectl delete namespace test-ns
```

## Makefile Commands Reference

| Command | Description |
|---------|-------------|
| `make deps` | Download Helm chart dependencies |
| `make lint` | Lint Helm chart for errors |
| `make template` | Render templates to /tmp/rendered-templates.yaml |
| `make build` | Build deployer Docker image |
| `make push` | Push deployer image to GCR |
| `make verify` | Run mpdev verification |
| `make install` | Install using mpdev (requires LICENSE_KEY) |
| `make uninstall` | Uninstall test deployment |
| `make clean` | Remove local Docker images |
| `make check-operator` | Check operator pod status |
| `make check-objectstore` | Check objectstore pod status |
| `make get-credentials` | Retrieve MinIO credentials |
| `make port-forward-console` | Port-forward to MinIO Console (9001) |
| `make port-forward-api` | Port-forward to MinIO API (9000) |

## Testing Guidelines

### Unit Testing (Chart Validation)

```bash
# Validate YAML syntax
make lint

# Test with different parameter combinations
helm template test ./chart/minio-aistor \
  --set license="test-license" \
  --set aistor-objectstore.objectStore.pools[0].servers=4 \
  --dry-run
```

### Integration Testing (Live Deployment)

```bash
# 1. Deploy to test cluster
make install LICENSE_KEY="${LICENSE_KEY}"

# 2. Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=aistor-objectstore-operator -n test --timeout=300s
kubectl wait --for=condition=ready pod -l app=aistor-objectstore -n test --timeout=600s

# 3. Verify MinIO health
kubectl get pods -n test

# 4. Test S3 operations
mc alias set test http://localhost:9000 admin <password>
mc mb test/test-bucket
echo "test" > test.txt
mc cp test.txt test/test-bucket/
mc ls test/test-bucket/

# 5. Cleanup
make uninstall
```

### Verification Testing (mpdev)

```bash
# Automated verification (may fail locally due to auth)
make verify

# Check verification logs
cat /tmp/mpdev-verify.log
```

## Updating for New Versions

### Version Bump Checklist

1. Update `chart/minio-aistor/Chart.yaml`:
   ```yaml
   version: 1.1.0  # Update version
   appVersion: "1.1.0"
   ```

2. Update `schema.yaml`:
   ```yaml
   publishedVersion: '1.1.0'
   ```

3. Update version documentation as needed

4. Build and tag:
   ```bash
   make build
   docker tag gcr.io/minio-inc-public/minio-aistor/deployer:latest \
     gcr.io/minio-inc-public/minio-aistor/deployer:1.1
   docker tag gcr.io/minio-inc-public/minio-aistor/deployer:latest \
     gcr.io/minio-inc-public/minio-aistor/deployer:1.1.0
   docker push gcr.io/minio-inc-public/minio-aistor/deployer:1.1
   docker push gcr.io/minio-inc-public/minio-aistor/deployer:1.1.0
   ```

5. Update in Partner Hub:
   - Navigate to product listing
   - Click "Add Version"
   - Specify deployer image: `gcr.io/minio-inc-public/minio-aistor/deployer:1.1`
   - Add release notes
   - Submit for review

## Updating Subchart Dependencies

To update the MinIO AIStor operator or objectstore versions:

1. **Update Chart.yaml dependencies**:
   ```yaml
   dependencies:
   - name: aistor-objectstore-operator
     version: 5.2.0  # New version
     repository: https://charts.min.io/enterprise/aistor
   - name: aistor-objectstore
     version: 1.0.10  # New version
     repository: https://charts.min.io/enterprise/aistor
   ```

2. **Download new dependencies**:
   ```bash
   cd chart/minio-aistor
   helm dependency update
   cd ../..
   ```

3. **Test with new versions**:
   ```bash
   make lint
   make template
   make build
   make install LICENSE_KEY="${LICENSE_KEY}"
   ```

4. **Update documentation** to reflect new versions

## Troubleshooting Development Issues

### Issue: mpdev verify fails with ImagePullBackOff

**Cause**: Local Kind/minikube clusters can't authenticate with GCR

**Solution**:
- Expected behavior for local testing
- Load image into Kind: `kind load docker-image <image>:tag`
- Or test in real GKE cluster with proper GCR access

### Issue: Helm lint errors

**Cause**: Template syntax errors or missing values

**Solution**:
```bash
# Check specific template
helm template test ./chart/minio-aistor --debug

# Validate with test values
helm lint ./chart/minio-aistor --values test-values.yaml
```

### Issue: Deployment fails with license error

**Cause**: Invalid or expired MinIO license

**Solution**:
- Verify license format (should start with 'eyJ')
- Check license expiration: Decode JWT at jwt.io
- Request new test license from MinIO

### Issue: Pods stuck in Pending

**Cause**: Insufficient cluster resources

**Solution**:
```bash
# Check node resources
kubectl top nodes

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Scale down if testing:
--set aistor-objectstore.objectStore.pools[0].servers=1
--set aistor-objectstore.objectStore.pools[0].volumesPerServer=1
```

## GCP Marketplace Requirements

### 2025 Compliance Requirements

Starting January 20, 2025, all images must include service name annotation:

**deployer/Dockerfile**:
```dockerfile
LABEL com.google.marketplace.service="minio-aistor"
```

### Image Tagging Requirements

- **Must have semantic minor version**: `1.0`, `2.1`, etc.
- **Optional patch version**: `1.0.0`, `2.1.3`
- **Do NOT use**: `latest` for production

### Schema Validation Requirements

- All required parameters must have validation
- Proper RBAC permissions defined
- Application CRD properly configured
- Usage reporting configured (ConfigMap)

### Testing Requirements Before Submission

- [ ] `make lint` passes with no errors
- [ ] `make template` renders successfully
- [ ] `make verify` passes (or known limitations documented)
- [ ] Live deployment test completed
- [ ] S3 operations verified
- [ ] CLI deployment instructions tested
- [ ] All documentation up to date

## Best Practices

1. **Always test locally before pushing**
   - Run `make lint` and `make template`
   - Test in local cluster when possible

2. **Use semantic versioning**
   - Follow MAJOR.MINOR.PATCH format
   - See [VERSIONING.md](VERSIONING.md)

3. **Document all changes**
   - Update relevant .md files
   - Add comments to complex templates

4. **Keep dependencies updated**
   - Regularly check for MinIO chart updates
   - Test compatibility before updating

5. **Test with minimal resources**
   - Use small configurations for quick testing
   - Test production configs before release

## Support and Resources

### Documentation
- [GCP Marketplace Kubernetes Docs](https://cloud.google.com/marketplace/docs/partners/kubernetes)
- [Example Apps Repository](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-example)
- [Marketplace Tools](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools)

### MinIO Resources
- [MinIO AIStor Documentation](https://docs.min.io/enterprise/aistor-object-store/)
- [MinIO Helm Charts](https://github.com/minio/aistor-helm-charts)
- [MinIO Support](https://min.io/support)

### GCP Support
- [Partner Hub](https://console.cloud.google.com/partner)
- [Partner Support Desk](https://support.google.com/cloud)
- Include "Marketplace" in ticket description for faster routing

## Contributing

For issues or improvements:
1. Create an issue describing the problem/enhancement
2. Make changes in a feature branch
3. Test thoroughly using this guide
4. Submit pull request with:
   - Description of changes
   - Testing performed
   - Documentation updates

## License

This packaging is provided for deploying MinIO AIStor through GCP Marketplace. Refer to MinIO's licensing terms for the MinIO AIStor product itself.
