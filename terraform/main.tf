terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Create Workload Identity Pool
resource "google_iam_workload_identity_pool" "oke_pool" {
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = var.workload_identity_pool_display_name
  description               = "Workload Identity Pool for OKE cluster integration"
  disabled                  = false
}

# Create OIDC Provider for OKE
resource "google_iam_workload_identity_pool_provider" "oke_oidc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.oke_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "OKE OIDC Provider"
  description                        = "OIDC provider for Oracle Kubernetes Engine"
  disabled                           = false

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.namespace"           = "assertion['kubernetes.io/namespace']"
    "attribute.service_account_name" = "assertion['kubernetes.io/serviceaccount/name']"
    "attribute.pod_name"            = "assertion['kubernetes.io/pod/name']"
  }

  # Optional: Add attribute condition to restrict access
  # attribute_condition = "assertion['kubernetes.io/namespace'] == 'default'"

  oidc {
    issuer_uri        = var.oke_oidc_issuer_url
    allowed_audiences = ["sts.googleapis.com"]
  }
}

# Create GCP Service Account for workloads
resource "google_service_account" "oke_workload" {
  account_id   = var.gcp_service_account_id
  display_name = "OKE Workload Service Account"
  description  = "Service account used by OKE pods to access GCP resources"
}

# Grant IAM roles to the service account (example: Storage Object Viewer)
resource "google_project_iam_member" "workload_storage_viewer" {
  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.oke_workload.email}"
}

# Allow Kubernetes service accounts to impersonate the GCP service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.oke_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.oke_pool.name}/attribute.namespace/${var.k8s_namespace}"
}

# Optional: Create a GCS bucket for testing
resource "google_storage_bucket" "test_bucket" {
  name          = "${var.gcp_project_id}-oke-test"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
}

# Grant the service account access to the test bucket
resource "google_storage_bucket_iam_member" "bucket_viewer" {
  bucket = google_storage_bucket.test_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.oke_workload.email}"
}
