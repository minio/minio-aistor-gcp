# MinIO AIStor on GCP Marketplace

MinIO AIStor delivers unmatched enterprise performance, scale, agility and economics for AI data, agentic computing, and analytics.

## Overview

AIStor extends the most sophisticated object store on the market. It is designed for the exascale data infrastructure challenges presented by modern AI workloads. AIStor provides new features, along with performance and scalability improvements, to enable enterprises to store all AI data in one infrastructure.

Deploy on Google Kubernetes Engine (GKE) through GCP Marketplace with one click.

## Quick Start

### Deploy via Cloud Console (Recommended)

1. Visit [MinIO AIStor on GCP Marketplace](https://console.cloud.google.com/marketplace)
2. Click **"Configure"** and fill in parameters
3. Click **"Deploy"**
4. Wait 5-10 minutes for deployment to complete

### Deploy via Command Line

See [CLI Deployment Guide](CLI_DEPLOYMENT.md) for complete instructions.

```bash
# Quick example
kubectl create job deployer \
  --image=gcr.io/minio-inc-public/minio-aistor/deployer:1.0 \
  --namespace=minio-aistor
```

## What You Need

- **GKE Cluster** - Kubernetes 1.23+ with 4+ nodes (can be created during deployment)
- **MinIO AIStor License** - JWT format, [contact MinIO](https://min.io/pricing) to obtain

## After Deployment

Get your credentials and access the console:

```bash
# Get credentials
kubectl get secret minio-aistor-env-config -n minio-aistor \
  -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d

kubectl get secret minio-aistor-env-config -n minio-aistor \
  -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d

# Get Console URL
kubectl get svc minio-aistor-console -n minio-aistor \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Access at: http://<IP>:9001
```

## Configuration

MinIO AIStor can be customized during deployment. Default configuration:
- 4 servers with 4 volumes each (10Gi per volume)
- 2Gi RAM, 1 CPU per server
- LoadBalancer services for API and Console

📖 **See [DEPLOYMENT_PARAMETERS.md](DEPLOYMENT_PARAMETERS.md) for all configuration options**

## Documentation

- **[MinIO AIStor Docs](https://docs.min.io/enterprise/aistor-object-store/)** - Official MinIO documentation
- **[CLI Deployment Guide](CLI_DEPLOYMENT.md)** - Deploy using kubectl and gcloud
- **[Parameter Reference](DEPLOYMENT_PARAMETERS.md)** - All 21 configuration parameters

## Support

- **MinIO Support** - https://subnet.min.io
- **GCP Marketplace Support** - https://cloud.google.com/marketplace/docs/partners/support

## Pricing

**BYOL (Bring Your Own License)** - License purchased separately from MinIO. Standard GKE infrastructure costs apply.

**Contact MinIO** for licensing: https://min.io/pricing

## License

This packaging is for deploying MinIO AIStor through GCP Marketplace. See [MinIO's licensing terms](https://min.io/license) for the product itself.

---

**Version 1.0.0** • **Publisher:** MinIO Inc • **Contact:** https://min.io/contact
