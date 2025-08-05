# Migration from In-Tree Barman to Barman Cloud Plugin

This document describes how to migrate from the deprecated in-tree Barman Object Store implementation to the new Barman Cloud Plugin for CloudNative-PG 1.26+.

## Overview

Starting with CloudNative-PG 1.26, the in-tree Barman Object Store implementation is deprecated and will be removed in a future release. The recommended approach is to use the [Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/) instead.

## Prerequisites

Before migrating to the Barman Cloud Plugin, ensure the following requirements are met:

### 1. CloudNative-PG Version

Verify you're running CloudNative-PG 1.26 or newer:

```console
kubectl get deployment -n cnpg-system cnpg-controller-manager -o yaml | grep ghcr.io/cloudnative-pg/cloudnative-pg
```

### 2. cert-manager

Ensure cert-manager is installed and available:

```console
# Install cert-manager if not already installed
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

# Verify cert-manager is ready (requires cmctl tool)
cmctl check api
```

### 3. Install the Barman Cloud Plugin

Install the plugin in the same namespace as CloudNative-PG (typically `cnpg-system`):

```console
kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.4.0/manifest.yaml

# Verify the installation
kubectl rollout status deployment -n cnpg-system barman-cloud
```

**Important Notes:**

- The plugin must be installed in the same namespace as the CloudNative-PG operator
- Make sure the operator's listening namespaces are properly configured
- For the latest version, check the [plugin releases page](https://github.com/cloudnative-pg/plugin-barman-cloud/releases)

## Migration Steps

### Step 1: Update Your Values Configuration

1. **Enable the Barman Cloud Plugin**:

   ```yaml
   cluster:
     plugins:
       - name: barman-cloud.cloudnative-pg.io
         isWALArchiver: true
         parameters:
           barmanObjectName: backup-store
   ```

2. **Create an ObjectStore Resource**:

   ```yaml
   objectStore:
     create: true
     name: backup-store
     configuration:
       destinationPath: "s3://my-backup-bucket/path"
       endpointURL: "https://s3.amazonaws.com" # Optional, uses default if empty
       s3Credentials:
         accessKeyId:
           name: backup-credentials
           key: ACCESS_KEY_ID
         secretAccessKey:
           name: backup-credentials
           key: ACCESS_SECRET_KEY
       wal:
         compression: gzip
         encryption: AES256
         maxParallel: 1
       data:
         compression: gzip
         encryption: AES256
         jobs: 2
     retentionPolicy: "30d"
   ```

3. **Update Backup Method**:

   ```yaml
   backups:
     enabled: true
     method: plugin # Changed from barmanObjectStore
   ```

4. **Update Scheduled Backups**:
   ```yaml
   backups:
     scheduledBackups:
       - name: daily-backup
         schedule: "0 0 0 * * *"
         method: plugin # Changed from volumeSnapshot or barmanObjectStore
         pluginConfiguration:
           name: barman-cloud.cloudnative-pg.io
           parameters:
             barmanObjectName: backup-store
         backupOwnerReference: self
   ```

### Step 2: Legacy Configuration Migration

If you're migrating from the legacy `barmanObjectStore` method, you can reuse most of your existing configuration:

**Before (Legacy)**:

```yaml
backups:
  method: barmanObjectStore
  destinationPath: "s3://my-backup-bucket/path"
  provider: s3
  s3:
    region: "us-east-1"
    bucket: "my-backup-bucket"
    accessKey: "AKIA..."
    secretKey: "secret..."
  wal:
    compression: gzip
    encryption: AES256
  data:
    compression: gzip
    encryption: AES256
  retentionPolicy: "30d"
```

**After (Plugin)**:

```yaml
backups:
  method: plugin

cluster:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: backup-store

objectStore:
  create: true
  name: backup-store
  configuration:
    destinationPath: "s3://my-backup-bucket/path"
    s3Credentials:
      accessKeyId:
        name: backup-credentials
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: backup-credentials
        key: ACCESS_SECRET_KEY
    wal:
      compression: gzip
      encryption: AES256
    data:
      compression: gzip
      encryption: AES256
  retentionPolicy: "30d"
```

## Supported Backup Methods

This chart supports three backup methods:

### 1. Volume Snapshots (Default, Recommended)

```yaml
backups:
  method: volumeSnapshot
  volumeSnapshot:
    className: "csi-driver-class"
```

### 2. Legacy Barman Object Store (Deprecated)

```yaml
backups:
  method: barmanObjectStore
  # ... legacy configuration
```

### 3. Barman Cloud Plugin (Recommended for Object Storage)

```yaml
backups:
  method: plugin

cluster:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: my-objectstore

objectStore:
  create: true
  name: my-objectstore
  # ... configuration
```

## Benefits of the Plugin Approach

1. **Future-proof**: Recommended approach for CloudNative-PG 1.26+
2. **Decoupled**: ObjectStore resources can be shared across clusters
3. **Enhanced features**: Better performance and reliability
4. **Active development**: Ongoing improvements and bug fixes

## Backward Compatibility

This chart maintains backward compatibility with all three methods:

- Existing `volumeSnapshot` configurations continue to work unchanged
- Legacy `barmanObjectStore` configurations are still supported but deprecated
- New `plugin` method provides the modern approach

## Troubleshooting

### Plugin Not Available

If you see errors about the plugin not being available:

1. **Check plugin installation:**

   ```console
   kubectl get deployment -n cnpg-system barman-cloud
   kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud
   ```

2. **Verify plugin logs:**

   ```console
   kubectl logs -n cnpg-system deployment/barman-cloud
   ```

3. **Check CloudNative-PG operator logs:**
   ```console
   kubectl logs -n cnpg-system deployment/cnpg-controller-manager
   ```

### ObjectStore Resource Issues

If ObjectStore resources are not being created or recognized:

1. **Check CRD installation:**

   ```console
   kubectl get crd objectstores.barmancloud.cnpg.io
   ```

2. **Verify ObjectStore status:**
   ```console
   kubectl get objectstore -n <your-namespace>
   kubectl describe objectstore <objectstore-name> -n <your-namespace>
   ```

### Credential Issues

If you encounter authentication errors:

1. **Verify secrets exist:**

   ```console
   kubectl get secret <credential-secret-name> -n <your-namespace>
   ```

2. **Check secret contents:**

   ```console
   kubectl get secret <credential-secret-name> -n <your-namespace> -o yaml
   ```

3. **Ensure correct key names** (ACCESS_KEY_ID, ACCESS_SECRET_KEY for S3)

### Migration Validation

After migration, verify the setup:

1. **Check cluster status:**

   ```console
   kubectl get cluster -n <your-namespace>
   kubectl describe cluster <cluster-name> -n <your-namespace>
   ```

2. **Verify WAL archiving:**

   ```console
   kubectl logs -n <your-namespace> <cluster-pod-name> -c postgres
   ```

3. **Test backup creation:**
   ```console
   kubectl get scheduledbackup -n <your-namespace>
   kubectl get backup -n <your-namespace>
   ```

## References

- [Barman Cloud Plugin Documentation](https://cloudnative-pg.io/plugin-barman-cloud/)
- [Migration Guide](https://cloudnative-pg.io/plugin-barman-cloud/docs/0.4.0/migration/)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/)
