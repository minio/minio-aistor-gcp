.PHONY: help
help:
	@echo "Available targets:"
	@echo "  deps                 - Download Helm chart dependencies"
	@echo "  build                - Build the deployer image"
	@echo "  build-reporter       - Build the usage-reporter image"
	@echo "  build-all            - Build all images"
	@echo "  push                 - Push deployer image to GCR"
	@echo "  push-reporter        - Push usage-reporter image to GCR"
	@echo "  push-all             - Push all images to GCR"
	@echo "  release              - Build, push, and annotate all images (VERSION required)"
	@echo "  verify               - Verify the app package"
	@echo "  install              - Install the app using mpdev (requires LICENSE_KEY)"
	@echo "  uninstall            - Uninstall the app"
	@echo "  clean                - Clean up local resources"
	@echo "  lint                 - Lint the Helm chart"
	@echo "  template             - Test Helm template rendering"

# Configuration variables
REGISTRY ?= gcr.io/minio-inc-public
APP_NAME = minio-aistor
PRODUCT_ID = aistor
TAG ?= latest
VERSION ?= 1.0.0
MARKETPLACE_TOOLS_TAG ?= 0.12.10

# License (must be provided for installation)
LICENSE_KEY ?=

# Image names
DEPLOYER_IMAGE = $(REGISTRY)/$(PRODUCT_ID)/deployer:$(TAG)
REPORTER_IMAGE = $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(TAG)

# GCP Marketplace service annotation
SERVICE_ANNOTATION = services/$(PRODUCT_ID).endpoints.minio-inc-public.cloud.goog

.PHONY: deps
deps:
	@echo "Downloading Helm chart dependencies..."
	cd chart/$(APP_NAME) && helm repo add aistor https://helm.min.io/ 2>/dev/null || true && helm repo update
	cd chart/$(APP_NAME) && helm dependency update

.PHONY: build
build: deps
	@echo "Building deployer image..."
	docker build \
		--build-arg MARKETPLACE_TOOLS_TAG=$(MARKETPLACE_TOOLS_TAG) \
		--tag $(DEPLOYER_IMAGE) \
		-f deployer/Dockerfile \
		.

.PHONY: build-reporter
build-reporter:
	@echo "Building usage-reporter image..."
	docker build \
		--tag $(REPORTER_IMAGE) \
		-f images/usage-reporter/Dockerfile \
		images/usage-reporter/

.PHONY: build-all
build-all: build build-reporter

.PHONY: push
push:
	@echo "Pushing deployer image to $(DEPLOYER_IMAGE)..."
	docker push $(DEPLOYER_IMAGE)

.PHONY: push-reporter
push-reporter:
	@echo "Pushing usage-reporter image to $(REPORTER_IMAGE)..."
	docker push $(REPORTER_IMAGE)

.PHONY: push-all
push-all: push push-reporter

.PHONY: release
release:
	@echo "Building and releasing version $(VERSION)..."
	# Build deployer
	docker build \
		--build-arg MARKETPLACE_TOOLS_TAG=$(MARKETPLACE_TOOLS_TAG) \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION) \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:$(shell echo $(VERSION) | cut -d. -f1,2) \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:latest \
		-f deployer/Dockerfile \
		.
	# Build usage-reporter
	docker build \
		--tag $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(VERSION) \
		--tag $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(shell echo $(VERSION) | cut -d. -f1,2) \
		--tag $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:latest \
		-f images/usage-reporter/Dockerfile \
		images/usage-reporter/
	# Push all tags
	docker push $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION)
	docker push $(REGISTRY)/$(PRODUCT_ID)/deployer:$(shell echo $(VERSION) | cut -d. -f1,2)
	docker push $(REGISTRY)/$(PRODUCT_ID)/deployer:latest
	docker push $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(VERSION)
	docker push $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(shell echo $(VERSION) | cut -d. -f1,2)
	docker push $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:latest
	# Add OCI annotations for GCP Marketplace (deployer only)
	crane mutate $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION) \
		--annotation com.googleapis.cloudmarketplace.product.service.name="$(SERVICE_ANNOTATION)" \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION)
	crane mutate $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION) \
		--annotation com.googleapis.cloudmarketplace.product.service.name="$(SERVICE_ANNOTATION)" \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:$(shell echo $(VERSION) | cut -d. -f1,2)
	crane mutate $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION) \
		--annotation com.googleapis.cloudmarketplace.product.service.name="$(SERVICE_ANNOTATION)" \
		--tag $(REGISTRY)/$(PRODUCT_ID)/deployer:latest
	@echo "Release $(VERSION) complete!"
	@echo "Images:"
	@echo "  - $(REGISTRY)/$(PRODUCT_ID)/deployer:$(VERSION)"
	@echo "  - $(REGISTRY)/$(PRODUCT_ID)/usage-reporter:$(VERSION)"

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
		--parameters='{"name": "$(APP_NAME)", "namespace": "$(APP_NAME)", "aistor-operator.license": "$(LICENSE_KEY)", "reportingSecret": "gs://cloud-marketplace-tools/reporting_secrets/fake_reporting_secret.yaml", "objectstore.pools.0.servers": 1, "objectstore.pools.0.volumesPerServer": 4, "objectstore.pools.0.size": "10Gi"}'

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
	docker rmi $(REPORTER_IMAGE) || true
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
