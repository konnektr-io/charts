{{- define "agedigitaltwins.cluster.backup" -}}
{{- if .Values.backups.enabled }}
backup:
  target: "prefer-standby"
  {{- if ne .Values.backups.method "plugin" }}
  retentionPolicy: {{ .Values.backups.retentionPolicy }}
  {{- end }}
  {{- if eq .Values.backups.method "barmanObjectStore" }}
  barmanObjectStore:
    wal:
      compression: {{ .Values.backups.wal.compression }}
      encryption: {{ .Values.backups.wal.encryption }}
      maxParallel: {{ .Values.backups.wal.maxParallel }}
    data:
      compression: {{ .Values.backups.data.compression }}
      encryption: {{ .Values.backups.data.encryption }}
      jobs: {{ .Values.backups.data.jobs }}

    {{- $d := dict "chartFullname" (include "agedigitaltwins.fullname" .) "scope" .Values.backups "secretPrefix" "backup" }}
    {{- include "agedigitaltwins.cluster.barmanObjectStoreConfig" $d | nindent 2 }}
  {{- else if eq .Values.backups.method "volumeSnapshot" }}
  volumeSnapshot:
    {{- toYaml .Values.backups.volumeSnapshot | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
