{{/*
Expand the name of the chart.
*/}}
{{- define "agedigitaltwins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agedigitaltwins.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "agedigitaltwins.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agedigitaltwins.labels" -}}
helm.sh/chart: {{ include "agedigitaltwins.chart" . }}
{{ include "agedigitaltwins.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agedigitaltwins.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agedigitaltwins.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}



{{/*
API Image Name
If a custom imageName is available, use it, otherwise use the defaults based on the .Values.type
*/}}
{{- define "agedigitaltwins.api.imageName" -}}
    {{- if .Values.api.imageName -}}
        {{- .Values.api.imageName -}}
    {{- else -}}
        {{- printf "ghcr.io/konnektr-io/pg-age-digitaltwins/agedigitaltwins-api:%s" .Chart.AppVersion -}}
    {{- end }}
{{- end -}}

{{/*
Events Image Name
If a custom imageName is available, use it, otherwise use the defaults based on the .Values.type
*/}}
{{- define "agedigitaltwins.events.imageName" -}}
    {{- if .Values.events.imageName -}}
        {{- .Values.events.imageName -}}
    {{- else -}}
        {{- printf "ghcr.io/konnektr-io/pg-age-digitaltwins/agedigitaltwins-events:%s" .Chart.AppVersion -}}
    {{- end }}
{{- end -}}

{{/*
Whether we need to use TimescaleDB defaults
*/}}
{{- define "agedigitaltwins.cluster.useTimescaleDBDefaults" -}}
{{ and (eq .Values.type "timescaledb") .Values.imageCatalog.create (empty .Values.cluster.imageCatalogRef.name) (empty .Values.imageCatalog.images) (empty .Values.cluster.imageName) }}
{{- end -}}

{{/*
Get the PostgreSQL major version from .Values.version.postgresql
*/}}
{{- define "agedigitaltwins.cluster.postgresqlMajor" -}}
{{ index (regexSplit "\\." (toString .Values.version.postgresql) 2) 0 }}
{{- end -}}

{{/*
Cluster Image Name
If a custom imageName is available, use it, otherwise use the defaults based on the .Values.type
*/}}
{{- define "agedigitaltwins.cluster.imageName" -}}
    {{- if .Values.cluster.imageName -}}
        {{- .Values.cluster.imageName -}}
    {{- else if eq .Values.type "age" -}}
        {{- printf "ghcr.io/konnektr-io/age:%s" .Values.version.age -}}
    {{- else if eq .Values.type "postgresql" -}}
        {{- printf "ghcr.io/cloudnative-pg/postgresql:%s" .Values.version.postgresql -}}
    {{- else if eq .Values.type "postgis" -}}
        {{- printf "ghcr.io/cloudnative-pg/postgis:%s-%s" .Values.version.postgresql .Values.version.postgis -}}
    {{- else -}}
        {{ fail "Invalid cluster type!" }}
    {{- end }}
{{- end -}}

{{/*
Cluster Image
If imageCatalogRef defined, use it, otherwise calculate ordinary imageName.
*/}}
{{- define "agedigitaltwins.cluster.image" }}
{{- if .Values.cluster.imageCatalogRef.name }}
imageCatalogRef:
  apiGroup: postgresql.cnpg.io
  {{- toYaml .Values.cluster.imageCatalogRef | nindent 2 }}
  major: {{ include "agedigitaltwins.cluster.postgresqlMajor" . }}
{{- else if and .Values.imageCatalog.create (not (empty .Values.imageCatalog.images )) }}
imageCatalogRef:
  apiGroup: postgresql.cnpg.io
  kind: ImageCatalog
  name: {{ include "agedigitaltwins.cluster.fullname" . }}
  major: {{ include "agedigitaltwins.cluster.postgresqlMajor" . }}
{{- else if eq (include "agedigitaltwins.cluster.useTimescaleDBDefaults" .) "true" -}}
imageCatalogRef:
  apiGroup: postgresql.cnpg.io
  kind: ImageCatalog
  name: {{ include "agedigitaltwins.cluster.fullname" . }}-timescaledb-ha
  major: {{ include "agedigitaltwins.cluster.postgresqlMajor" . }}
{{- else }}
imageName: {{ include "agedigitaltwins.cluster.imageName" . }}
{{- end }}
{{- end }}

{{/*
Postgres UID
*/}}
{{- define "agedigitaltwins.cluster.postgresUID" -}}
  {{- if ge (int .Values.cluster.postgresUID) 0 -}}
    {{- .Values.cluster.postgresUID }}
  {{- else if and (eq (include "agedigitaltwins.cluster.useTimescaleDBDefaults" .) "true") (eq .Values.type "timescaledb") -}}
    {{- 1000 -}}
  {{- else -}}
    {{- 26 -}}
  {{- end -}}
{{- end -}}

{{/*
Postgres GID
*/}}
{{- define "agedigitaltwins.cluster.postgresGID" -}}
  {{- if ge (int .Values.cluster.postgresGID) 0 -}}
    {{- .Values.cluster.postgresGID }}
  {{- else if and (eq (include "agedigitaltwins.cluster.useTimescaleDBDefaults" .) "true") (eq .Values.type "timescaledb") -}}
    {{- 1000 -}}
  {{- else -}}
    {{- 26 -}}
  {{- end -}}
{{- end -}}

{{/*
Service account name
*/}}
{{- define "agedigitaltwins.serviceAccountName" -}}
{{- if .Values.cluster.serviceAccountTemplate.metadata.name -}}
{{- .Values.cluster.serviceAccountTemplate.metadata.name -}}
{{- else -}}
{{- include "agedigitaltwins.fullname" . -}}
{{- end -}}
{{- end -}}