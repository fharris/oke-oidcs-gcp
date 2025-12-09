#!/bin/bash
# Test script to verify OKE pod can access GCP resources

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

# Configuration
POD_NAME=${1:-gcp-test-pod}
NAMESPACE=${2:-default}

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo_info "Testing GCP access from OKE pod: ${POD_NAME}"

# Check if pod exists
if ! kubectl get pod ${POD_NAME} -n ${NAMESPACE} &> /dev/null; then
    echo_error "Pod ${POD_NAME} not found in namespace ${NAMESPACE}"
    echo_info "Creating test pod..."
    kubectl apply -f k8s/serviceaccount.yaml
    kubectl apply -f k8s/test-pod.yaml
    echo_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=Ready pod/${POD_NAME} -n ${NAMESPACE} --timeout=120s
fi

# Test 1: Check if token is mounted
echo_info "Test 1: Checking if OIDC token is mounted..."
if kubectl exec ${POD_NAME} -n ${NAMESPACE} -- test -f /var/run/secrets/tokens/gcp-ksa; then
    echo_info "✓ Token file exists"
else
    echo_error "✗ Token file not found"
    exit 1
fi

# Test 2: Inspect token claims
echo_info "Test 2: Inspecting token claims..."
TOKEN=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- cat /var/run/secrets/tokens/gcp-ksa)
if [ -n "$TOKEN" ]; then
    echo_info "✓ Token retrieved successfully"
    # Decode JWT header and payload (for debugging)
    echo "Token preview (first 50 chars): ${TOKEN:0:50}..."
else
    echo_error "✗ Failed to retrieve token"
    exit 1
fi

# Test 3: Authenticate with GCP
echo_info "Test 3: Testing GCP authentication..."
if kubectl exec ${POD_NAME} -n ${NAMESPACE} -- gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    echo_info "✓ Successfully authenticated with GCP"
else
    echo_warn "Authentication check inconclusive"
fi

# Test 4: List GCS buckets (requires appropriate permissions)
echo_info "Test 4: Testing GCS bucket access..."
if kubectl exec ${POD_NAME} -n ${NAMESPACE} -- gcloud storage ls 2>/dev/null; then
    echo_info "✓ Successfully listed GCS buckets"
else
    echo_warn "Could not list GCS buckets (this is expected if no permissions granted)"
fi

# Test 5: Check service account info
echo_info "Test 5: Checking service account info..."
SA_INFO=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- gcloud auth list --format=json 2>/dev/null || echo "[]")
echo "Service Account Info: ${SA_INFO}"

echo_info "Testing completed!"
echo_info "Summary:"
echo "  - Token mounted: ✓"
echo "  - GCP authentication: Check logs above"
echo "  - Resource access: Depends on permissions granted"
