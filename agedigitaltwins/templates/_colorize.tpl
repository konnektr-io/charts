{{- define "agedigitaltwins.cluster.color-error" }}
  {{- printf "\033[0;31m%s\033[0m" . -}}
{{- end }}
{{- define "agedigitaltwins.cluster.color-ok" }}
  {{- printf "\033[0;32m%s\033[0m" . -}}
{{- end }}
{{- define "agedigitaltwins.cluster.color-warning" }}
  {{- printf "\033[0;33m%s\033[0m" . -}}
{{- end }}
{{- define "agedigitaltwins.cluster.color-info" }}
  {{- printf "\033[0;34m%s\033[0m" . -}}
{{- end }}