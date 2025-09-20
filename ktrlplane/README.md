# ktrlplane Helm Chart

This chart deploys the ktrlplane solution, including backend, frontend, and PostgreSQL database. Optionally, you can enable either the db-query-operator or http-query-operator charts as dependencies to manage resources with ktrlplane.

## Features

- Deploys backend and frontend services
- Deploys PostgreSQL with persistent storage
- Configurable Auth0 integration
- Configurable ingress
- Optional dependency on db-query-operator or http-query-operator

## Usage

### Install the chart

```sh
helm install ktrlplane ./ktrlplane -f values.yaml
```

### Optional Dependencies

Enable one of the query operator dependencies in `values.yaml`:

```yaml
optionalDependencies:
  dbQueryOperator:
    enabled: true
  httpQueryOperator:
    enabled: false
```

Only one should be enabled at a time.

## Configuration

See `values.yaml` for all configurable options, including images, resources, Auth0, ingress, and database settings.

### Database Options

You can choose to deploy a built-in PostgreSQL database or use an external database (e.g., CloudNativePG):

- **Built-in Postgres**: Set `database.enabled: true` and `database.useExternalSecret: false` (default). The chart will generate a random password and store all DB credentials in a Kubernetes secret. The backend will read DB connection info from this secret.
- **External Database (e.g., cnpg)**: Set `database.enabled: false` and `database.useExternalSecret: true`. Provide the name of the external secret in `database.externalSecretName`. The backend will read DB connection info from this secret. The secret must contain keys: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.

#### Example for using cnpg app secret:

```yaml
database:
  enabled: false
  useExternalSecret: true
  externalSecretName: app # The name of the cnpg-generated secret
```

#### Example for built-in Postgres:

```yaml
database:
  enabled: true
  useExternalSecret: false
```

> **Note:** Passwords are never stored in values.yaml. For built-in Postgres, a random password is generated and stored in a secret. For external DB, you must provide a secret with all required keys.

## Example Access

Add to your hosts file:

```
<ingress-ip> ktrlplane.local
```

Then access: http://ktrlplane.local

## Production Considerations

- Use external database for production
- Implement proper secrets management
- Configure monitoring and logging
- Use official Helm chart for advanced features
