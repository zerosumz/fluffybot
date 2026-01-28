{{/*
Expand the name of the chart.
*/}}
{{- define "fluffybot.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "fluffybot.fullname" -}}
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
{{- define "fluffybot.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fluffybot.labels" -}}
helm.sh/chart: {{ include "fluffybot.chart" . }}
{{ include "fluffybot.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fluffybot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fluffybot.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Webhook selector labels
*/}}
{{- define "fluffybot.webhook.selectorLabels" -}}
app: {{ .Values.webhook.name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fluffybot.serviceAccountName" -}}
{{- if .Values.rbac.create }}
{{- default .Values.rbac.serviceAccountName .Values.rbac.serviceAccountName }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Webhook image
*/}}
{{- define "fluffybot.webhookImage" -}}
{{- printf "%s/webhook:%s" .Values.image.registry .Values.image.webhookTag }}
{{- end }}

{{/*
Worker image
*/}}
{{- define "fluffybot.workerImage" -}}
{{- printf "%s/worker:%s" .Values.image.registry .Values.image.workerTag }}
{{- end }}
