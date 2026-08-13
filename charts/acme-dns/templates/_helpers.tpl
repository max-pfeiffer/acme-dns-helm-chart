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
Base for the workload names below. The fullname is truncated well short of 63
characters first so that appending a suffix cannot push the two workload names
into the same truncated string, and so that the StatefulSet's pod names
(<name>-<ordinal>) stay within the 63 character DNS label limit.
*/}}
{{- define "acme-dns.workloadNameBase" -}}
{{- include "acme-dns.fullname" . | trunc 50 | trimSuffix "-" }}
{{- end }}

{{/*
Name of the StatefulSet used when database.engine is "sqlite".
*/}}
{{- define "acme-dns.statefulSetName" -}}
{{- printf "%s-stateful" (include "acme-dns.workloadNameBase" .) }}
{{- end }}

{{/*
Name of the Deployment used when database.engine is "postgres".
Deliberately distinct from the StatefulSet name: Helm cannot change the kind of
an existing resource in place, so a release switching from SQLite to PostgreSQL
would otherwise fail with an immutable-field error.
*/}}
{{- define "acme-dns.deploymentName" -}}
{{- printf "%s-stateless" (include "acme-dns.workloadNameBase" .) }}
{{- end }}

{{/*
Selector for the API and DNS Services.
With SQLite the workload is a single-replica StatefulSet whose per-pod PVC holds
the database file, so the Services are pinned to pod 0. With PostgreSQL every
replica is interchangeable and shares one database, so the Services select all
pods and traffic is load balanced across them. The app labels are part of the
selector in both cases, so a same-named pod from another workload cannot be
picked up.
*/}}
{{- define "acme-dns.serviceSelector" -}}
{{- include "acme-dns.selectorLabels" . }}
{{- if eq .Values.database.engine "sqlite" }}
statefulset.kubernetes.io/pod-name: {{ include "acme-dns.statefulSetName" . }}-0
{{- end }}
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

{{/*
Pod template shared by the StatefulSet (sqlite) and the Deployment (postgres).
The only difference between the two is the SQLite volume, which comes from the
StatefulSet's volumeClaimTemplate and therefore only exists for that engine.
*/}}
{{- define "acme-dns.podTemplate" -}}
metadata:
  annotations:
    # acme-dns parses config.cfg once, at process start. Without this checksum a
    # change to `config` would update the Secret but leave the pod template
    # byte-identical, so `helm upgrade` would succeed while the pods kept
    # running the old configuration.
    checksum/config: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
    {{- with .Values.podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "acme-dns.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "acme-dns.serviceAccountName" . }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ .Chart.Name }}
      {{- with .Values.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      ports:
        - name: api
          containerPort: {{ .Values.containerPorts.api }}
          protocol: TCP
        - name: dns-tcp
          containerPort: {{ .Values.containerPorts.dnsTcp }}
          protocol: TCP
        - name: dns-udp
          containerPort: {{ .Values.containerPorts.dnsUdp }}
          protocol: UDP
      {{- with .Values.livenessProbe }}
      livenessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumeMounts:
        - name: config
          mountPath: "/etc/acme-dns"
          readOnly: true
        {{- if eq .Values.database.engine "sqlite" }}
        - name: sqlite
          mountPath: "/var/lib/acme-dns"
        {{- end }}
        - name: tmp
          mountPath: "/tmp"
        - name: home
          mountPath: "/root"
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- range . }}
    - {{ toYaml . | nindent 6 | trim }}
      {{- if not .labelSelector }}
      labelSelector:
        matchLabels:
          {{- include "acme-dns.selectorLabels" $ | nindent 10 }}
      {{- end }}
    {{- end }}
  {{- end }}
  volumes:
    - name: config
      secret:
        secretName: {{ include "acme-dns.fullname" . }}
    - name: tmp
      emptyDir: {}
    # Writable home dir for the container's WORKDIR (/root); used e.g. as the
    # default relative path for acme_cache_dir when tls = "letsencrypt". Note
    # that this is per-pod and lost on restart: with more than one replica,
    # terminate TLS elsewhere and use tls = "none" or "cert".
    - name: home
      emptyDir: {}
{{- end }}
