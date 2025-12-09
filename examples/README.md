# Usage Examples

This directory contains example applications demonstrating how to use OKE-GCP OIDC integration for various GCP services.

## Prerequisites

Before running these examples:
1. Complete the setup in [GETTING_STARTED.md](../GETTING_STARTED.md)
2. Ensure the GCP service account has appropriate permissions
3. Create the Kubernetes service account (`kubectl apply -f k8s/serviceaccount.yaml`)

## Available Examples

### 1. Google Cloud Storage (GCS) Example

**File**: `storage-example.yaml`

**Description**: Demonstrates accessing Google Cloud Storage buckets.

**Required Permissions**:
- `roles/storage.objectViewer` - To list buckets and read objects
- `roles/storage.objectCreator` - To upload objects (optional)

**Deploy**:
```bash
kubectl apply -f examples/storage-example.yaml
```

**Test**:
```bash
# Check logs
kubectl logs gcs-storage-example

# List buckets interactively
kubectl exec -it gcs-storage-example -- gcloud storage ls

# Download a file
kubectl exec -it gcs-storage-example -- gcloud storage cp gs://your-bucket/file.txt /tmp/
```

### 2. Secret Manager Example

**File**: `secrets-example.yaml`

**Description**: Demonstrates accessing secrets from GCP Secret Manager.

**Required Permissions**:
- `roles/secretmanager.secretAccessor` - To access secret values
- `roles/secretmanager.viewer` - To list secrets (optional)

**Setup**:
1. Create a secret in GCP:
   ```bash
   echo -n "my-secret-value" | gcloud secrets create my-secret --data-file=-
   ```

2. Update the pod spec with your project ID

3. Deploy:
   ```bash
   kubectl apply -f examples/secrets-example.yaml
   ```

**Test**:
```bash
# Check logs
kubectl logs gcp-secrets-example

# Access a secret interactively
kubectl exec -it gcp-secrets-example -- \
  gcloud secrets versions access latest --secret=my-secret
```

## Creating Your Own Application

### Python Example

```python
from google.cloud import storage
import os

# The OIDC token will be automatically used by google-cloud libraries
# when GOOGLE_APPLICATION_CREDENTIALS points to the token file

def list_buckets():
    """List all GCS buckets in the project."""
    storage_client = storage.Client()
    buckets = list(storage_client.list_buckets())
    print("Buckets:")
    for bucket in buckets:
        print(f"  - {bucket.name}")

if __name__ == "__main__":
    list_buckets()
```

**Dockerfile**:
```dockerfile
FROM python:3.11-slim

RUN pip install google-cloud-storage

COPY app.py /app/app.py

WORKDIR /app

CMD ["python", "app.py"]
```

**Kubernetes Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-gcp-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: python-gcp-app
  template:
    metadata:
      labels:
        app: python-gcp-app
    spec:
      serviceAccountName: oke-sa
      containers:
      - name: app
        image: your-registry/python-gcp-app:latest
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

### Go Example

```go
package main

import (
    "context"
    "fmt"
    "log"

    "cloud.google.com/go/storage"
    "google.golang.org/api/iterator"
)

func main() {
    ctx := context.Background()
    
    // The client library will automatically use GOOGLE_APPLICATION_CREDENTIALS
    client, err := storage.NewClient(ctx)
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    // List buckets
    it := client.Buckets(ctx, "your-project-id")
    fmt.Println("Buckets:")
    for {
        battrs, err := it.Next()
        if err == iterator.Done {
            break
        }
        if err != nil {
            log.Fatalf("Failed to iterate: %v", err)
        }
        fmt.Printf("  - %s\n", battrs.Name)
    }
}
```

### Node.js Example

```javascript
const {Storage} = require('@google-cloud/storage');

async function listBuckets() {
  // Creates a client using GOOGLE_APPLICATION_CREDENTIALS
  const storage = new Storage();

  const [buckets] = await storage.getBuckets();
  console.log('Buckets:');
  buckets.forEach(bucket => {
    console.log(`  - ${bucket.name}`);
  });
}

listBuckets().catch(console.error);
```

## Common Patterns

### Environment Variables

Always set these environment variables in your pod:
```yaml
env:
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: /var/run/secrets/tokens/gcp-ksa
- name: CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE
  value: /var/run/secrets/tokens/gcp-ksa
```

### Volume Mount

Always include this volume configuration:
```yaml
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

### Token Refresh

The token automatically refreshes. Your application doesn't need to handle refresh logic as long as:
- The projected volume is properly configured
- The `expirationSeconds` is set appropriately (recommended: 3600)

## Supported GCP Services

With proper IAM permissions, you can access:

- **Cloud Storage** (GCS)
- **Secret Manager**
- **Cloud SQL**
- **Pub/Sub**
- **Firestore**
- **BigQuery**
- **Cloud Run**
- **Compute Engine**
- **Kubernetes Engine** (GKE)
- And many more...

## Granting Additional Permissions

To access different GCP services, grant the appropriate roles:

```bash
# For Cloud SQL
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# For Pub/Sub
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"

# For BigQuery
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"
```

## Troubleshooting

If examples don't work:

1. **Check token is mounted**:
   ```bash
   kubectl exec <pod-name> -- cat /var/run/secrets/tokens/gcp-ksa | head -c 50
   ```

2. **Verify authentication**:
   ```bash
   kubectl exec <pod-name> -- gcloud auth list
   ```

3. **Check permissions**:
   ```bash
   gcloud projects get-iam-policy YOUR_PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:oke-workload-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com"
   ```

4. See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for more help
