# Getting Started Guide

This guide will walk you through setting up OIDC-based authentication between Oracle Kubernetes Engine (OKE) and Google Cloud Platform (GCP).

## Time Estimate

- Initial setup: 30-45 minutes
- Testing and validation: 15 minutes

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] **OKE Cluster**: An OKE cluster up and running
- [ ] **GCP Project**: A GCP project with billing enabled
- [ ] **Tools Installed**:
  - [ ] `kubectl` (connected to your OKE cluster)
  - [ ] `gcloud` CLI (authenticated)
  - [ ] `oci` CLI (optional)
  - [ ] `terraform` (if using Terraform approach)
- [ ] **Permissions**:
  - [ ] OCI: Manage OKE clusters
  - [ ] GCP: IAM Admin, Service Account Admin

## Quick Start (Script-Based Setup)

### Step 1: Get OKE Cluster Information

```bash
# Using OCI CLI
oci ce cluster get --cluster-id <your-cluster-ocid>

# Get the OIDC issuer URL
# Format: https://[region].oraclecloud.com/v1/kubernetes/[cluster-ocid]/token
export OIDC_ISSUER="https://us-ashburn-1.oraclecloud.com/v1/kubernetes/ocid1.cluster.oc1.iad.xxx/token"
```

### Step 2: Run Setup Script

```bash
# Make script executable (if not already)
chmod +x scripts/setup-gcp.sh

# Run the setup script
./scripts/setup-gcp.sh
```

The script will prompt you for:
- GCP Project ID
- OKE OIDC Issuer URL
- Workload Identity Pool ID (default: oke-workload-pool)
- Provider ID (default: oke-oidc-provider)
- Service account names

### Step 3: Deploy Kubernetes Resources

```bash
# Apply the Kubernetes manifests
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/test-pod.yaml
```

### Step 4: Test the Setup

```bash
# Run the test script
./scripts/test-access.sh

# Or manually test
kubectl exec -it gcp-test-pod -- gcloud auth list
kubectl exec -it gcp-test-pod -- gcloud storage ls
```

## Detailed Setup (Manual)

### Option A: Using Terraform

1. **Configure Terraform Variables**:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Initialize and Apply**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Deploy Kubernetes Resources**:
   ```bash
   cd ..
   kubectl apply -f k8s/
   ```

### Option B: Using gcloud Commands

1. **Create Workload Identity Pool**:
   ```bash
   gcloud iam workload-identity-pools create oke-workload-pool \
     --project="YOUR_PROJECT_ID" \
     --location="global" \
     --display-name="OKE Workload Identity Pool"
   ```

2. **Create OIDC Provider**:
   ```bash
   gcloud iam workload-identity-pools providers create-oidc oke-oidc-provider \
     --project="YOUR_PROJECT_ID" \
     --location="global" \
     --workload-identity-pool=oke-workload-pool \
     --issuer-uri="YOUR_OIDC_ISSUER_URL" \
     --allowed-audiences="sts.googleapis.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.namespace=assertion['kubernetes.io/namespace'],attribute.service_account_name=assertion['kubernetes.io/serviceaccount/name']"
   ```

3. **Create GCP Service Account**:
   ```bash
   gcloud iam service-accounts create oke-workload-sa \
     --project="YOUR_PROJECT_ID" \
     --display-name="OKE Workload Service Account"
   ```

4. **Grant Permissions**:
   ```bash
   # Example: Grant Storage Object Viewer
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/storage.objectViewer"
   ```

5. **Bind Service Accounts**:
   ```bash
   PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)")
   
   gcloud iam service-accounts add-iam-policy-binding \
     oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com \
     --project="YOUR_PROJECT_ID" \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/oke-workload-pool/attribute.namespace/default"
   ```

6. **Deploy Kubernetes Resources**:
   ```bash
   kubectl apply -f k8s/serviceaccount.yaml
   kubectl apply -f k8s/test-pod.yaml
   ```

## Validation Steps

### 1. Verify GCP Resources

```bash
# List Workload Identity Pools
gcloud iam workload-identity-pools list --location=global --project=YOUR_PROJECT_ID

# List Providers
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=oke-workload-pool \
  --location=global \
  --project=YOUR_PROJECT_ID

# Check Service Account
gcloud iam service-accounts describe oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### 2. Verify Kubernetes Resources

```bash
# Check service account
kubectl get serviceaccount oke-sa -n default

# Check pod status
kubectl get pods -n default
kubectl describe pod gcp-test-pod -n default
```

### 3. Test Authentication

```bash
# Check token is mounted
kubectl exec gcp-test-pod -- ls -l /var/run/secrets/tokens/

# View token (partially)
kubectl exec gcp-test-pod -- cat /var/run/secrets/tokens/gcp-ksa | head -c 50

# Test gcloud authentication
kubectl exec gcp-test-pod -- gcloud auth list

# Test resource access
kubectl exec gcp-test-pod -- gcloud storage ls
```

## Common Next Steps

### Add More Permissions

```bash
# Add Compute Viewer role
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.viewer"

# Add Secret Manager Secret Accessor
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Deploy Production Workload

```bash
# Use the deployment instead of test pod
kubectl apply -f k8s/deployment.yaml

# Scale the deployment
kubectl scale deployment gcp-workload --replicas=3
```

### Restrict to Specific Namespace

Update the OIDC provider with an attribute condition:

```bash
gcloud iam workload-identity-pools providers update-oidc oke-oidc-provider \
  --workload-identity-pool=oke-workload-pool \
  --location=global \
  --project=YOUR_PROJECT_ID \
  --attribute-condition="assertion['kubernetes.io/namespace'] == 'production'"
```

## Troubleshooting

If you encounter issues, refer to the [TROUBLESHOOTING.md](TROUBLESHOOTING.md) guide.

Common issues:
- **Token not mounted**: Check pod volume configuration
- **Authentication fails**: Verify OIDC provider configuration
- **Permission denied**: Check IAM roles on GCP service account

## Cleanup

When you're done testing:

```bash
# Option 1: Using cleanup script
./scripts/cleanup.sh

# Option 2: Using Terraform
cd terraform
terraform destroy

# Option 3: Manual cleanup
kubectl delete -f k8s/
gcloud iam service-accounts delete oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
gcloud iam workload-identity-pools delete oke-workload-pool --location=global
```

## Next Steps

- Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- Check [k8s/README.md](k8s/README.md) for pod configuration details
- See [terraform/README.md](terraform/README.md) for infrastructure as code
- Explore GCP services accessible with this setup

## Support

For issues or questions:
1. Check the troubleshooting guide
2. Review GCP and OKE documentation
3. Open an issue in this repository
