#!/bin/bash
# Cleanup script to remove GCP resources

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

# Get user inputs
echo_warn "This script will delete GCP resources. Are you sure?"
read -p "Continue? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo_info "Cleanup cancelled."
    exit 0
fi

read -p "GCP Project ID: " PROJECT_ID
read -p "Workload Identity Pool ID [oke-workload-pool]: " POOL_ID
POOL_ID=${POOL_ID:-oke-workload-pool}

read -p "Workload Identity Provider ID [oke-oidc-provider]: " PROVIDER_ID
PROVIDER_ID=${PROVIDER_ID:-oke-oidc-provider}

read -p "GCP Service Account Name [oke-workload-sa]: " GSA_NAME
GSA_NAME=${GSA_NAME:-oke-workload-sa}

GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Delete GCP Service Account
echo_info "Deleting GCP Service Account..."
if gcloud iam service-accounts describe ${GSA_EMAIL} --project=${PROJECT_ID} &> /dev/null; then
    gcloud iam service-accounts delete ${GSA_EMAIL} --project=${PROJECT_ID} --quiet
    echo_info "Service Account deleted."
else
    echo_warn "Service Account not found."
fi

# Delete OIDC Provider
echo_info "Deleting OIDC Provider..."
if gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} \
    --workload-identity-pool=${POOL_ID} \
    --location=global \
    --project=${PROJECT_ID} &> /dev/null; then
    gcloud iam workload-identity-pools providers delete ${PROVIDER_ID} \
        --workload-identity-pool=${POOL_ID} \
        --location=global \
        --project=${PROJECT_ID} \
        --quiet
    echo_info "OIDC Provider deleted."
else
    echo_warn "OIDC Provider not found."
fi

# Delete Workload Identity Pool
echo_info "Deleting Workload Identity Pool..."
if gcloud iam workload-identity-pools describe ${POOL_ID} --location=global --project=${PROJECT_ID} &> /dev/null; then
    gcloud iam workload-identity-pools delete ${POOL_ID} \
        --location=global \
        --project=${PROJECT_ID} \
        --quiet
    echo_info "Workload Identity Pool deleted."
else
    echo_warn "Workload Identity Pool not found."
fi

# Delete Kubernetes resources
echo_info "Deleting Kubernetes resources..."
kubectl delete -f k8s/ --ignore-not-found=true

echo_info "Cleanup completed!"
