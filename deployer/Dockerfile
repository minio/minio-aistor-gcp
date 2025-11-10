ARG MARKETPLACE_TOOLS_TAG

FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm:$MARKETPLACE_TOOLS_TAG

# Copy chart and schema
COPY chart/minio-aistor /data/chart
COPY schema.yaml /data/

# Add required annotations for 2025 requirements
LABEL com.google.marketplace.service="minio-aistor"
