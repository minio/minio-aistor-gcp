ARG MARKETPLACE_TOOLS_TAG

FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm:$MARKETPLACE_TOOLS_TAG

# Package and copy chart
# Create a wrapper directory called 'chart' so extraction works correctly
COPY chart/minio-aistor /tmp/build/chart
RUN cd /tmp/build && \
    tar czf /data/chart/minio-aistor.tar.gz chart && \
    rm -rf /tmp/build

# Copy schema
COPY schema.yaml /data/

# Copy custom deploy scripts
COPY deployer/deploy.sh /bin/deploy.sh
COPY deployer/deploy_with_tests.sh /bin/deploy_with_tests.sh
RUN chmod +x /bin/deploy.sh /bin/deploy_with_tests.sh

# Add required annotations for 2025 requirements
# Full service endpoint format: services/<product_id>.endpoints.<project_id>.cloud.goog
LABEL com.googleapis.cloudmarketplace.product.service.name="services/minio-aistor-objectstore.endpoints.minio-inc-public.cloud.goog"
