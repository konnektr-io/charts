{{/*
Expand the name of the chart.
*/}}
{{- define "graph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "graph.fullname" -}}
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
{{- define "graph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "graph.labels" -}}
helm.sh/chart: {{ include "graph.chart" . }}
{{ include "graph.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "graph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "graph.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API Image Name
If a custom imageName is available, use it, otherwise use the defaults based on the .Values.type
*/}}
{{- define "graph.api.imageName" -}}
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
{{- define "graph.events.imageName" -}}
    {{- if .Values.events.imageName -}}
        {{- .Values.events.imageName -}}
    {{- else -}}
        {{- printf "ghcr.io/konnektr-io/pg-age-digitaltwins/agedigitaltwins-events:%s" .Chart.AppVersion -}}
    {{- end }}
{{- end -}}

{{/*
API service account name
*/}}
{{- define "graph.api.serviceAccountName" -}}
{{- if .Values.api.serviceAccountName -}}
{{- .Values.api.serviceAccountName -}}
{{- else if and .Values.cluster.cluster.erviceAccountTemplate (hasKey .Values.cluster.cluster.serviceAccountTemplate "metadata") .Values.cluster.cluster.serviceAccountTemplate.metadata.name -}}
{{- .Values.cluster.cluster.serviceAccountTemplate.metadata.name -}}
{{- else -}}
{{- include "graph.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Events service account name
*/}}
{{- define "graph.events.serviceAccountName" -}}
{{- if .Values.events.serviceAccountName -}}
{{- .Values.events.serviceAccountName -}}
{{- else if and .Values.cluster.cluster.serviceAccountTemplate (hasKey .Values.cluster.cluster.serviceAccountTemplate "metadata") .Values.cluster.cluster.serviceAccountTemplate.metadata.name -}}
{{- .Values.cluster.serviceAccountTemplate.metadata.name -}}
{{- else -}}
{{- include "graph.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "toPascalCase" -}}
{{- $str := . -}}
{{- $components := split "_" $str -}}
{{- $result := "" -}}
{{- range $components -}}
{{- $result = printf "%s%s" $result (title $) -}}
{{- end -}}
{{- $result -}}
{{- end -}}

{{- define "recurseFlattenMap" -}}
{{- $map := first . -}}
{{- $label := last . -}}
{{- range $key, $val := $map -}}
  {{- $sublabel := list $label ($key | include "toPascalCase") | compact | join "__" -}}
  {{- if kindOf $val | eq "map" -}}
    {{- list $val $sublabel | include "recurseFlattenMap" -}}
  {{- else if kindOf $val | eq "slice" -}}
    {{- range $index, $item := $val -}}
      {{- if kindOf $item | eq "map" -}}
        {{- list $item (printf "%s__%d" $sublabel $index) | include "recurseFlattenMap" -}}
      {{- else -}}
- name: {{ printf "%s__%d" $sublabel $index | quote }}
  value: {{ $item | quote }}
      {{- end -}}
    {{- end -}}
  {{- else -}}
- name: {{ $sublabel | quote }}
  value: {{ $val | quote }}
{{ end -}}
{{- end -}}
{{- end -}}