# Authorizing Pods in OKE to Access GCP Resources Using OIDC

This guide demonstrates how to configure Oracle Kubernetes Engine (OKE) pods to securely access Google Cloud Platform (GCP) resources using OpenID Connect (OIDC) and Workload Identity Federation.

## Overview

This solution enables OKE pods to authenticate to GCP services without storing long-lived credentials. Instead, it uses:
- **OKE's OIDC Discovery**: OKE clusters can be configured to expose an OIDC issuer URL
- **GCP Workload Identity Federation**: GCP trusts external OIDC providers to authenticate workloads
- **Kubernetes Service Accounts**: Pods use service accounts that get OIDC tokens

## Architecture

```
OKE Pod → K8s Service Account → OIDC Token → GCP Workload Identity Pool → GCP Service Account → GCP Resources
```

## Prerequisites

- Oracle Cloud Infrastructure (OCI) account with OKE cluster
- Google Cloud Platform account with a project
- `kubectl` configured for your OKE cluster
- `gcloud` CLI installed and authenticated
- `oci` CLI installed (optional, for OCI operations)
- Terraform (optional, for infrastructure automation)

## Setup Steps

### 1. Enable OIDC Discovery on OKE Cluster

OKE clusters support OIDC discovery. Get your cluster's OIDC issuer URL:

```bash
# Get the cluster OCID
CLUSTER_OCID="your-cluster-ocid"

# The OIDC issuer URL format for OKE is:
# https://[region].oraclecloud.com/v1/kubernetes/[cluster-ocid]/token
OIDC_ISSUER="https://[region].oraclecloud.com/v1/kubernetes/${CLUSTER_OCID}/token"
```

### 2. Configure GCP Workload Identity Federation

#### Create Workload Identity Pool

```bash
# Set variables
PROJECT_ID="your-gcp-project-id"
POOL_ID="oke-workload-pool"
POOL_DISPLAY_NAME="OKE Workload Identity Pool"

# Create the workload identity pool
gcloud iam workload-identity-pools create ${POOL_ID} \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="${POOL_DISPLAY_NAME}"
```

#### Create Workload Identity Provider

```bash
PROVIDER_ID="oke-oidc-provider"
OIDC_ISSUER="https://your-region.oraclecloud.com/v1/kubernetes/your-cluster-ocid/token"

gcloud iam workload-identity-pools providers create-oidc ${PROVIDER_ID} \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool=${POOL_ID} \
    --issuer-uri="${OIDC_ISSUER}" \
    --allowed-audiences="sts.googleapis.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.namespace=assertion['kubernetes.io/namespace'],attribute.service_account_name=assertion['kubernetes.io/serviceaccount/name']" \
    --attribute-condition="assertion['kubernetes.io/namespace'] == 'default'"
```

### 3. Create GCP Service Account

```bash
GSA_NAME="oke-workload-sa"
GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create ${GSA_NAME} \
    --project="${PROJECT_ID}" \
    --display-name="OKE Workload Service Account"

# Grant permissions (example: Storage Object Viewer)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/storage.objectViewer"
```

### 4. Bind Kubernetes Service Account to GCP Service Account

```bash
K8S_NAMESPACE="default"
K8S_SA_NAME="oke-sa"
WORKLOAD_IDENTITY_POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# Allow the Kubernetes service account to impersonate the GCP service account
gcloud iam service-accounts add-iam-policy-binding ${GSA_EMAIL} \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL}/attribute.namespace/${K8S_NAMESPACE}"
```

### 5. Create Kubernetes Resources

Create a Kubernetes Service Account:

```yaml
# k8s/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oke-sa
  namespace: default
```

Create a test pod that uses the service account:

```yaml
# k8s/test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gcp-test-pod
  namespace: default
spec:
  serviceAccountName: oke-sa
  containers:
  - name: gcloud
    image: google/cloud-sdk:slim
    command: ["sleep", "infinity"]
    env:
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: /var/run/secrets/tokens/gcp-ksa
    volumeMounts:
    - name: gcp-token
      mountPath: /var/run/secrets/tokens
      readOnly: true
  volumes:
  - name: gcp-token
    projected:
      sources:
      - serviceAccountToken:
          path: gcp-ksa
          expirationSeconds: 3600
          audience: sts.googleapis.com
```

### 6. Deploy and Test

```bash
# Apply Kubernetes resources
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/test-pod.yaml

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/gcp-test-pod -n default --timeout=60s

# Test GCP access
kubectl exec -it gcp-test-pod -n default -- gcloud auth login --cred-file=/var/run/secrets/tokens/gcp-ksa
kubectl exec -it gcp-test-pod -n default -- gcloud storage ls
```

## Configuration Files

This repository includes:

- `terraform/` - Terraform configuration for GCP Workload Identity setup
- `k8s/` - Kubernetes manifests for service accounts and example pods
- `scripts/` - Helper scripts for setup and validation

## Troubleshooting

### OIDC Token Issues

```bash
# Check if token is mounted correctly
kubectl exec -it gcp-test-pod -n default -- cat /var/run/secrets/tokens/gcp-ksa

# Decode the JWT token to inspect claims
kubectl exec -it gcp-test-pod -n default -- cat /var/run/secrets/tokens/gcp-ksa | base64 -d
```

### Permission Denied Errors

- Verify the GCP service account has the required roles
- Check the workload identity binding is correct
- Ensure the attribute mapping matches your token claims

### OIDC Provider Configuration

- Verify the OIDC issuer URL is accessible
- Check that the audience matches ("sts.googleapis.com")
- Ensure attribute mapping extracts the correct fields from the token

## Security Considerations

1. **Least Privilege**: Grant only necessary permissions to GCP service accounts
2. **Namespace Isolation**: Use attribute conditions to restrict access by namespace
3. **Token Expiration**: Configure appropriate token expiration times
4. **Audit Logging**: Enable Cloud Audit Logs to track access

## References

- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [OKE OIDC Authentication](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupoidcprovider.htm)
- [Kubernetes Service Account Tokens](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

## License

MIT
