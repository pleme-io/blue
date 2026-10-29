use("deeta", [:get_or, :pretty, :yaml])
use("kyuuji")
use("retsu", [:first])
use("settei", [:env_prefix])
use("shihyou")

def entries_of(m)
  if m.nil?
    []
  else
    map_entries(m)
  end
end

def from_entries(es)
  reduce((acc, e) -> assoc(acc, first(e), second(e)), {}, es)
end

def defaults(svc)
  base = from_entries(entries_of(get_or(svc, "config", {})))
  with_listen = assoc(
    base,
    "listen",
    {"host" => "0.0.0.0", "port" => svc["port"]}
  )
  with_health = assoc(with_listen, "health", get_or(svc, "probe", "/healthz"))
  assoc(
    with_health,
    "flags",
    from_entries(entries_of(get_or(svc, "flags", {})))
  )
end

def type_name(v)
  if v == true or v == false
    "boolean"
  elsif integer?(v)
    "integer"
  elsif float?(v)
    "number"
  elsif string?(v)
    "string"
  elsif v != nil and map?(v)
    "object"
  elsif v.nil?
    "null"
  else
    "array"
  end
end

def schema_of(v)
  t = type_name(v)
  if t == "object"
    {
      "type" => "object",
      "additionalProperties" => false,
      "properties" => from_entries(
        map((e) -> [first(e), schema_of(second(e))], map_entries(v))
      )
    }
  elsif t == "array"
    if v == []
      {"type" => "array"}
    else
      {"type" => "array", "items" => schema_of(first(v))}
    end
  elsif t == "null"
    {}
  else
    {"type" => t, "default" => v}
  end
end

def open_object(values_schema)
  {"type" => "object", "additionalProperties" => values_schema}
end

def document(title, schema)
  assoc(
    assoc(schema, "$schema", "https://json-schema.org/draft-07/schema#"),
    "title",
    title
  )
end

def schema_name(name)
  replace(name, "-", "_")
end

def service_defaults(name, svc)
  d = defaults(svc)
  if tables(svc) == []
    d
  else
    assoc(d, "database", {"url" => "", "schema" => schema_name(name)})
  end
end

def config_schema(name, svc)
  document("#{name} settings", schema_of(service_defaults(name, svc)))
end

def resources_of(svc)
  r = get_or(svc, "resources", {})
  requests = from_entries(
    filter(
      (e) -> second(e) != nil,
      [["cpu", r["cpu"]], ["memory", r["memory"]]]
    )
  )
  limits = from_entries(
    filter((e) -> second(e) != nil, [["memory", r["memory_limit"]]])
  )
  from_entries(
    filter(
      (e) -> map_entries(second(e)) != [],
      [["requests", requests], ["limits", limits]]
    )
  )
end

def cache?(svc)
  svc["cache"] != nil
end

def cache_values(svc)
  c = get_or(svc, "cache", {})
  {
    "enabled" => false,
    "host" => "",
    "port" => get_or(c, "port", 6379),
    "passwordSecret" => "",
    "passwordKey" => "password"
  }
end

def tables(svc)
  entries_of(get_or(svc, "schema", {}))
end

def values(svc)
  values_with(svc, :pleme_lib)
end

def service_values(svc, mode)
  if mode == :self
    {"type" => "ClusterIP", "port" => svc["port"]}
  else
    {
      "type" => "ClusterIP",
      "ports" => [
        {
          "name" => "http",
          "port" => svc["port"],
          "targetPort" => "http",
          "protocol" => "TCP"
        }
      ]
    }
  end
end

def values_with(svc, mode)
  d = defaults(svc)
  base = {
    "replicaCount" => get_or(svc, "replicas", 1),
    "image" => {
      "repository" => svc["repository"],
      "tag" => "",
      "pullPolicy" => "IfNotPresent"
    },
    "command" => [],
    "args" => get_or(svc, "host_args", []),
    "service" => service_values(svc, mode),
    "listen" => d["listen"],
    "health" => d["health"],
    "config" => from_entries(entries_of(get_or(svc, "config", {}))),
    "flags" => d["flags"],
    "resources" => resources_of(svc),
    "podAnnotations" => {
      "prometheus.io/scrape" => "true",
      "prometheus.io/port" => to_s(svc["port"]),
      "prometheus.io/path" => kyuuji::metrics_path
    },
    "slo" => {"rules" => true, "dashboard" => true},
    "podSecurityContext" => {
      "runAsNonRoot" => true,
      "runAsUser" => 65532,
      "runAsGroup" => 65532
    },
    "securityContext" => {
      "allowPrivilegeEscalation" => false,
      "readOnlyRootFilesystem" => true,
      "capabilities" => {"drop" => ["ALL"]}
    }
  }
  with_sa = if mode == :self
    base
  else
    assoc(
      base,
      "serviceAccount",
      {"create" => true, "automountServiceAccountToken" => false}
    )
  end
  with_cache = if cache?(svc)
    assoc(with_sa, "cache", cache_values(svc))
  else
    with_sa
  end
  if tables(svc) == []
    with_cache
  else
    assoc(
      with_cache,
      "database",
      {
        "enabled" => false,
        "host" => "",
        "port" => 5432,
        "name" => "",
        "username" => "",
        "credentialsSecret" => "",
        "passwordKey" => "password",
        "migratorImage" => "docker.io/library/postgres:17-alpine"
      }
    )
  end
end

def values_schema(name, svc)
  values_schema_with(name, svc, :pleme_lib)
end

def values_schema_with(name, svc, mode)
  v = values_with(svc, mode)
  closed = schema_of(v)
  props = closed["properties"]
  string_map = open_object({"type" => "string"})
  kube_object = {"type" => "object"}
  quantity = {"type" => "string"}
  resources = {
    "type" => "object",
    "additionalProperties" => false,
    "properties" => {
      "requests" => {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {"cpu" => quantity, "memory" => quantity}
      },
      "limits" => {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {"cpu" => quantity, "memory" => quantity}
      }
    }
  }
  command = {"type" => "array", "items" => {"type" => "string"}}
  replicas = assoc(props["replicaCount"], "minimum", 0)
  open = assoc(
    assoc(
      assoc(
        assoc(
          assoc(
            assoc(props, "podAnnotations", string_map),
            "podSecurityContext",
            kube_object
          ),
          "securityContext",
          kube_object
        ),
        "resources",
        resources
      ),
      "command",
      command
    ),
    "replicaCount",
    replicas
  )
  with_args = assoc(open, "args", command)
  with_library = if mode == :self
    with_args
  else
    assoc(assoc(with_args, "pleme-lib", kube_object), "global", kube_object)
  end
  document("#{name} chart values", assoc(closed, "properties", with_library))
end

def column_sql(spec)
  nullable = ends_with?(spec, "?")
  t = if nullable
    join(butlast(chars(spec)), "")
  else
    spec
  end
  sql = get(
    {
      "text" => "text",
      "integer" => "integer",
      "bigint" => "bigint",
      "boolean" => "boolean",
      "timestamptz" => "timestamptz",
      "uuid" => "uuid",
      "jsonb" => "jsonb",
      "double" => "double precision"
    },
    t
  )
  if sql.nil?
    raise(:column_type, "#{spec} is not a column type")
  end
  [sql, nullable]
end

def quoted(ident)
  "\"#{ident}\""
end

def table_sql(t)
  table_sql_in(nil, t)
end

def table_sql_in(schema, t)
  name = if schema.nil?
    quoted(first(t))
  else
    "#{quoted(schema)}.#{quoted(first(t))}"
  end
  cols = map_entries(second(t))
  defs = map(
    fn(c)
      s = column_sql(second(c))
      if second(s)
        "  #{quoted(first(c))} #{first(s)}"
      else
        "  #{quoted(first(c))} #{first(s)} NOT NULL"
      end
    end,
    cols
  )
  create = unlines(
    [
      "CREATE TABLE IF NOT EXISTS #{name} (",
      "  \"id\" bigserial PRIMARY KEY#{join(map((d) -> join_lines([",", d]), defs), "")}",
      ");"
    ]
  )
  adds = join(
    map(
      fn(c)
        unlines(
          [
            "ALTER TABLE #{name} ADD COLUMN IF NOT EXISTS #{quoted(first(c))} #{first(column_sql(second(c)))};"
          ]
        )
      end,
      cols
    ),
    ""
  )
  "#{create}#{adds}"
end

@doc """
ddl: database schema statements from declared tables.

    ddl({"port" => 1}) #=> ""
"""
def ddl(svc)
  join(map(table_sql, tables(svc)), line_break)
end

def ddl_in(schema, svc)
  join_lines(
    [
      "CREATE SCHEMA IF NOT EXISTS #{quoted(schema)};",
      "",
      join(map((t) -> table_sql_in(schema, t), tables(svc)), line_break)
    ]
  )
end

def row_refusals(svc, table, row)
  cols = get(get_or(svc, "schema", {}), table)
  if cols.nil?
    [[:unknown_table, "#{table} is not a declared table"]]
  else
    unknown = map(
      (e) -> [:unknown_column, "#{table}.#{first(e)} is not a declared column"],
      filter((e) -> get(cols, first(e)).nil?, map_entries(row))
    )
    missing = map(
      (e) -> [:missing_column, "#{table}.#{first(e)} is required"],
      filter(
        (e) -> not ends_with?(second(e), "?") and get(row, first(e)).nil?,
        map_entries(cols)
      )
    )
    append(unknown, missing)
  end
end

def literal(v)
  if v.nil?
    "NULL"
  elsif v == true
    "TRUE"
  elsif v == false
    "FALSE"
  elsif number?(v)
    to_s(v)
  else
    "'#{replace(to_s(v), "'", "''")}'"
  end
end

def insert_sql(svc, table, row)
  rs = row_refusals(svc, table, row)
  if rs != []
    raise(first(first(rs)), join(map((r) -> second(r), rs), "; "))
  end
  es = map_entries(row)
  unlines(
    [
      "INSERT INTO #{quoted(table)} (#{join(map((e) -> quoted(first(e)), es), ", ")}) VALUES (#{join(map((e) -> literal(second(e)), es), ", ")});"
    ]
  )
end

def lines(xs)
  unlines([join(xs, line_break)])
end

def chart_yaml(name, version, mode)
  base = {
    "apiVersion" => "v2",
    "name" => name,
    "description" => "#{name}, rendered by blue from its Bluefile service declaration",
    "type" => "application",
    "version" => version,
    "appVersion" => version
  }
  yaml(
    if mode == :self
      base
    else
      assoc(
        base,
        "dependencies",
        [
          {
            "name" => "pleme-lib",
            "version" => pleme_lib_range,
            "repository" => "oci://ghcr.io/pleme-io/charts"
          }
        ]
      )
    end
  )
end

def pleme_lib_range()
  ">=0.53.0"
end

def helpers(n)
  lines(
    [
      "{{- define \"#{n}.name\" -}}",
      "{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix \"-\" }}",
      "{{- end }}",
      "",
      "{{- define \"#{n}.fullname\" -}}",
      "{{- if contains (include \"#{n}.name\" .) .Release.Name }}",
      "{{- .Release.Name | trunc 63 | trimSuffix \"-\" }}",
      "{{- else }}",
      "{{- printf \"%s-%s\" .Release.Name (include \"#{n}.name\" .) | trunc 63 | trimSuffix \"-\" }}",
      "{{- end }}",
      "{{- end }}",
      "",
      "{{- define \"#{n}.chart\" -}}",
      "{{- printf \"%s-%s\" .Chart.Name .Chart.Version | replace \"+\" \"_\" | trunc 63 | trimSuffix \"-\" }}",
      "{{- end }}",
      "",
      "{{- define \"#{n}.selectorLabels\" -}}",
      "app.kubernetes.io/name: {{ include \"#{n}.name\" . }}",
      "app.kubernetes.io/instance: {{ .Release.Name }}",
      "{{- end }}",
      "",
      "{{- define \"#{n}.labels\" -}}",
      "helm.sh/chart: {{ include \"#{n}.chart\" . }}",
      "{{ include \"#{n}.selectorLabels\" . }}",
      "app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}",
      "app.kubernetes.io/managed-by: {{ .Release.Service }}",
      "{{- end }}"
    ]
  )
end

def service_account(n)
  lines(
    [
      "apiVersion: v1",
      "kind: ServiceAccount",
      "metadata:",
      "  name: {{ include \"#{n}.fullname\" . }}",
      "  namespace: {{ .Release.Namespace }}",
      "  labels:",
      "    {{- include \"#{n}.labels\" . | nindent 4 }}",
      "automountServiceAccountToken: false"
    ]
  )
end

def service(n)
  lines(
    [
      "apiVersion: v1",
      "kind: Service",
      "metadata:",
      "  name: {{ include \"#{n}.fullname\" . }}",
      "  namespace: {{ .Release.Namespace }}",
      "  labels:",
      "    {{- include \"#{n}.labels\" . | nindent 4 }}",
      "spec:",
      "  type: {{ .Values.service.type }}",
      "  ports:",
      "    - name: http",
      "      port: {{ .Values.service.port }}",
      "      targetPort: http",
      "      protocol: TCP",
      "  selector:",
      "    {{- include \"#{n}.selectorLabels\" . | nindent 4 }}"
    ]
  )
end

def deployment(n, h)
  deployment_with(n, h, {})
end

def cache_env(p, n)
  [
    "            {{- if and .Values.cache .Values.cache.enabled }}",
    "            - name: #{p}CACHE__HOST",
    "              value: {{ required \"cache.host is required when cache.enabled is true\" .Values.cache.host | quote }}",
    "            - name: #{p}CACHE__PORT",
    "              value: {{ .Values.cache.port | quote }}",
    "            - name: #{p}CACHE__PASSWORD_FILE",
    "              value: #{cache_mount(n)}/password",
    "            {{- end }}"
  ]
end

def cache_mount(n)
  "/var/run/secrets/#{n}-valkey"
end

def cache_mounts(n)
  [
    "          {{- if and .Values.cache .Values.cache.enabled }}",
    "          volumeMounts:",
    "            - name: #{n}-valkey",
    "              mountPath: #{cache_mount(n)}",
    "              readOnly: true",
    "          {{- end }}"
  ]
end

def cache_volumes(n)
  [
    "      {{- if and .Values.cache .Values.cache.enabled }}",
    "      volumes:",
    "        - name: #{n}-valkey",
    "          secret:",
    "            secretName: {{ required \"cache.passwordSecret is required when cache.enabled is true\" .Values.cache.passwordSecret | quote }}",
    "            items:",
    "              - key: {{ .Values.cache.passwordKey | quote }}",
    "                path: password",
    "      {{- end }}"
  ]
end

def deployment_with(n, h, svc)
  p = env_prefix(n)
  cached = cache?(svc)
  lines(
    append(
      [
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: {{ include \"#{h}.fullname\" . }}",
        "  namespace: {{ .Release.Namespace }}",
        "  labels:",
        "    {{- include \"#{h}.labels\" . | nindent 4 }}",
        "spec:",
        "  replicas: {{ .Values.replicaCount }}",
        "  selector:",
        "    matchLabels:",
        "      {{- include \"#{h}.selectorLabels\" . | nindent 6 }}",
        "  template:",
        "    metadata:",
        "      labels:",
        "        {{- include \"#{h}.selectorLabels\" . | nindent 8 }}",
        "      {{- with .Values.podAnnotations }}",
        "      annotations:",
        "        {{- toYaml . | nindent 8 }}",
        "      {{- end }}",
        "    spec:",
        "      serviceAccountName: {{ include \"#{h}.fullname\" . }}",
        "      automountServiceAccountToken: false",
        "      {{- with .Values.podSecurityContext }}",
        "      securityContext:",
        "        {{- toYaml . | nindent 8 }}",
        "      {{- end }}",
        "      containers:",
        "        - name: #{n}",
        "          image: \"{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}\"",
        "          imagePullPolicy: {{ .Values.image.pullPolicy }}",
        "          {{- with .Values.command }}",
        "          command:",
        "            {{- toYaml . | nindent 12 }}",
        "          {{- end }}",
        "          {{- with .Values.args }}",
        "          args:",
        "            {{- toYaml . | nindent 12 }}",
        "          {{- end }}",
        "          env:",
        "            - name: BLUE_SERVICE",
        "              value: \"#{n}\"",
        "            - name: #{p}LISTEN__HOST",
        "              value: {{ .Values.listen.host | quote }}",
        "            - name: #{p}LISTEN__PORT",
        "              value: {{ .Values.listen.port | quote }}",
        "            - name: #{p}HEALTH",
        "              value: {{ .Values.health | quote }}",
        "            {{- if and .Values.database .Values.database.enabled }}",
        "            - name: #{p}DATABASE__URL",
        "              value: {{ printf \"postgres://%s@%s:%v/%s\" .Values.database.username .Values.database.host .Values.database.port .Values.database.name | quote }}",
        "            {{- end }}"
      ],
      if cached
        cache_env(p, n)
      else
        []
      end,
      [
        "            {{- with include \"#{n}.env\" (list \"#{p}\" .Values.config) | trim }}",
        "            {{- . | nindent 12 }}",
        "            {{- end }}",
        "            {{- with include \"#{n}.env\" (list \"#{p}FLAGS__\" .Values.flags) | trim }}",
        "            {{- . | nindent 12 }}",
        "            {{- end }}",
        "          ports:",
        "            - name: http",
        "              containerPort: {{ .Values.listen.port }}",
        "              protocol: TCP",
        "          livenessProbe:",
        "            httpGet:",
        "              path: {{ .Values.health | quote }}",
        "              port: http",
        "          readinessProbe:",
        "            httpGet:",
        "              path: {{ .Values.health | quote }}",
        "              port: http",
        "          {{- with .Values.resources }}",
        "          resources:",
        "            {{- toYaml . | nindent 12 }}",
        "          {{- end }}",
        "          {{- with .Values.securityContext }}",
        "          securityContext:",
        "            {{- toYaml . | nindent 12 }}",
        "          {{- end }}"
      ],
      if cached
        append(cache_mounts(n), cache_volumes(n))
      else
        []
      end,
      env_template(n)
    )
  )
end

@doc """
The named template that turns a settings map into environment entries. A
nested map joins its keys with `__`, the separator settei reads back; a list
renders as JSON; a null leaf renders nothing, so the program keeps its own
default.

    first(env_template("hello")) == "{{- define \"hello.env\" }}"
"""
def env_template(n)
  [
    "{{- define \"#{n}.env\" }}",
    "{{- $prefix := index . 0 }}",
    "{{- range $k, $v := index . 1 }}",
    "{{- if kindIs \"map\" $v }}",
    "{{- include \"#{n}.env\" (list (printf \"%s%s__\" $prefix (upper $k)) $v) }}",
    "{{- else if not (kindIs \"invalid\" $v) }}",
    "- name: {{ printf \"%s%s\" $prefix (upper $k) }}",
    "  value: {{ if kindIs \"slice\" $v }}{{ $v | toJson | quote }}{{ else }}{{ $v | toString | quote }}{{ end }}",
    "{{- end }}",
    "{{- end }}",
    "{{- end }}"
  ]
end

def migration(_n, h)
  lines(
    [
      "{{- if .Values.database.enabled }}",
      "{{- $db := .Values.database }}",
      "apiVersion: v1",
      "kind: ConfigMap",
      "metadata:",
      "  name: {{ include \"#{h}.fullname\" . }}-schema",
      "  namespace: {{ .Release.Namespace }}",
      "  labels:",
      "    {{- include \"#{h}.labels\" . | nindent 4 }}",
      "data:",
      "  schema.sql: |-",
      "    {{- .Files.Get \"files/schema.sql\" | trimSuffix \"\\n\" | nindent 4 }}",
      "---",
      "apiVersion: shinka.pleme.io/v1alpha1",
      "kind: DatabaseMigration",
      "metadata:",
      "  name: {{ include \"#{h}.fullname\" . }}-schema",
      "  namespace: {{ .Release.Namespace }}",
      "  labels:",
      "    {{- include \"#{h}.labels\" . | nindent 4 }}",
      "spec:",
      "  database:",
      "    directRef:",
      "      engine: postgres",
      "      host: {{ required \"database.host is required when database.enabled is true\" $db.host | quote }}",
      "      port: {{ $db.port }}",
      "      {{- with $db.name }}",
      "      database: {{ . | quote }}",
      "      {{- end }}",
      "      {{- with $db.username }}",
      "      username: {{ . | quote }}",
      "      {{- end }}",
      "      credentialsSecretRef:",
      "        name: {{ required \"database.credentialsSecret is required when database.enabled is true\" $db.credentialsSecret | quote }}",
      "      passwordKey: {{ $db.passwordKey | quote }}",
      "      sqlConfigMapRef:",
      "        name: {{ include \"#{h}.fullname\" . }}-schema",
      "  migrator:",
      "    type: custom",
      "    imageOverride: {{ $db.migratorImage | quote }}",
      "    deploymentRef:",
      "      name: {{ include \"#{h}.fullname\" . }}",
      "    command:",
      "      - psql",
      "      - -v",
      "      - ON_ERROR_STOP=1",
      "      - -f",
      "      - /sql/schema.sql",
      "{{- end }}"
    ]
  )
end

def notes(n, h)
  lines(
    [
      "{{ include \"#{h}.fullname\" . }} answers HTTP on port {{ .Values.listen.port }}; its health is {{ .Values.health }}.",
      "Settings reach it as #{env_prefix(n)}* environment variables, the shikumi env tier over its baked defaults."
    ]
  )
end

def slo_rules(name, svc)
  r = shihyou::rules(name, svc)
  m = assoc(r["metadata"], "namespace", "{{ .Release.Namespace }}")
  unlines(
    [
      "{{- if .Values.slo.rules }}",
      "#{yaml(assoc(r, "metadata", m))}{{- end }}"
    ]
  )
end

def dashboard_map(name)
  lines(
    [
      "{{- if .Values.slo.dashboard }}",
      "apiVersion: v1",
      "kind: ConfigMap",
      "metadata:",
      "  name: #{name}-dashboard",
      "  namespace: {{ .Release.Namespace }}",
      "  labels:",
      "    grafana_dashboard: \"1\"",
      "    app.kubernetes.io/name: #{name}",
      "    app.kubernetes.io/component: slo",
      "data:",
      "  #{name}.json: |-",
      "    {{- .Files.Get \"files/dashboard.json\" | trimSuffix \"\\n\" | nindent 4 }}",
      "{{- end }}"
    ]
  )
end

def catalog_entry(name, version, svc)
  shihyou::entry(name, version, svc)
end

def files(name, version, svc)
  files_with(name, version, svc, :pleme_lib)
end

def files_self(name, version, svc)
  files_with(name, version, svc, :self)
end

def files_with(name, version, svc, mode)
  h = if mode == :self
    name
  else
    "pleme-lib"
  end
  own = if mode == :self
    [
      ["chart/templates/_helpers.tpl", helpers(name)],
      ["chart/templates/serviceaccount.yaml", service_account(name)],
      ["chart/templates/service.yaml", service(name)]
    ]
  else
    [
      [
        "chart/templates/serviceaccount.yaml",
        unlines(["{{- include \"pleme-lib.serviceaccount\" . }}"])
      ],
      [
        "chart/templates/service.yaml",
        unlines(["{{- include \"pleme-lib.service\" . }}"])
      ]
    ]
  end
  chart = [
    ["chart/Chart.yaml", chart_yaml(name, version, mode)],
    ["chart/values.yaml", yaml(values_with(svc, mode))],
    ["chart/values.schema.json", pretty(values_schema_with(name, svc, mode))],
    ["chart/templates/deployment.yaml", deployment_with(name, h, svc)],
    ["chart/templates/NOTES.txt", notes(name, h)],
    ["chart/templates/slo-rules.yaml", slo_rules(name, svc)],
    ["chart/templates/dashboard.yaml", dashboard_map(name)],
    ["chart/files/dashboard.json", pretty(shihyou::dashboard(name, svc))]
  ]
  db = if tables(svc) == []
    []
  else
    [
      ["chart/templates/migration.yaml", migration(name, h)],
      ["chart/files/schema.sql", ddl_in(schema_name(name), svc)]
    ]
  end
  config = [
    ["config/#{name}.yaml", pretty(service_defaults(name, svc))],
    ["config/#{name}.schema.json", pretty(config_schema(name, svc))]
  ]
  sort_keyed((f) -> first(f), append(chart, own, db, config))
end

def write_tree(root, fs)
  map(
    fn(f)
      path = "#{root}/#{first(f)}"
      mkdir_p(path_dirname(path))
      write_file(path, second(f))
      path
    end,
    fs
  )
end

def sample()
  {
    "program" => "hello.b",
    "repository" => "ghcr.io/pleme-io/hello",
    "port" => 8080,
    "probe" => "/healthz",
    "config" => {"greeting" => "hello", "times" => 2},
    "flags" => {"shout" => false},
    "schema" => {"greetings" => {"text" => "text", "note" => "text?"}}
  }
end

test "defaults are the declared settings plus listen, health and flags"
  d = defaults(sample)
  assert d ==
    {
      "greeting" => "hello",
      "times" => 2,
      "listen" => {"host" => "0.0.0.0", "port" => 8080},
      "health" => "/healthz",
      "flags" => {"shout" => false}
    }
  assert defaults({"port" => 1}) ==
    {
      "listen" => {"host" => "0.0.0.0", "port" => 1},
      "health" => "/healthz",
      "flags" => {}
    }
end

test "a schema is closed and typed from the values it describes"
  s = schema_of({"a" => 1, "b" => {"c" => true}, "l" => ["x"]})
  assert s["additionalProperties"] == false
  assert s["properties"]["a"]["type"] == "integer"
  assert s["properties"]["b"]["properties"]["c"]["type"] == "boolean"
  assert s["properties"]["l"]["items"]["type"] == "string"
  assert schema_of([]) == {"type" => "array"}
end

test "the values schema closes what blue owns and opens what Kubernetes owns"
  vs = values_schema("hello", sample)["properties"]
  assert vs["config"]["additionalProperties"] == false
  assert vs["flags"]["properties"]["shout"]["type"] == "boolean"
  assert vs["podSecurityContext"]["type"] == "object"
  assert vs["podSecurityContext"]["additionalProperties"].nil?
  assert vs["replicaCount"]["minimum"] == 0
  assert vs["database"]["properties"]["enabled"]["default"] == false
  bare = values_schema("hello", {"port" => 1, "repository" => "r/x"})
  assert bare["properties"]["database"].nil?
end

test "the DDL is additive, keyed by id, with nullable columns marked"
  sql = ddl(sample)
  assert contains?(
    sql,
    join_lines(
      [
        "CREATE TABLE IF NOT EXISTS \"greetings\" (",
        "  \"id\" bigserial PRIMARY KEY,",
        "  \"note\" text,",
        "  \"text\" text NOT NULL",
        ");"
      ]
    )
  ) == true
  assert contains?(
    sql,
    "ALTER TABLE \"greetings\" ADD COLUMN IF NOT EXISTS \"note\" text;"
  ) == true
  assert ddl({"port" => 1}) == ""
  assert error?(
    begin
      column_sql("varchar")
    rescue e
      e
    end
  ) == true
  assert column_sql("double?") == ["double precision", true]
end

test "a row is checked against its table before it becomes SQL"
  assert insert_sql(sample, "greetings", {"text" => "it's"}) ==
    unlines(["INSERT INTO \"greetings\" (\"text\") VALUES ('it''s');"])
  assert row_refusals(sample, "greetings", {"note" => "x"}) ==
    [[:missing_column, "greetings.text is required"]]
  assert row_refusals(sample, "nope", {}) ==
    [[:unknown_table, "nope is not a declared table"]]
  assert first(
    first(row_refusals(sample, "greetings", {"text" => "a", "bad" => 1}))
  ) == :unknown_column
end

test "the tree holds the chart, its schema, the config and, with a schema, the migration"
  self_paths = map((f) -> first(f), files_self("hello", "0.1.0", sample))
  assert member?("chart/templates/_helpers.tpl", self_paths) == true
  paths = map((f) -> first(f), files("hello", "0.1.0", sample))
  assert paths ==
    [
      "chart/Chart.yaml",
      "chart/files/dashboard.json",
      "chart/files/schema.sql",
      "chart/templates/NOTES.txt",
      "chart/templates/dashboard.yaml",
      "chart/templates/deployment.yaml",
      "chart/templates/migration.yaml",
      "chart/templates/service.yaml",
      "chart/templates/serviceaccount.yaml",
      "chart/templates/slo-rules.yaml",
      "chart/values.schema.json",
      "chart/values.yaml",
      "config/hello.schema.json",
      "config/hello.yaml"
    ]
  bare = map(
    (f) -> first(f),
    files("hello", "0.1.0", {"port" => 1, "repository" => "r/x"})
  )
  assert member?("chart/templates/migration.yaml", bare) == false
  assert contains?(
    second(first(files("hello", "0.1.0", sample))),
    "version: \"0.1.0\""
  ) == true
  assert contains?(
    deployment("ola-mundo", "pleme-lib"),
    "(list \"OLA_MUNDO_FLAGS__\" .Values.flags)"
  ) == true
  assert contains?(
    deployment("ola-mundo", "pleme-lib"),
    "include \"pleme-lib.fullname\""
  ) == true
  assert contains?(
    second(first(files("hello", "0.1.0", sample))),
    "name: \"pleme-lib\""
  ) == true
  assert contains?(
    second(first(files_self("hello", "0.1.0", sample))),
    "pleme-lib"
  ) == false
  assert contains?(service("hello"), "  namespace: {{ .Release.Namespace }}") ==
    true
end

test "a service with tables names its schema and a database setting"
  d = service_defaults("ola-mundo", sample)
  assert d["database"] == {"url" => "", "schema" => "ola_mundo"}
  assert service_defaults("x", {"port" => 1})["database"].nil?
  sql = ddl_in("ola_mundo", sample)
  assert starts_with?(sql, "CREATE SCHEMA IF NOT EXISTS \"ola_mundo\";") == true
  assert contains?(
    sql,
    "CREATE TABLE IF NOT EXISTS \"ola_mundo\".\"greetings\" ("
  ) == true
  assert contains?(
    sql,
    "ALTER TABLE \"ola_mundo\".\"greetings\" ADD COLUMN IF NOT EXISTS \"note\" text;"
  ) == true
  assert contains?(
    deployment("ola-mundo", "pleme-lib"),
    "OLA_MUNDO_DATABASE__URL"
  ) == true
end

test "a service with a cache mounts its password Secret as a file and names it in the environment"
  svc = assoc(sample, "cache", {})
  v = values_with(svc, :pleme_lib)
  assert v["cache"] ==
    {
      "enabled" => false,
      "host" => "",
      "port" => 6379,
      "passwordSecret" => "",
      "passwordKey" => "password"
    }
  assert values_with(sample, :pleme_lib)["cache"].nil?
  d = deployment_with("ola-mundo", "pleme-lib", svc)
  assert contains?(d, "OLA_MUNDO_CACHE__PASSWORD_FILE") == true
  assert contains?(d, "value: /var/run/secrets/ola-mundo-valkey/password") ==
    true
  assert contains?(d, "mountPath: /var/run/secrets/ola-mundo-valkey") == true
  assert contains?(d, "secretName: {{ required") == true
  plain = deployment("ola-mundo", "pleme-lib")
  assert contains?(plain, "valkey") == false
  assert contains?(plain, "volumes:") == false
  schema = values_schema("ola-mundo", svc)
  assert schema["properties"]["cache"]["additionalProperties"] == false
end

test "the chart carries the service's SLO rules, its dashboard and a scrape annotation"
  fs = files("hello", "0.1.0", sample)
  rules = second(
    first(filter((f) -> first(f) == "chart/templates/slo-rules.yaml", fs))
  )
  assert starts_with?(rules, unlines(["{{- if .Values.slo.rules }}"])) == true
  assert contains?(rules, "kind: \"PrometheusRule\"") == true
  assert contains?(rules, "SloLatencyBurn3d") == true
  assert contains?(rules, ".Release.Namespace") == true
  v = values(sample)
  assert v["podAnnotations"]["prometheus.io/port"] == "8080"
  assert v["slo"] == {"rules" => true, "dashboard" => true}
  vs = values_schema("hello", sample)["properties"]
  assert vs["slo"]["properties"]["rules"]["type"] == "boolean"
  assert catalog_entry("hello", "0.1.0", sample)["owner"] == "pleme-io"
end

test "nested settings reach the environment through one named template"
  svc = assoc(sample, "config", {"api" => {"auth" => {"mode" => "off"}}})
  d = deployment_with("ola-mundo", "pleme-lib", svc)
  assert contains?(d, "{{- define \"ola-mundo.env\" }}") == true
  assert contains?(d, "(list \"OLA_MUNDO_\" .Values.config)") == true
  assert contains?(d, "(list \"OLA_MUNDO_FLAGS__\" .Values.flags)") == true
  assert contains?(d, "range $k, $v := .Values.config") == false
  vs = values_schema("ola-mundo", svc)["properties"]["config"]
  assert get(
    vs["properties"]["api"]["properties"]["auth"]["properties"]["mode"],
    "type"
  ) == "string"
end

test "a host service's arguments become the chart's args, and a blue service has none"
  hosted = assoc(sample, "host_args", ["daemon", "--declaration"])
  assert values(hosted)["args"] == ["daemon", "--declaration"]
  assert values(sample)["args"] == []
  vs = values_schema("hello", hosted)["properties"]
  assert vs["args"]["type"] == "array"
end
