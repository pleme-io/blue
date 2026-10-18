{{- define "greeter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "greeter.fullname" -}}
{{- if contains (include "greeter.name" .) .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "greeter.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "greeter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "greeter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greeter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "greeter.labels" -}}
helm.sh/chart: {{ include "greeter.chart" . }}
{{ include "greeter.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
