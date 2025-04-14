# Konnektr Helm Charts Repository

Welcome to the Konnektr Helm Charts repository. This repository hosts Helm charts for deploying various applications and services. Currently, it contains the chart for deploying **Konnektr AgeDigitalTwins**. More charts will be added in the future.

## Repository URL

The public address for this Helm repository is:

```
https://charts.konnektr.io
```

## Adding the Repository

To use the charts in this repository, first add it to your Helm client:

```bash
helm repo add konnektr https://charts.konnektr.io
helm repo update
```

## Installing the Konnektr AgeDigitalTwins Chart

To install the **Konnektr AgeDigitalTwins** chart, use the following command:

```bash
helm install my-agedigitaltwins konnektr/agedigitaltwins --values my-values.yaml
```

- Replace `my-agedigitaltwins` with the desired release name.
- Replace `my-values.yaml` with the path to your custom values file, if needed.

## Chart Values

The chart comes with a `values.yaml` file that contains default configurations. You can override these values by providing your own `values.yaml` file during installation.

## Contributing

We welcome contributions to this repository. If you have a new chart to add or improvements to suggest, feel free to open a pull request.

## License

This repository is licensed under the terms of the LICENSE file included in the root directory.
