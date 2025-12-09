# oke-oidcs-gcp
Authorizing Pods in OKE to Access GCP Resources Using OpenID Connect (OIDC) Discovery


OKE lets you configure a cluster so that workloads can obtain Kubernetes ServiceAccount tokens from a projected volume. By setting up Workload Identity Federation, you can let workloads use these OKE ServiceAccount tokens to authenticate to GCP resources. This exercise can be applied to other cloud providers supporting OIDC Discovery.


From the OKE documentation we can read the following explanation:

"You might want application pods running on a Kubernetes cluster you've created with Kubernetes Engine to communicate with cloud service APIs hosted on external cloud providers (such as GCP, AWS, and Azure). To ensure the security of the resources hosted by an external cloud provider, the application running on the cluster must authenticate and manage identity. However, managing credentials directly can be a cumbersome process for applications, and key rotation is a manual process with considerable overhead.

OpenID Connect (OIDC) is an industry standard to make such integrations more straightforward. OpenID Connect is an identity layer built on top of OAuth 2.0. OpenID Connect supports a discovery protocol (often referred to as "OIDC Discovery") that uses an OpenID Provider Configuration document (known as the "discovery document") to authenticate applications.

Kubernetes Engine provides support for OIDC Discovery, enabling you to build applications that interact with other cloud services without the need to hard code and manually rotate API authentication keys. You can optionally enable OIDC Discovery when you create or update an enhanced cluster with Kubernetes Engine.

At a high level, when you enable OIDC Discovery for a cluster, the application's service account token is authenticated and (if valid) exchanged for an access token. The access token is then used to authenticate the application with the API on the external cloud provider."

First thing to acknowledge is that we will need to prepare an OKE cluster with OIDC Discovery enabled and GCP project with resources. Lets see how to do this step by step.

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

If you want to confirm, run the following command:

```
oci ce cluster get --cluster-id ocid1.cluster.oc1.iad.aaaaaaaaaf______jrd  | grep -C 'open-id-connect-discovery'
```

You should see something like the image below:

<img width="1557" height="370" alt="image" src="https://github.com/user-attachments/assets/fa219535-901a-481f-93c1-f03fd59be68c" />

retain the **open-id-connect-discovery-endpoint** . We will need it later.




