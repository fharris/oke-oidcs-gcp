#!/bin/bash
# Setup script for GCP Workload Identity Federation with OKE

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required tools
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        echo_error "gcloud CLI not found. Please install it first."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found. Please install it first."
        exit 1
    fi
    
    echo_info "Prerequisites check passed."
}

# Get user inputs
get_inputs() {
    echo_info "Please provide the following information:"
    
    read -p "GCP Project ID: " PROJECT_ID
    read -p "OKE OIDC Issuer URL: " OIDC_ISSUER
    read -p "Workload Identity Pool ID [oke-workload-pool]: " POOL_ID
    POOL_ID=${POOL_ID:-oke-workload-pool}
    
    read -p "Workload Identity Provider ID [oke-oidc-provider]: " PROVIDER_ID
    PROVIDER_ID=${PROVIDER_ID:-oke-oidc-provider}
    
    read -p "GCP Service Account Name [oke-workload-sa]: " GSA_NAME
    GSA_NAME=${GSA_NAME:-oke-workload-sa}
    
    read -p "Kubernetes Namespace [default]: " K8S_NAMESPACE
    K8S_NAMESPACE=${K8S_NAMESPACE:-default}
    
    read -p "Kubernetes Service Account Name [oke-sa]: " K8S_SA_NAME
    K8S_SA_NAME=${K8S_SA_NAME:-oke-sa}
    
    echo_info "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  OIDC Issuer: ${OIDC_ISSUER}"
    echo "  Pool ID: ${POOL_ID}"
    echo "  Provider ID: ${PROVIDER_ID}"
    echo "  GCP SA Name: ${GSA_NAME}"
    echo "  K8s Namespace: ${K8S_NAMESPACE}"
    echo "  K8s SA Name: ${K8S_SA_NAME}"
    
    read -p "Proceed with setup? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_warn "Setup cancelled."
        exit 0
    fi
}

# Create Workload Identity Pool
create_workload_identity_pool() {
    echo_info "Creating Workload Identity Pool..."
    
    if gcloud iam workload-identity-pools describe ${POOL_ID} --location=global --project=${PROJECT_ID} &> /dev/null; then
        echo_warn "Workload Identity Pool already exists. Skipping..."
    else
        gcloud iam workload-identity-pools create ${POOL_ID} \
            --project="${PROJECT_ID}" \
            --location="global" \
            --display-name="OKE Workload Identity Pool"
        echo_info "Workload Identity Pool created."
    fi
}

# Create OIDC Provider
create_oidc_provider() {
    echo_info "Creating OIDC Provider..."
    
    if gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} \
        --workload-identity-pool=${POOL_ID} \
        --location=global \
        --project=${PROJECT_ID} &> /dev/null; then
        echo_warn "OIDC Provider already exists. Skipping..."
    else
        gcloud iam workload-identity-pools providers create-oidc ${PROVIDER_ID} \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool=${POOL_ID} \
            --issuer-uri="${OIDC_ISSUER}" \
            --allowed-audiences="sts.googleapis.com" \
            --attribute-mapping="google.subject=assertion.sub,attribute.namespace=assertion['kubernetes.io/namespace'],attribute.service_account_name=assertion['kubernetes.io/serviceaccount/name']"
        echo_info "OIDC Provider created."
    fi
}

# Create GCP Service Account
create_gcp_service_account() {
    echo_info "Creating GCP Service Account..."
    
    GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe ${GSA_EMAIL} --project=${PROJECT_ID} &> /dev/null; then
        echo_warn "GCP Service Account already exists. Skipping..."
    else
        gcloud iam service-accounts create ${GSA_NAME} \
            --project="${PROJECT_ID}" \
            --display-name="OKE Workload Service Account"
        echo_info "GCP Service Account created."
    fi
    
    # Grant example permissions (Storage Object Viewer)
    echo_info "Granting Storage Object Viewer role..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${GSA_EMAIL}" \
        --role="roles/storage.objectViewer" \
        --condition=None
}

# Bind K8s SA to GCP SA
bind_service_accounts() {
    echo_info "Binding Kubernetes Service Account to GCP Service Account..."
    
    GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
    WORKLOAD_IDENTITY_POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
    
    gcloud iam service-accounts add-iam-policy-binding ${GSA_EMAIL} \
        --project="${PROJECT_ID}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.namespace/${K8S_NAMESPACE}"
    
    echo_info "Service accounts bound successfully."
}

# Main execution
main() {
    echo_info "GCP Workload Identity Federation Setup for OKE"
    echo_info "=============================================="
    
    check_prerequisites
    get_inputs
    create_workload_identity_pool
    create_oidc_provider
    create_gcp_service_account
    bind_service_accounts
    
    echo_info "Setup completed successfully!"
    echo_info "Next steps:"
    echo "  1. Apply Kubernetes resources: kubectl apply -f k8s/"
    echo "  2. Test the setup: ./scripts/test-access.sh"
}

main "$@"
