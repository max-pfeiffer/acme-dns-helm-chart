# acme-dns-server-helm-chart
A Helm chart for [acme-dns server](https://github.com/joohoi/acme-dns).

## Installation

## Usage
### Running it in the same Kubernetes cluster together with cert-manager
When you run [acme-dns](https://github.com/joohoi/acme-dns) in the same cluster and namespace as your cert-manager
instance, you don't need to expose the [acme-dns](https://github.com/joohoi/acme-dns) API with an Ingress or HTTPRoute.
It is also acceptable not to use TLS for the API endpoints. A config for this use case would look like this:
```yaml
ports:
  api: 80
services:
  api:
    type: ClusterIP
config: |
  [api]
  # listen port, eg. 443 for default HTTPS
  port = "80"
  # possible values: "letsencrypt", "letsencryptstaging", "cert", "none"
  tls = "none"
```

A `ClusterIssuer` for cert-manager would look like this:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns01
spec:
  acme:
    solvers:
    - dns01:
        acmeDNS:
          host: http://acme-dns-api
          accountSecretRef:
            name: acme-dns
            key: acmedns.json
```
When you use a `ClusterIssuer`, please be aware that you need to 
[put the `acme-dns` Secret inside the cert-manager's namespace for this to work](https://cert-manager.io/docs/configuration/acme/dns01/acme-dns/).