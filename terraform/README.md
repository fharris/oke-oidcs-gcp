# Terraform Configuration for GCP Workload Identity

This directory contains Terraform configuration to automate the setup of GCP Workload Identity Federation for OKE clusters.

## Prerequisites

- Terraform >= 1.0
- GCP account with appropriate permissions
- OKE cluster with OIDC Discovery enabled

## Usage

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```bash
   # Required values
   gcp_project_id      = "your-gcp-project-id"
   oke_oidc_issuer_url = "https://your-region.oraclecloud.com/v1/kubernetes/your-cluster-ocid/token"
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review the plan:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Resources Created

- **Workload Identity Pool**: Container for external identity providers
- **OIDC Provider**: Configured to trust your OKE cluster
- **GCP Service Account**: Used by OKE pods to access GCP resources
- **IAM Bindings**: Allows Kubernetes service accounts to impersonate the GCP service account
- **Test GCS Bucket**: Optional bucket for testing (can be disabled in main.tf)

## Outputs

After applying, Terraform will output:
- Workload Identity Pool name
- Provider name
- GCP Service Account email
- Test bucket name

## Customization

### Adding More IAM Roles

Edit `main.tf` to grant additional roles:

```hcl
resource "google_project_iam_member" "workload_custom_role" {
  project = var.gcp_project_id
  role    = "roles/compute.viewer"  # Your desired role
  member  = "serviceAccount:${google_service_account.oke_workload.email}"
}
```

### Restricting by Namespace

Uncomment the `attribute_condition` in `main.tf`:

```hcl
attribute_condition = "assertion['kubernetes.io/namespace'] == 'default'"
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Important Notes

1. Store `terraform.tfvars` securely - it contains sensitive configuration
2. Use Terraform state backend for team collaboration
3. Review IAM permissions carefully before applying
