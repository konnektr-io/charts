# Konnektr Helm Charts Repository

Welcome to the Konnektr Helm Charts repository. This repository hosts Helm charts for deploying various applications and services. Currently, it contains the chart for deploying **Konnektr AgeDigitalTwins**. More charts will be added in the future.

## Repository URLs

### Traditional HTTP Repository

The public address for this Helm repository is:

```
https://charts.konnektr.io
```

### OCI Registry

Charts are also available as OCI artifacts in the GitHub Container Registry:

```
oci://ghcr.io/konnektr-io
```

## Installation Methods

### Method 1: Traditional HTTP Repository

Add the repository to your Helm client:

```bash
helm repo add konnektr https://charts.konnektr.io
helm repo update
```

Install a chart:

```bash
helm install my-agedigitaltwins konnektr/agedigitaltwins --values my-values.yaml
```

### Method 2: OCI Registry (Recommended)

Install directly from the OCI registry without adding a repository:

```bash
# Install AgeDigitalTwins chart
helm install my-agedigitaltwins oci://ghcr.io/konnektr-io/agedigitaltwins

# Install other charts
helm install my-ktrlplane oci://ghcr.io/konnektr-io/ktrlplane
helm install my-db-operator oci://ghcr.io/konnektr-io/db-query-operator
helm install my-webhook oci://ghcr.io/konnektr-io/cert-manager-porkbun-webhook
```

### Benefits of OCI Method

- **No repository management**: Install directly without adding repositories
- **Better security**: Leverage GitHub's authentication and package permissions
- **Unified storage**: Charts and container images in the same registry
- **Improved caching**: Better performance and reliability

## Available Charts

| Chart Name                     | Description                                            |
| ------------------------------ | ------------------------------------------------------ |
| `agedigitaltwins`              | Digital Twins for Apache AGE API and database          |
| `ktrlplane`                    | Control plane solution (backend, frontend, PostgreSQL) |
| `db-query-operator`            | Database Query Kubernetes operator                     |
| `cert-manager-porkbun-webhook` | Porkbun solver for Cert Manager                        |

## Chart Values

The chart comes with a `values.yaml` file that contains default configurations. You can override these values by providing your own `values.yaml` file during installation.

## Contributing

We welcome contributions to this repository. If you have a new chart to add or improvements to suggest, feel free to open a pull request.

## License

This repository is licensed under the terms of the LICENSE file included in the root directory.
