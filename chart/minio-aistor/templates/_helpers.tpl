{{/*
Expand the name of the chart.
*/}}
{{- define "minio-aistor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "minio-aistor.fullname" -}}
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
Normalize pools from either dictionary (GCP Marketplace dot notation) or array format.
GCP Marketplace schema with dot notation like "pools.0.name" creates a dictionary with
string keys ("0", "1", etc) instead of an array. This helper normalizes both formats.

Input: The full Values object
Output: A list of pool objects, sorted by key if input was a dictionary

Usage in templates:
  {{- $pools := include "minio-aistor.normalizePools" . | fromYaml }}
  {{- range $pools }}
    servers: {{ .servers }}
  {{- end }}
*/}}
{{- define "minio-aistor.normalizePools" -}}
{{- $pools := index .Values "aistor-objectstore" "objectStore" "pools" | default dict }}
{{- $poolsList := list }}
{{- if kindIs "slice" $pools }}
  {{- /* Already an array, return as-is */}}
  {{- $poolsList = $pools }}
{{- else if kindIs "map" $pools }}
  {{- /* Dictionary format - need to convert to array */}}
  {{- /* Sort keys numerically and build array */}}
  {{- $keys := keys $pools | sortAlpha }}
  {{- range $key := $keys }}
    {{- $pool := index $pools $key }}
    {{- $poolsList = append $poolsList $pool }}
  {{- end }}
{{- end }}
{{- $poolsList | toYaml }}
{{- end }}

{{/*
Get the first pool, handling both dictionary and array formats.
This is a convenience helper for accessing pool 0 properties.

Usage:
  {{- $firstPool := include "minio-aistor.firstPool" . | fromYaml }}
  servers: {{ $firstPool.servers }}
*/}}
{{- define "minio-aistor.firstPool" -}}
{{- $pools := index .Values "aistor-objectstore" "objectStore" "pools" | default dict }}
{{- if kindIs "slice" $pools }}
  {{- /* Array format - index directly */}}
  {{- if gt (len $pools) 0 }}
    {{- index $pools 0 | toYaml }}
  {{- else }}
    {{- dict | toYaml }}
  {{- end }}
{{- else if kindIs "map" $pools }}
  {{- /* Dictionary format - get key "0" */}}
  {{- if hasKey $pools "0" }}
    {{- index $pools "0" | toYaml }}
  {{- else }}
    {{- dict | toYaml }}
  {{- end }}
{{- else }}
  {{- dict | toYaml }}
{{- end }}
{{- end }}
