output "workload_identity_pool_name" {
  description = "Full name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.oke_pool.name
}

output "workload_identity_provider_name" {
  description = "Full name of the Workload Identity Provider"
  value       = google_iam_workload_identity_pool_provider.oke_oidc.name
}

output "gcp_service_account_email" {
  description = "Email of the GCP service account"
  value       = google_service_account.oke_workload.email
}

output "test_bucket_name" {
  description = "Name of the test GCS bucket"
  value       = google_storage_bucket.test_bucket.name
}

output "workload_identity_pool_provider_full_id" {
  description = "Full resource ID for the Workload Identity Pool Provider"
  value       = "projects/${var.gcp_project_id}/locations/global/workloadIdentityPools/${var.workload_identity_pool_id}/providers/${var.workload_identity_provider_id}"
}
