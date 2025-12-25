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
  {{- if and (kindOf $val | eq "map") (hasKey $val "valueFrom") (hasKey ($val.valueFrom) "secretKeyRef") -}}
- name: {{ $sublabel | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ $val.valueFrom.secretKeyRef.name | quote }}
      key: {{ $val.valueFrom.secretKeyRef.key | quote }}
{{ "" }}
  {{- else if kindOf $val | eq "map" -}}
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