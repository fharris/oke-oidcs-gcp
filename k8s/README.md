# Kubernetes Manifests

This directory contains Kubernetes manifests for configuring OKE pods to access GCP resources.

## Files

- **serviceaccount.yaml**: Creates the Kubernetes service account used by pods
- **test-pod.yaml**: Single pod for testing GCP access
- **deployment.yaml**: Deployment with multiple replicas for production use

## Usage

### Apply All Resources

```bash
kubectl apply -f k8s/
```

### Apply Individual Resources

```bash
# Create service account
kubectl apply -f k8s/serviceaccount.yaml

# Create test pod
kubectl apply -f k8s/test-pod.yaml

# Create deployment
kubectl apply -f k8s/deployment.yaml
```

## Service Account Configuration

The service account must be created before deploying pods:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oke-sa
  namespace: default
```

## Pod Configuration

Pods must:
1. Use the service account: `serviceAccountName: oke-sa`
2. Mount the OIDC token as a volume
3. Set `GOOGLE_APPLICATION_CREDENTIALS` environment variable

Example:

```yaml
spec:
  serviceAccountName: oke-sa
  containers:
  - name: app
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

## Testing

After deploying, test GCP access:

```bash
# Check if pod is running
kubectl get pods -n default

# Check token is mounted
kubectl exec gcp-test-pod -n default -- cat /var/run/secrets/tokens/gcp-ksa

# Test GCP authentication
kubectl exec gcp-test-pod -n default -- gcloud auth list

# Test resource access
kubectl exec gcp-test-pod -n default -- gcloud storage ls
```

## Troubleshooting

### Token Not Mounted

Check the volume configuration in your pod spec. Ensure:
- The volume is defined in `volumes:`
- The volume mount is defined in `volumeMounts:`
- The path matches in both places

### Authentication Fails

1. Verify the OIDC provider is configured correctly in GCP
2. Check the Workload Identity binding
3. Ensure the audience is set to `sts.googleapis.com`

### Permission Denied

1. Verify the GCP service account has the required IAM roles
2. Check the Workload Identity binding includes your namespace
3. Review attribute conditions in the OIDC provider
