# ACME DNS Server Helm Chart
A Helm chart for [acme-dns server](https://github.com/acme-dns/acme-dns).

This Helm chart runs [acme-dns](https://github.com/acme-dns/acme-dns) as StatefulSet with a SQLite database.
Using PostgreSql as database is currently not supported by this Helm chart.

## Installation
The installation is done as follows:
```shell
$ helm repo add acme-dns https://max-pfeiffer.github.io/acme-dns-server-helm-chart
$ helm install acme-dns acme-dns/acme-dns --values your_values.yaml --namespace yournamespace 
```

## Configuration
In the Kubernetes context you usually use [acme-dns](https://github.com/acme-dns/acme-dns) in conjunction with [cert-manager](https://cert-manager.io/).
This [process is well described in cert-manager documentation](https://cert-manager.io/docs/configuration/acme/dns01/acme-dns/).

### Running acme-dns together with cert-manager in the same Kubernetes cluster
When you run [acme-dns](https://github.com/acme-dns/acme-dns) in the same cluster and namespace as your cert-manager
instance, you don't need to expose the [acme-dns](https://github.com/acme-dns/acme-dns) API with an Ingress or HTTPRoute.
It is also acceptable not to use TLS for the API endpoints. A config for this use case would look like this:
```yaml
services:
  api:
    type: ClusterIP
    ports:
      api: 80
config: |
  [general]
  # DNS interface. Note that systemd-resolved may reserve port 53 on 127.0.0.53
  # In this case acme-dns will error out and you will need to define the listening interface
  # for example: listen = "127.0.0.1:53"
  listen = "0.0.0.0:53"  
  [api]
  # listen ip eg. 127.0.0.1
  ip = "0.0.0.0"  
  # listen port, eg. 443 for default HTTPS
  port = "80"
  # possible values: "letsencrypt", "letsencryptstaging", "cert", "none"
  tls = "none"
```
Please note that the DNS server listens on all network interfaces `listen = "0.0.0.0:53"`. When you are running
[acme-dns](https://github.com/acme-dns/acme-dns) in a container this is necessary. Otherwise, it doesn't pick up any connections.

You only need to expose the DNS server part of [acme-dns](https://github.com/acme-dns/acme-dns) to the internet. You can use the `acme-dns-dns` Service
for this. By default, it is of type `LoadBalancer` and depending on your configuration will become assigned an external
IP address automatically. You cannot use an Ingress or HTTPRoute for this as DNS is mainly UDP traffic.
[UDPRoute is currently still in the experimental channel](https://gateway-api.sigs.k8s.io/concepts/api-overview/?h=udproute#tcproute-and-udproute)
of Gateway API.

A `ClusterIssuer` for cert-manager would look like this:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns01
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns01-cluster-issuer-account-key    
    solvers:
    - dns01:
        acmeDNS:
          host: http://acme-dns-api
          accountSecretRef:
            name: acme-dns
            key: acmedns.json
```
It uses the `acme-dns-api` Service which is available under this URL when you install the [acme-dns](https://github.com/acme-dns/acme-dns) in the same
namespace as [cert-manager](https://cert-manager.io/).

When you use a `ClusterIssuer`, please be aware that you need to 
[put the `acme-dns` Secret inside the cert-manager's namespace for this to work](https://cert-manager.io/docs/configuration/acme/dns01/acme-dns/).