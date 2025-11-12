.PHONY: help
help:
	@echo "Available targets:"
	@echo "  deps            - Download Helm chart dependencies"
	@echo "  build           - Build the deployer image"
	@echo "  push            - Push images to GCR"
	@echo "  verify          - Verify the app package"
	@echo "  install         - Install the app using mpdev (requires LICENSE_KEY)"
	@echo "  uninstall       - Uninstall the app"
	@echo "  clean           - Clean up local resources"
	@echo "  lint            - Lint the Helm chart"
	@echo "  template        - Test Helm template rendering"

# Configuration variables
REGISTRY ?= gcr.io/minio-inc-public
APP_NAME = minio-aistor
TAG ?= latest
MARKETPLACE_TOOLS_TAG ?= 0.12.10

# License (must be provided for installation)
LICENSE_KEY ?=

# Image names
DEPLOYER_IMAGE = $(REGISTRY)/$(APP_NAME)/deployer:$(TAG)

.PHONY: deps
deps:
	@echo "Downloading Helm chart dependencies..."
	cd chart/$(APP_NAME) && helm repo add aistor https://helm.min.io/ && helm repo update
	cd chart/$(APP_NAME) && helm dependency update

.PHONY: build
build: deps
	@echo "Building deployer image..."
	docker build \
		--build-arg MARKETPLACE_TOOLS_TAG=$(MARKETPLACE_TOOLS_TAG) \
		--tag $(DEPLOYER_IMAGE) \
		-f deployer/Dockerfile \
		.

.PHONY: push
push:
	@echo "Pushing deployer image to $(DEPLOYER_IMAGE)..."
	docker push $(DEPLOYER_IMAGE)

.PHONY: verify
verify: deps
	@echo "Verifying app package with mpdev..."
	mpdev verify \
		--deployer=$(DEPLOYER_IMAGE)

.PHONY: install
install:
	@if [ -z "$(LICENSE_KEY)" ]; then \
		echo "ERROR: LICENSE_KEY is required. Usage: make install LICENSE_KEY='your-license-key'"; \
		exit 1; \
	fi
	@echo "Installing MinIO AIStor with operator..."
	mpdev install \
		--deployer=$(DEPLOYER_IMAGE) \
		--parameters='{"name": "$(APP_NAME)", "namespace": "$(APP_NAME)", "license": "$(LICENSE_KEY)", "aistor-objectstore.objectStore.pools[0].servers": 4, "aistor-objectstore.objectStore.pools[0].size": "10Gi"}'

.PHONY: uninstall
uninstall:
	@echo "Uninstalling MinIO AIStor..."
	kubectl delete application $(APP_NAME) -n $(APP_NAME) --ignore-not-found
	kubectl delete objectstore --all -n $(APP_NAME) --ignore-not-found
	kubectl delete namespace $(APP_NAME) --ignore-not-found

.PHONY: test
test:
	@echo "Running tests..."
	# Add your test commands here

.PHONY: clean
clean:
	@echo "Cleaning up..."
	docker rmi $(DEPLOYER_IMAGE) || true
	cd chart/$(APP_NAME) && rm -rf charts/*.tgz charts Chart.lock

.PHONY: setup-mpdev
setup-mpdev:
	@echo "Installing mpdev tool..."
	@echo "Run: docker pull gcr.io/cloud-marketplace-tools/k8s/dev"
	@echo "Then create alias: alias mpdev='docker run --rm -it -v ~/.config/gcloud:/root/.config/gcloud -v $(PWD):/data gcr.io/cloud-marketplace-tools/k8s/dev'"

.PHONY: lint
lint: deps
	@echo "Linting Helm chart..."
	cd chart/$(APP_NAME) && helm lint .

.PHONY: template
template: deps
	@echo "Testing Helm template rendering..."
	cd chart/$(APP_NAME) && helm template test-release . \
		--set license="test-license-key" \
		--set aistor-objectstore.secrets.secretKey="test-secret-key"

.PHONY: check-operator
check-operator:
	@echo "Checking operator status..."
	kubectl get pods -n $(APP_NAME) -l app.kubernetes.io/name=aistor-objectstore-operator

.PHONY: check-objectstore
check-objectstore:
	@echo "Checking object store status..."
	kubectl get objectstore -n $(APP_NAME)
	kubectl get pods -n $(APP_NAME) -l app=minio-aistor-store

.PHONY: get-credentials
get-credentials:
	@echo "Getting MinIO credentials..."
	@echo "Access Key:"
	@kubectl get secret minio-aistor-env-config -n $(APP_NAME) -o jsonpath='{.data.config\.env}' | base64 -d | grep MINIO_ROOT_USER || echo "Secret not found yet"
	@echo ""
	@echo "Secret Key:"
	@kubectl get secret minio-aistor-env-config -n $(APP_NAME) -o jsonpath='{.data.config\.env}' | base64 -d | grep MINIO_ROOT_PASSWORD || echo "Secret not found yet"

.PHONY: port-forward-console
port-forward-console:
	@echo "Port-forwarding to MinIO Console (http://localhost:9001)..."
	kubectl port-forward -n $(APP_NAME) svc/$$(kubectl get svc -n $(APP_NAME) -l v1.min.io/console=minio-aistor-store -o name | head -1) 9001:9001

.PHONY: port-forward-api
port-forward-api:
	@echo "Port-forwarding to MinIO API (http://localhost:9000)..."
	kubectl port-forward -n $(APP_NAME) svc/$$(kubectl get svc -n $(APP_NAME) -l v1.min.io/tenant=minio-aistor-store -o name | head -1) 9000:9000
