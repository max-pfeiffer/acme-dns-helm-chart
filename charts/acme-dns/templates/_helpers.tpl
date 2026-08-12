{{/*
Expand the name of the chart.
*/}}
{{- define "acme-dns.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "acme-dns.fullname" -}}
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
{{- define "acme-dns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "acme-dns.labels" -}}
helm.sh/chart: {{ include "acme-dns.chart" . }}
{{ include "acme-dns.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "acme-dns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "acme-dns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Deployment used when database.engine is "postgres".
Deliberately distinct from the StatefulSet name: Helm cannot change the kind of
an existing resource in place, so a release switching from SQLite to PostgreSQL
would otherwise fail with an immutable-field error.
*/}}
{{- define "acme-dns.deploymentName" -}}
{{- printf "%s-server" (include "acme-dns.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector for the API and DNS Services.
With SQLite the workload is a single-replica StatefulSet whose per-pod PVC holds
the database file, so the Services are pinned to pod 0. With PostgreSQL every
replica is interchangeable and shares one database, so the Services select all
pods and traffic is load balanced across them.
*/}}
{{- define "acme-dns.serviceSelector" -}}
{{- if eq .Values.database.engine "sqlite" -}}
statefulset.kubernetes.io/pod-name: {{ include "acme-dns.fullname" . }}-0
{{- else -}}
{{- include "acme-dns.selectorLabels" . -}}
{{- end -}}
{{- end }}

{{/*
Fail on value combinations that cannot work.
*/}}
{{- define "acme-dns.validateValues" -}}
{{- if and (eq .Values.database.engine "sqlite") (gt (int .Values.replicaCount) 1) -}}
{{- fail "database.engine=\"sqlite\" supports replicaCount=1 only: every replica gets its own PersistentVolumeClaim and therefore its own, independent database file. Set database.engine=\"postgres\" (and point [database].connection in `config` at PostgreSQL) to run more than one replica." -}}
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "acme-dns.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "acme-dns.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
