{{/* Common labels */}}
{{- define "shipgrid.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: shipgrid
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Per-service selector labels (stable subset). Call with (dict "name" $name "root" $) */}}
{{- define "shipgrid.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/* Pod labels = selector labels + part-of (so NetworkPolicy + `kubectl -l
     part-of=shipgrid` match the pods, not just object metadata). */}}
{{- define "shipgrid.podLabels" -}}
{{ include "shipgrid.selectorLabels" . }}
app.kubernetes.io/part-of: shipgrid
{{- end -}}

{{/* Fully-qualified image for a service block. Call with (dict "svc" $svc "root" $) */}}
{{- define "shipgrid.image" -}}
{{- $reg := .root.Values.global.registry -}}
{{- printf "%s/%s:%s" $reg .svc.image (.svc.tag | toString) -}}
{{- end -}}

{{/* Resource name for a service: <release>-<svc> */}}
{{- define "shipgrid.svcName" -}}
{{- printf "%s-%s" .root.Release.Name .name -}}
{{- end -}}

{{/* Checksum of the shared secrets Secret (shipgrid-secrets) — put on every
     backend pod so `helm upgrade` after rotating a secret actually restarts
     the pods that consume it via envFrom (Secret changes don't roll pods on
     their own). Call with root ($). */}}
{{- define "shipgrid.secretsChecksum" -}}
{{- toYaml .Values.secrets | sha256sum -}}
{{- end -}}

{{/* Checksum of the shared site/license ConfigMap (shipgrid-config) — same
     rollout problem as above for PUBLIC_APP_URL/ADMIN_APP_URL/SP_BASE_URL/
     license.*. Call with root ($). */}}
{{- define "shipgrid.siteConfigChecksum" -}}
{{- printf "%s|%s" (toYaml .Values.site) (toYaml .Values.license) | sha256sum -}}
{{- end -}}

{{/* Checksum of a service's own configs/<name>/config.yaml, when it ships
     one (svc.config: true) — so editing that file rolls just that service.
     Call with (dict "name" $name "root" $). */}}
{{- define "shipgrid.svcConfigChecksum" -}}
{{- $path := printf "configs/%s/config.yaml" .name -}}
{{- $content := .root.Files.Get $path -}}
{{- if $content -}}
{{- $content | sha256sum -}}
{{- else -}}
{{- "no-config-file" | sha256sum -}}
{{- end -}}
{{- end -}}

{{/* Renders one httpGet probe block (liveness|readiness), per-service path/
     timing overridable via services.<name>.probes.<kind>.*, falling back
     field-by-field to defaults.probes.<kind>.*. Call with
     (dict "svc" $svc "root" $ "kind" "liveness" "port" $port). */}}
{{- define "shipgrid.probe" -}}
{{- $d := index .root.Values.defaults.probes .kind -}}
{{- $o := dict -}}
{{- if and .svc.probes (index .svc.probes .kind) -}}
{{- $o = index .svc.probes .kind -}}
{{- end -}}
httpGet:
  path: {{ $o.path | default $d.path }}
  port: {{ .port }}
initialDelaySeconds: {{ $o.initialDelaySeconds | default $d.initialDelaySeconds }}
periodSeconds: {{ $o.periodSeconds | default $d.periodSeconds }}
timeoutSeconds: {{ $o.timeoutSeconds | default $d.timeoutSeconds }}
failureThreshold: {{ $o.failureThreshold | default $d.failureThreshold }}
{{- end -}}
