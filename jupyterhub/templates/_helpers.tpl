{{- /*
  ## About
  This file contains helpers to systematically name, label and select Kubernetes
  objects we define in the .yaml template files.


  ## How helpers work
  Helm helper functions is a good way to avoid repeating something. They will
  generate some output based on one single dictionary of input that we call the
  helpers scope. When you are in helm, you access your current scope with a
  single a single punctuation (.).

  When you ask a helper to render its content, one often forward the current
  scope to the helper in order to allow it to access .Release.Name,
  .Values.rbac.enabled and similar values.

  #### Example - Passing the current scope
  {{ include "jupyterhub.commonLabels" . }}

  It would be possible to pass something specific instead of the current scope
  (.), but that would make .Release.Name etc. inaccessible by the helper which
  is something we aim to avoid.

  #### Example - Passing a new scope
  {{ include "demo.bananaPancakes" (dict "pancakes" 5 "bananas" 3) }}

  To let a helper access the current scope along with additional values we have
  opted to create dictionary containing additional values that is then populated
  with additional values from the current scope through a the merge function.

  #### Example - Passing a new scope augmented with the old
  {{- $_ := merge (dict "appLabel" "kube-lego") . }}
  {{- include "jupyterhub.matchLabels" $_ | nindent 6 }}

  In this way, the code within the definition of `jupyterhub.matchLabels` will
  be able to access .Release.Name and .appLabel.

  NOTE:
    The ordering of merge is crucial, the latter argument is merged into the
    former. So if you would swap the order you would influence the current scope
    risking unintentional behavior. Therefore, always put the fresh unreferenced
    dictionary (dict "key1" "value1") first and the current scope (.) last.


  ## Declared helpers
  - appLabel          |
  - componentLabel    |
  - nameField         | uses componentLabel
  - commonLabels      | uses appLabel
  - labels            | uses commonLabels
  - matchLabels       | uses labels
  - podCullerSelector | uses matchLabels


  ## Example usage
  ```yaml
  # Excerpt from proxy/autohttps/deployment.yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: {{ include "jupyterhub.nameField" . }}
    labels:
      {{- include "jupyterhub.labels" . | nindent 4 }}
  spec:
    selector:
      matchLabels:
        {{- $_ := merge (dict "appLabel" "kube-lego") . }}
        {{- include "jupyterhub.matchLabels" $_ | nindent 6 }}
    template:
      metadata:
        labels:
          {{- include "jupyterhub.labels" $_ | nindent 8 }}
          hub.jupyter.org/network-access-proxy-http: "true"
  ```

  NOTE:
    The "jupyterhub.matchLabels" and "jupyterhub.labels" is passed an augmented
    scope that will influence the helpers' behavior. It get the current scope
    "." but merged with a dictionary containing extra key/value pairs. In this
    case the "." scope was merged with a small dictionary containing only one
    key/value pair "appLabel: kube-lego". It is required for kube-lego to
    function properly. It is a way to override the default app label's value.
*/}}


{{- /*
  jupyterhub.appLabel:
    Used by "jupyterhub.labels".
*/}}
{{- define "jupyterhub.appLabel" -}}
{{ .Values.nameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}


{{- /*
  jupyterhub.componentLabel:
    Used by "jupyterhub.labels" and "jupyterhub.nameField".

    NOTE: The component label is determined by either...
    - 1: The provided scope's .componentLabel
    - 2: The template's filename if living in the root folder
    - 3: The template parent folder's name
    -  : ...and is combined with .componentPrefix and .componentSuffix
*/}}
{{- define "jupyterhub.componentLabel" -}}
{{- $file := .Template.Name | base | trimSuffix ".yaml" -}}
{{- $parent := .Template.Name | dir | base | trimPrefix "templates" -}}
{{- $component := .componentLabel | default $parent | default $file -}}
{{- $component := print (.componentPrefix | default "") $component (.componentSuffix | default "") -}}
{{ $component }}
{{- end }}


{{- /*
  jupyterhub.nameField:
    Populates the name field's value.
    NOTE: some name fields are limited to 63 characters by the DNS naming spec.

  TODO:
  - [ ] Set all name fields using this helper.
  - [ ] Optionally prefix the release name based on some setting in
        .Values to allow for multiple deployments within a single namespace.
*/}}
{{- define "jupyterhub.nameField" -}}
{{- $name := print (.namePrefix | default "") (include "jupyterhub.componentLabel" .) (.nameSuffix | default "") -}}
{{ printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}


{{- /*
  jupyterhub.commonLabels:
    Foundation for "jupyterhub.labels".
    Provides labels: app, release, (chart and heritage).
*/}}
{{- define "jupyterhub.commonLabels" -}}
app: {{ .appLabel | default (include "jupyterhub.appLabel" .) }}
release: {{ .Release.Name }}
{{- if not .matchLabels }}
chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
heritage: {{ .heritageLabel | default .Release.Service }}
{{- end }}
{{- end }}


{{- /*
  jupyterhub.labels:
    Provides labels: component, app, release, (chart and heritage).
*/}}
{{- define "jupyterhub.labels" -}}
component: {{ include "jupyterhub.componentLabel" . }}
{{ include "jupyterhub.commonLabels" . }}
{{- end }}


{{- /*
  jupyterhub.matchLabels:
    Used to provide pod selection labels: component, app, release.
*/}}
{{- define "jupyterhub.matchLabels" -}}
{{- $_ := merge (dict "matchLabels" true) . -}}
{{ include "jupyterhub.labels" $_ }}
{{- end }}


{{- /*
  jupyterhub.dockersingleuserconfigjson:
    Creates a base64 encoded docker registry json blob for use in a image pull
    secret, just like the `kubectl create secret docker-registry` command does
    for the generated secrets data.dockerconfigjson field. The output is
    verified to be exactly the same even if you have a password spanning
    multiple lines as you may need to use a private GCR registry.

    - https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod
*/}}
{{- define "jupyterhub.dockersingleuserconfigjson" -}}
{{ include "jupyterhub.dockersingleuserconfigjson.yaml" . | b64enc }}
{{- end }}

{{- define "jupyterhub.dockersingleuserconfigjson.yaml" -}}
{{- with .Values.singleuser.imagePullSecret -}}
{
  "auths": {
    {{ .registry | default "https://index.docker.io/v1/" | quote }}: {
      "username": {{ .username | quote }},
      "password": {{ .password | quote }},
      {{- if .email }}
      "email": {{ .email | quote }},
      {{- end }}
      "auth": {{ (print .username ":" .password) | b64enc | quote }}
    }
  }
}
{{- end }}
{{- end }}

{{- /*
  jupyterhub.dockerhubconfigjson:
    Creates a base64 encoded docker registry json blob for use in a image pull
    secret, just like the `kubectl create secret docker-registry` command does
    for the generated secrets data.dockerhubconfigjson field. The output is
    verified to be exactly the same even if you have a password spanning
    multiple lines as you may need to use a private GCR registry.

    - https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod
*/}}
{{- define "jupyterhub.dockerhubconfigjson" -}}
{{ include "jupyterhub.dockerhubconfigjson.yaml" . | b64enc }}
{{- end }}

{{- define "jupyterhub.dockerhubconfigjson.yaml" -}}
{{- with .Values.hub.imagePullSecret -}}
{
  "auths": {
    {{ .registry | default "https://index.docker.io/v1/" | quote }}: {
      "username": {{ .username | quote }},
      "password": {{ .password | quote }},
      {{- if .email }}
      "email": {{ .email | quote }},
      {{- end }}
      "auth": {{ (print .username ":" .password) | b64enc | quote }}
    }
  }
}
{{- end }}
{{- end }}

{{- /*
  jupyterhub.hub.env:
    The env vars for the hub pod.
*/}}
{{- define "jupyterhub.hub.env" -}}
- name: PYTHONUNBUFFERED
  value: "1"
- name: HELM_RELEASE_NAME
  value: {{ .Release.Name | quote }}
{{- if .Values.hub.cookieSecret }}
- name: JPY_COOKIE_SECRET
  valueFrom:
    secretKeyRef:
      {{- if .Values.hub.existingSecret }}
      name: {{ .Values.hub.existingSecret }}
      {{- else }}
      name: hub-secret
      {{- end }}
      key: hub.cookie-secret
{{- end }}
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: CONFIGPROXY_AUTH_TOKEN
  valueFrom:
    secretKeyRef:
      {{- if .Values.hub.existingSecret }}
      name: {{ .Values.hub.existingSecret }}
      {{- else }}
      name: hub-secret
      {{- end }}
      key: proxy.token
{{- if .Values.auth.state.enabled }}
- name: JUPYTERHUB_CRYPT_KEY
  valueFrom:
    secretKeyRef:
      {{- if .Values.hub.existingSecret }}
      name: {{ .Values.hub.existingSecret }}
      {{- else }}
      name: hub-secret
      {{- end }}
      key: auth.state.crypto-key
{{- end }}
{{- if .Values.hub.db.password }}
{{- if eq .Values.hub.db.type "mysql" }}
- name: MYSQL_PWD
  valueFrom:
    secretKeyRef:
      {{- if .Values.hub.existingSecret }}
      name: {{ .Values.hub.existingSecret }}
      {{- else }}
      name: hub-secret
      {{- end }}
      key: hub.db.password
{{- else if eq .Values.hub.db.type "postgres" }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      {{- if .Values.hub.existingSecret }}
      name: {{ .Values.hub.existingSecret }}
      {{- else }}
      name: hub-secret
      {{- end }}
      key: hub.db.password
{{- end }}
{{- end }}
{{- if .Values.hub.extraEnv }}
{{- $extraEnvType := typeOf .Values.hub.extraEnv }}
{{- /* If we have a list, embed that here directly. This allows for complex configuration from configmap, downward API, etc. */}}
{{- if eq $extraEnvType "[]interface {}" }}
{{ .Values.hub.extraEnv | toYaml | trimSuffix "\n" }}
{{- else if eq $extraEnvType "map[string]interface {}" }}
{{- /* If we have a map, treat those as key-value pairs. */}}
{{- range $key, $value := .Values.hub.extraEnv }}
- name: {{ $key | quote }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- end }}

{{- /*
  jupyterhub.hub.volumeMounts:
    The volumeMounts for the hub pod.
*/}}
{{- define "jupyterhub.hub.volumeMounts" -}}
- mountPath: /etc/jupyterhub/jupyterhub_config.py
  subPath: jupyterhub_config.py
  name: config
- mountPath: /etc/jupyterhub/z2jh.py
  subPath: z2jh.py
  name: config
- mountPath: /etc/jupyterhub/config/
  name: config
- mountPath: /etc/jupyterhub/secret/
  name: secret
{{- if .Values.hub.extraVolumeMounts }}
{{ .Values.hub.extraVolumeMounts | toYaml | trimSuffix "\n" }}
{{- end }}
{{- if eq .Values.hub.db.type "sqlite-pvc" }}
- mountPath: /srv/jupyterhub
  name: hub-db-dir
  {{- if .Values.hub.db.pvc.subPath }}
  subPath: {{ .Values.hub.db.pvc.subPath | quote }}
  {{- end }}
{{- end }}
{{- if .Values.hub.https.enabled }}
- mountPath: /srv/jupyterhub-internal-ssl
  name: hub-internal-ssl
  {{- if .Values.hub.https.pvc.subPath }}
  subPath: {{ .Values.hub.https.pvc.subPath | quote }}
  {{- end }}
{{- end }}

{{- end }}



{{- /*
  jupyterhub.resources:
    The resource request of a singleuser.
*/}}
{{- define "jupyterhub.resources" -}}
{{- $r1 := .Values.singleuser.cpu.guarantee -}}
{{- $r2 := .Values.singleuser.memory.guarantee -}}
{{- $r3 := .Values.singleuser.extraResource.guarantees -}}
{{- $r := or $r1 $r2 $r3 -}}
{{- $l1 := .Values.singleuser.cpu.limit -}}
{{- $l2 := .Values.singleuser.memory.limit -}}
{{- $l3 := .Values.singleuser.extraResource.limits -}}
{{- $l := or $l1 $l2 $l3 -}}
{{- if $r -}}
requests:
  {{- if $r1 }}
  cpu: {{ .Values.singleuser.cpu.guarantee }}
  {{- end }}
  {{- if $r2 }}
  memory: {{ .Values.singleuser.memory.guarantee }}
  {{- end }}
  {{- if $r3 }}
  {{- range $key, $value := .Values.singleuser.extraResource.guarantees }}
  {{ $key | quote }}: {{ $value | quote }}
  {{- end }}
  {{- end }}
{{- end }}

{{- if $l }}
limits:
  {{- if $l1 }}
  cpu: {{ .Values.singleuser.cpu.limit }}
  {{- end }}
  {{- if $l2 }}
  memory: {{ .Values.singleuser.memory.limit }}
  {{- end }}
  {{- if $l3 }}
  {{- range $key, $value := .Values.singleuser.extraResource.limits }}
  {{ $key | quote }}: {{ $value | quote }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
