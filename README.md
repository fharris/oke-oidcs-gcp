# Authorizing Pods in OKE to Access GCP Resources Using OpenID Connect (OIDC) Discovery
Authorizing Pods in OKE to Access GCP Resources Using OpenID Connect (OIDC) Discovery


# 1. Prepare OKE to support OIDC Discovery

## 1.1 - Enable OIDC discovery

In the OKE Documentation you can see how to create a cluster with OIDC Discovery enabled. But you can also provision a cluster without it and update it once is provisioned. 

Like this if you want to do it in the console:

<img width="1230" height="795" alt="image" src="https://github.com/user-attachments/assets/02cf2177-48d3-47f4-ae8c-32ec0bfac4ae" />


Or like this if you want to do it with OCI CLI:

Create a JSON file cluster-enable-oidc.json :

```
{
  "options": {
    "openIdConnectDiscovery": {
      "isOpenIdConnectDiscoveryEnabled": true
    }
  }
```

and run the following command:

```
oci ce cluster update --cluster-id ocid1.cluster.oc1.iad.aaaaaaaaaf______jrd --from-json file://./cluster-enable-oidc.json
```

You might need to wait a few moments. If you want to confirm, run the following command:

```
oci ce cluster get --cluster-id ocid1.cluster.oc1.iad.aaaaaaaaaf______jrd  | grep -C 'open-id-connect-discovery'
```

You should see something like the image below:


<img width="1557" height="370" alt="image" src="https://github.com/user-attachments/assets/6a2eb2c3-f8e0-48c3-8fdb-f1abad078cea" />


retain the **open-id-connect-discovery-endpoint** . We will need it later.

Documentation: [OpenID Connect Discovery - Oracle Cloud Infrastructure Docs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengOpenIDConnect-Discovery.htm)



## 1.2 - Create a namespace and a service account

Create a namespace and a service account for the OKE workloads:

```
kubectl create ns oke-gcp-ns;
kubectl -n oke-gcp-ns create sa oke-gcp-sa;
```

# 2 - Prepare GCP resources

We will try to run the commands with GCP CLI, but you can always try to do it in the console as well:

## 1. create a GCP project

GCP recommends to use a dedicated project to manage workload identity pools and providers, so lets create a GCP project :

```
   gcloud projects create oke-oidc-gcp;
```

Retain the PROJECT_NUMBER.

## 2. enable APIs for the project

Enable the IAM, Resource Manager, Service Account Credentials, and Security Token Service APIs.

   Dont forget verifing that billing is enabled for your oke-oidc-gcp Google Cloud project.

```
   gcloud billing projects link oke-oidc-gcp --billing-account=MY-BILLING-ACCOUNT-ID

```
Once done you can validate it:

```
gcloud billing projects describe oke-oidc-gcp
```

<img width="738" height="102" alt="image" src="https://github.com/user-attachments/assets/5d3baae7-79ec-4182-a8ad-9f41c73a488a" />



## 3.  Enable APIs for your project

   Make sure that the following APIs are enabled:
   
   - Identity and Access Management (IAM) API
   - Cloud Resource Manager API
   - IAM Service Account Credentials API
   - Security Token Service API 

```
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com iamcredentials.googleapis.com sts.googleapis.com
```

## 4. Configure Workload Identity Federation

### - Create workload identity pool

```
gcloud iam workload-identity-pools create "oke-pool" \
  --location="global" \
  --description="Pool for OKE workloads"
```


### - Create identity provider

```
gcloud iam workload-identity-pools providers create-oidc "oke-provider" \
  --location="global" \
  --workload-identity-pool="oke-pool" \
  --issuer-uri="https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/xxxxxxxx/x/oidc/o/12345678-ab44-45c2-bg02-1234354555f4" \
  --attribute-mapping="google.subject=assertion.sub"
```

### - Create Service Account

```
gcloud iam service-accounts create oke-workload-sa \
  --description="Service account for OKE Workloads to access GCP Object Storage" \
  --display-name="OKE Workload Service Account"
```

### - Objective Viewer role for Service Account

The following command grants the service account named oke-workload-sa the Storage Object Viewer role on the entire oke-oidc-gcp project.
We should be able to view buckets and list their files:

```
  gcloud projects add-iam-policy-binding projects/oke-oidc-gcp \
  --member="serviceAccount:oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

### - workloadIdentityUser role for Service Account

This command grants a specific Kubernetes service account (created in point 1.2 and identified by its unique Workload Identity Pool member string) the permission to impersonate a particular Google Cloud service account ( oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com ). The role granted, roles/iam.workloadIdentityUser , is specifically designed for this impersonation, allowing applications running in the Kubernetes cluster using the oke-gcp-sa service account,) to effectively "act as" the Google Cloud service account and access Google Cloud resources based on the Google Cloud service account's permissions, without needing traditional service account keys. 

```
gcloud iam service-accounts add-iam-policy-binding \
  oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member=principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/oke-pool/subject/system:serviceaccount:oke-gcp-ns:oke-gcp-sa \
  --condition=None
```

### - create a credential configuration file

Now, to deploy a Kubernetes workload that can access Google Cloud resources , we need to create a credential configuration file:

```
gcloud iam workload-identity-pools create-cred-config \
    projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/oke-pool/providers/oke-provider \
    --service-account=oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com \
    --credential-source-file=/var/run/service-account/token \
    --credential-source-type=text \
    --sts-location=global \
    --output-file=credential-configuration.json
```

### - create a bucket with a file inside

Now, lets create some resources in GCP:

```
gcloud storage buckets create gs://oke-gcp-bucket ;
echo "File Content" | gcloud storage cp - gs://oke-gcp-bucket/file.txt ;
```

# 3 - Testing

## - create the GCP credential configuration file, as a config map

Return to OKE and lets create the GCP credential configuration file, as a config map in our namespace oke-gcp-ns:

```
kubectl create configmap gcp-credential-configuration \
  --from-file credential-configuration.json \
  --namespace oke-gcp-ns
```

## - creating the pod to test

The following pod will use the  ServiceAccount oke-gcp-sa and ConfigMap gcp-credential-configuration to authenticate to Google Cloud:


```
apiVersion: v1
kind: Pod
metadata:
  name: oke-gcp-pod
  namespace: oke-gcp-ns
spec:
  containers:
  - name: oke-gcp-container
    image: google/cloud-sdk:alpine
    command: ["/bin/sh", "-c", "gcloud auth login --cred-file $GOOGLE_APPLICATION_CREDENTIALS && gcloud auth list && sleep 600"]
    volumeMounts:
    - name: token
      mountPath: "/var/run/service-account"
      readOnly: true
    - name: workload-identity-credential-configuration
      mountPath: "/etc/workload-identity"
      readOnly: true
    env:
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: "/etc/workload-identity/credential-configuration.json"
  serviceAccountName: oke-gcp-sa
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          audience: https://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/oke-pool/providers/oke-provider
          expirationSeconds: 3600
          path: token
  - name: workload-identity-credential-configuration
    configMap:
      name: gcp-credential-configuration
```

Once its running you can first check its logs to validate the result of the authentication process:

```
kubectl -n oke-gcp-ns logs oke-gcp-pod
```

The output expected:

<img width="895" height="194" alt="image" src="https://github.com/user-attachments/assets/db3408e4-4138-4a4b-a05f-ee7b6ae5538c" />


You can then exec into it and list your buckets:

```
kubectl exec oke-gcp-pod --namespace oke-gcp-ns -- gcloud storage ls gs://oke-gcp-bucket/
```

The output should be something like this:

<img width="1064" height="45" alt="image" src="https://github.com/user-attachments/assets/147a25c5-4f84-4cdf-9abe-cbb7e45d2cd5" />


Hope its usefull! :D

Documentation: [Workload Identity Federation with Kubernetes](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-kubernetes#kubernetes)


