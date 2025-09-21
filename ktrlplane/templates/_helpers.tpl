{{/*
Expand the name of the chart.
*/}}
{{- define "ktrlplane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ktrlplane.fullname" -}}
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
{{- define "ktrlplane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ktrlplane.labels" -}}
helm.sh/chart: {{ include "ktrlplane.chart" . }}
{{ include "ktrlplane.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ktrlplane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ktrlplane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Stripe secret name
*/}}
{{- define "ktrlplane.stripeName" -}}
{{- if .Values.stripe.useExternalSecret }}
{{- .Values.stripe.externalSecretName }}
{{- else }}
{{- printf "%s-stripe-secret" (include "ktrlplane.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Config ConfigMap name
*/}}
{{- define "ktrlplane.configName" -}}
{{- printf "%s-config" (include "ktrlplane.fullname" .) }}
{{- end }}