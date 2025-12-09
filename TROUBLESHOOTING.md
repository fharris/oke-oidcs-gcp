# Troubleshooting Guide

Common issues and solutions when setting up OKE to GCP OIDC integration.

## Table of Contents

1. [OIDC Provider Issues](#oidc-provider-issues)
2. [Token Problems](#token-problems)
3. [Authentication Failures](#authentication-failures)
4. [Permission Issues](#permission-issues)
5. [Network Connectivity](#network-connectivity)

## OIDC Provider Issues

### Error: OIDC Issuer URL Not Accessible

**Symptoms:**
```
Error creating OIDC provider: The issuer URI is not accessible
```

**Solutions:**
1. Verify the OIDC issuer URL format:
   ```
   https://[region].oraclecloud.com/v1/kubernetes/[cluster-ocid]/token
   ```

2. Check if the OIDC discovery endpoint is accessible:
   ```bash
   curl https://[region].oraclecloud.com/v1/kubernetes/[cluster-ocid]/token/.well-known/openid-configuration
   ```

3. Ensure your OKE cluster has OIDC discovery enabled

### Error: Invalid Attribute Mapping

**Symptoms:**
```
Error: Invalid attribute mapping expression
```

**Solution:**
Review the attribute mapping syntax:
```bash
--attribute-mapping="google.subject=assertion.sub,attribute.namespace=assertion['kubernetes.io/namespace'],attribute.service_account_name=assertion['kubernetes.io/serviceaccount/name']"
```

Ensure:
- Keys are properly quoted
- Brackets are used for nested fields
- Commas separate mappings

## Token Problems

### Token Not Mounted in Pod

**Symptoms:**
```
ls: /var/run/secrets/tokens/gcp-ksa: No such file or directory
```

**Solutions:**
1. Check pod specification has the projected volume:
   ```yaml
   volumes:
   - name: gcp-token
     projected:
       sources:
       - serviceAccountToken:
           path: gcp-ksa
           expirationSeconds: 3600
           audience: sts.googleapis.com
   ```

2. Verify volume mount in container:
   ```yaml
   volumeMounts:
   - name: gcp-token
     mountPath: /var/run/secrets/tokens
     readOnly: true
   ```

3. Check if the service account exists:
   ```bash
   kubectl get serviceaccount oke-sa -n default
   ```

### Token Has Wrong Claims

**Symptoms:**
Authentication fails even though token is mounted

**Solutions:**
1. Decode and inspect the token (JWT tokens are not base64 encoded, they are already readable):
   ```bash
   # View the raw JWT token (it's already readable text)
   kubectl exec gcp-test-pod -- cat /var/run/secrets/tokens/gcp-ksa
   
   # To properly decode JWT claims, use a tool like jwt-cli or online JWT decoder
   ```

2. Verify these claims are present:
   - `sub`: Subject (should match pattern)
   - `kubernetes.io/namespace`: Namespace name
   - `kubernetes.io/serviceaccount/name`: Service account name
   - `aud`: Audience (should be `sts.googleapis.com`)

3. Check token expiration (requires jq to be installed in pod):
   ```bash
   # Note: JWT tokens use base64url encoding, not standard base64
   # You may need to install jwt-cli or similar tool for proper decoding
   kubectl exec gcp-test-pod -- sh -c 'cat /var/run/secrets/tokens/gcp-ksa | cut -d. -f2 | base64 -d 2>/dev/null || echo "Token format may require base64url decoding"'
   ```

## Authentication Failures

### Error: Unable to Generate Access Token

**Symptoms:**
```
ERROR: (gcloud.auth.login) Unable to generate access token
```

**Solutions:**
1. Verify Workload Identity Pool exists:
   ```bash
   gcloud iam workload-identity-pools describe oke-workload-pool \
     --location=global \
     --project=YOUR_PROJECT_ID
   ```

2. Check OIDC Provider configuration:
   ```bash
   gcloud iam workload-identity-pools providers describe oke-oidc-provider \
     --workload-identity-pool=oke-workload-pool \
     --location=global \
     --project=YOUR_PROJECT_ID
   ```

3. Verify issuer URI matches your OKE cluster

### Error: Principal Does Not Exist

**Symptoms:**
```
ERROR: Principal does not exist in workload identity pool
```

**Solutions:**
1. Check attribute condition in OIDC provider:
   ```bash
   gcloud iam workload-identity-pools providers describe oke-oidc-provider \
     --workload-identity-pool=oke-workload-pool \
     --location=global \
     --project=YOUR_PROJECT_ID \
     --format="get(attributeCondition)"
   ```

2. Ensure namespace matches the condition (if set)

3. Verify attribute mapping extracts namespace correctly

## Permission Issues

### Error: Permission Denied When Accessing GCP Resources

**Symptoms:**
```
ERROR: (gcloud.storage.ls) Permission denied
```

**Solutions:**
1. Check GCP service account has required roles:
   ```bash
   gcloud projects get-iam-policy YOUR_PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com"
   ```

2. Verify Workload Identity binding:
   ```bash
   gcloud iam service-accounts get-iam-policy \
     oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```

3. Add missing role:
   ```bash
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/storage.objectViewer"
   ```

### Error: Workload Identity User Role Not Bound

**Symptoms:**
```
Permission denied: Principal cannot impersonate service account
```

**Solution:**
Add the workload identity user binding:
```bash
gcloud iam service-accounts add-iam-policy-binding \
  oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/oke-workload-pool/attribute.namespace/default"
```

## Network Connectivity

### Cannot Reach GCP APIs

**Symptoms:**
Timeouts or connection refused errors

**Solutions:**
1. Check pod has internet access:
   ```bash
   kubectl exec gcp-test-pod -- curl -I https://www.googleapis.com
   ```

2. Verify DNS resolution:
   ```bash
   kubectl exec gcp-test-pod -- nslookup sts.googleapis.com
   ```

3. Check for network policies blocking egress:
   ```bash
   kubectl get networkpolicies -A
   ```

## Debugging Tips

### Enable Verbose Logging

```bash
kubectl exec gcp-test-pod -- gcloud auth login \
  --cred-file=/var/run/secrets/tokens/gcp-ksa \
  --verbosity=debug
```

### Check Pod Events

```bash
kubectl describe pod gcp-test-pod -n default
```

### View Pod Logs

```bash
kubectl logs gcp-test-pod -n default
```

### Test Token Exchange Manually

```bash
# Get the token
TOKEN=$(kubectl exec gcp-test-pod -- cat /var/run/secrets/tokens/gcp-ksa)

# Exchange for GCP credentials (outside the cluster)
curl -X POST https://sts.googleapis.com/v1/token \
  -H "Content-Type: application/json" \
  -d "{
    \"audience\": \"//iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/oke-workload-pool/providers/oke-oidc-provider\",
    \"grantType\": \"urn:ietf:params:oauth:grant-type:token-exchange\",
    \"requestedTokenType\": \"urn:ietf:params:oauth:token-type:access_token\",
    \"scope\": \"https://www.googleapis.com/auth/cloud-platform\",
    \"subjectTokenType\": \"urn:ietf:params:oauth:token-type:jwt\",
    \"subjectToken\": \"${TOKEN}\"
  }"
```

## Getting Help

If issues persist:

1. Review GCP Audit Logs:
   ```bash
   gcloud logging read "resource.type=iam_workload_identity_pool" --limit 50
   ```

2. Check OKE cluster logs in OCI Console

3. Verify all prerequisites are met

4. Consult the official documentation:
   - [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
   - [OKE Documentation](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
