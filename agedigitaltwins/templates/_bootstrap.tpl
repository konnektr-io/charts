{{- define "agedigitaltwins.cluster.bootstrap" -}}
{{- if eq .Values.mode "standalone" }}
bootstrap:
  initdb:
    {{- with .Values.cluster.initdb }}
        {{- with (omit . "postInitApplicationSQL" "owner") }}
            {{- . | toYaml | nindent 4 }}
        {{- end }}
    {{- end }}
    {{- if .Values.cluster.initdb.owner }}
    owner: {{ tpl .Values.cluster.initdb.owner . }}
    {{- end }}
    postInitApplicationSQL:
      {{- if eq .Values.type "age" }}
      - CREATE EXTENSION age;
      - GRANT SELECT ON ag_catalog.ag_graph TO {{ default "app" .Values.cluster.initdb.owner }};
      - GRANT USAGE ON SCHEMA ag_catalog TO {{ default "app" .Values.cluster.initdb.owner }};
      - ALTER USER {{ default "app" .Values.cluster.initdb.owner }} REPLICATION;
      - CREATE PUBLICATION age_pub FOR ALL TABLES;
      - SELECT * FROM pg_create_logical_replication_slot('age_slot', 'pgoutput');
      {{- else if eq .Values.type "postgis" }}
      - CREATE EXTENSION IF NOT EXISTS postgis;
      - CREATE EXTENSION IF NOT EXISTS postgis_topology;
      - CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
      - CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
      {{- else if eq .Values.type "timescaledb" }}
      - CREATE EXTENSION IF NOT EXISTS timescaledb;
      {{- end }}
      {{- with .Values.cluster.initdb }}
          {{- range .postInitApplicationSQL }}
            {{- printf "- %s" . | nindent 6 }}
          {{- end -}}
      {{- end -}}
    {{- end }}
{{- else if eq .Values.mode "recovery" -}}
bootstrap:
{{- if eq .Values.recovery.method "pg_basebackup" }}
  pg_basebackup:
    source: pgBaseBackupSource
    {{ with .Values.recovery.pgBaseBackup.database }}
    database: {{ . }}
    {{- end }}
    {{ with .Values.recovery.pgBaseBackup.owner }}
    owner: {{ . }}
    {{- end }}
    {{ with .Values.recovery.pgBaseBackup.secret }}
    secret:
      {{- toYaml . | nindent 6 }}
    {{- end }}

externalClusters:
- name: pgBaseBackupSource
  connectionParameters:
    host: {{ .Values.recovery.pgBaseBackup.source.host | quote }}
    port: {{ .Values.recovery.pgBaseBackup.source.port | quote }}
    user: {{ .Values.recovery.pgBaseBackup.source.username | quote }}
    dbname: {{ .Values.recovery.pgBaseBackup.source.database | quote }}
    sslmode: {{ .Values.recovery.pgBaseBackup.source.sslMode | quote }}
  {{- if .Values.recovery.pgBaseBackup.source.passwordSecret.name }}
  password:
    name: {{ default (printf "%s-pg-basebackup-password" (include "agedigitaltwins.fullname" .)) .Values.recovery.pgBaseBackup.source.passwordSecret.name }}
    key: {{ .Values.recovery.pgBaseBackup.source.passwordSecret.key }}
  {{- end }}
  {{- if .Values.recovery.pgBaseBackup.source.sslKeySecret.name }}
  sslKey:
    name: {{ .Values.recovery.pgBaseBackup.source.sslKeySecret.name }}
    key: {{ .Values.recovery.pgBaseBackup.source.sslKeySecret.key }}
  {{- end }}
  {{- if .Values.recovery.pgBaseBackup.source.sslCertSecret.name }}
  sslCert:
    name: {{ .Values.recovery.pgBaseBackup.source.sslCertSecret.name }}
    key: {{ .Values.recovery.pgBaseBackup.source.sslCertSecret.key }}
  {{- end }}
  {{- if .Values.recovery.pgBaseBackup.source.sslRootCertSecret.name }}
  sslRootCert:
    name: {{ .Values.recovery.pgBaseBackup.source.sslRootCertSecret.name }}
    key: {{ .Values.recovery.pgBaseBackup.source.sslRootCertSecret.key }}
  {{- end }}

{{- else }}
  recovery:
    {{- with .Values.recovery.pitrTarget.time }}
    recoveryTarget:
      targetTime: {{ . }}
    {{- end }}
    {{- if eq .Values.recovery.method "backup" }}
    backup:
      name: {{ .Values.recovery.backupName }}
    {{- else if eq .Values.recovery.method "object_store" }}
    source: objectStoreRecoveryCluster
    {{- end }}

externalClusters:
  - name: objectStoreRecoveryCluster
    barmanObjectStore:
      serverName: {{ .Values.recovery.clusterName }}
      {{- $d := dict "chartFullname" (include "agedigitaltwins.fullname" .) "scope" .Values.recovery "secretPrefix" "recovery" -}}
      {{- include "agedigitaltwins.cluster.barmanObjectStoreConfig" $d | nindent 4 }}
{{- end }}
{{-  else }}
  {{ fail "Invalid cluster mode!" }}
{{- end }}
{{- end }}