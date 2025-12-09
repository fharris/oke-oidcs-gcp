variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "oke-workload-pool"
}

variable "workload_identity_pool_display_name" {
  description = "Display name for Workload Identity Pool"
  type        = string
  default     = "OKE Workload Identity Pool"
}

variable "workload_identity_provider_id" {
  description = "Workload Identity Provider ID"
  type        = string
  default     = "oke-oidc-provider"
}

variable "oke_oidc_issuer_url" {
  description = "OKE OIDC Issuer URL (format: https://[region].oraclecloud.com/v1/kubernetes/[cluster-ocid]/token)"
  type        = string
}

variable "gcp_service_account_id" {
  description = "GCP Service Account ID"
  type        = string
  default     = "oke-workload-sa"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "default"
}

variable "k8s_service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "oke-sa"
}
