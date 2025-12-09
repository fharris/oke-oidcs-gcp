# Authorizing Pods in OKE to Access GCP Resources Using OpenID Connect (OIDC) Discovery
Authorizing Pods in OKE to Access GCP Resources Using OpenID Connect (OIDC) Discovery


OKE lets you configure a cluster so that workloads can obtain Kubernetes ServiceAccount tokens from a projected volume. By setting up Workload Identity Federation, you can let workloads use these O[...] 


From the OKE documentation we can read the following explanation:

"You might want application pods running on a Kubernetes cluster you've created with Kubernetes Engine to communicate with cloud service APIs hosted on external cloud providers (such as GCP, AWS, [...]

OpenID Connect (OIDC) is an industry standard to make such integrations more straightforward. OpenID Connect is an identity layer built on top of OAuth 2.0. OpenID Connect supports a discovery pro[...]

Kubernetes Engine provides support for OIDC Discovery, enabling you to build applications that interact with other cloud services without the need to hard code and manually rotate API authentications[...]

At a high level, when you enable OIDC Discovery for a cluster, the application's service account token is authenticated and (if valid) exchanged for an access token. The access token is then used [...]

First thing to acknowledge is that we will need to prepare an OKE cluster with OIDC Discovery enabled and a GCP project with resources to be accessed by workloads in OKE. Lets see how to do this s[...]


## 1. Prepare OKE to support OIDC Discovery

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

<img width="1557" height="370" alt="image" src="https://github.com/user-attachments/assets/fa219535-901a481f93c1-f03fd59be68c" />

<img width="1557" height="370" alt="image" src="https://github.com/user-attachments/assets/6a2eb2c3-f8e0-48c3-8fdb-f1abad078cea" />


retain the **open-id-connect-discovery-endpoint** . We will need it later.

Documentation: [OpenID Connect Discovery - Oracle Cloud Infrastructure Docs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengOpenIDConnect-Discovery.htm)


## 2 - Prepare GCP resources

We will try to run the commands with GCP CLI, but you can always try to do it in the console as well:

1. GCP recommends to use a dedicated project to manage workload identity pools and providers, so lets create a GCP project with GCP Shell:

```
   gcloud projects create oke-oidc-gcp;
   gcloud projects create oke-oidc-gcp;
```

2. Enable the IAM, Resource Manager, Service Account Credentials, and Security Token Service APIs.

   Dont forget verifing that billing is enabled for your oke-oidc-gcp Google Cloud project.

You can do it with gcloud
```
   gcloud billing projects link oke-oidc-gcp --billing-account=MY-BILLING-ACCOUNT-ID

```
or in the console. Once done you can validate it:

```
gcloud billing projects describe oke-oidc-gcp
```

<img width="738" height="102" alt="image" src="https://github.com/user-attachments/assets/5d3baae7-79ec-4182-a8ad-9f41c73a488a" />



3.  Enable APIs for your project

   In the console make sure that the following APIs are enabled:
   
   - Identity and Access Management (IAM) API
   - Cloud Resource Manager API
   - IAM Service Account Credentials API
   - Security Token Service API 

Or with gcloud:

```
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com iamcredentials.googleapis.com sts.googleapis.com
```

4. Configure Workload Identity Federation

 - Create workload identity pool

```
gcloud iam workload-identity-pools create "oke-pool" \
  --location="global" \
  --description="Pool for OKE workloads"
```


- Create identity provider

```
gcloud iam workload-identity-pools providers create-oidc "oke-provider" \
  --location="global" \
  --workload-identity-pool="oke-pool" \
  --issuer-uri="https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/id9y6mi8tcky/b/oidc/o/42180282-ab82-48c3-bf01-5faea66725c4" \
  --attribute-mapping="google.subject=assertion.sub"
```

- Create Service Account

```
gcloud iam service-accounts create oke-workload-sa \
  --description="Service account for OKE Workloads to access GCP Object Storage" \
  --display-name="OKE Workload Service Account"
```

The following command grants the service account named oke-workload-sa the Storage Object Viewer role on the entire oke-oidc-gcp project. 

```
  gcloud projects add-iam-policy-binding projects/oke-oidc-gcp \
  --member="serviceAccount:oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

This command grants a specific Kubernetes service account (identified by its unique Workload Identity Pool member string) the permission to impersonate a particular Google Cloud service account ( oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com ). The role granted, roles/iam.workloadIdentityUser , is specifically designed for this impersonation, allowing applications running in the Kubernetes cluster (using that Kubernetes service account) to effectively "act as" the Google Cloud service account and access Google Cloud resources based on the Google Cloud service account's permissions, without needing traditional service account keys. The --condition=None explicitly states that no additional conditions are placed on this binding.

```
gcloud iam service-accounts add-iam-policy-binding \
  oke-workload-sa@oke-oidc-gcp.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member=principal://iam.googleapis.com/projects/647206516842/locations/global/workloadIdentityPools/oke-pool/subject/system:serviceaccount:oke-gcp-ns:oke-gcp-sa \
  --condition=None
```



