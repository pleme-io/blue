@moduledoc """
shihyou (指標) — indicator: a service's SLO as data, projected to the rules and the dashboard that watch it.

The availability and latency objectives have defaults, and a service's
Bluefile overrides each one alone. `rules` projects them to multi-window
burn-rate recording and alert rules, `dashboard` to a Grafana dashboard,
and `entry` to the service's catalog entry, all over kyuuji's /metrics
series.

    budget(99.5) #=> 0.005
"""

use("deeta", [:get_or])
use("kyuuji")
use("retsu", %i[first rest])

def defaults()
  {
    "availability" => 99.5,
    "latency" => 99,
    "latency_ms" => 250,
    "window_days" => 30
  }
end

def le_of(latency_ms)
  to_s(latency_ms / 1000)
end

@doc """
objectives: The objectives declared for a service.

    objectives(sample) #=> defaults
"""
def objectives(svc)
  given = get_or(svc, "slo", {})
  o = reduce(
    (acc, e) -> assoc(acc, first(e), second(e)),
    defaults,
    if given.nil?
      []
    else
      map_entries(given)
    end
  )
  le = le_of(o["latency_ms"])
  if member?(le, map((b) -> to_s(b), kyuuji::latency_bounds))
    o
  else
    raise(
      :latency_bound,
      "slo latency_ms #{to_s(o["latency_ms"])} is no histogram bound; the bounds are #{join(map((b) -> to_s(round(b * 1000)), kyuuji::latency_bounds), ", ")} ms"
    )
  end
end

@doc """
budget: the error budget left in a window.

    budget(0) #=> 1
"""
def budget(percent)
  (100 - percent) / 100
end

def windows()
  [
    {"severity" => "page", "long" => "1h", "short" => "5m", "factor" => 14.4},
    {"severity" => "page", "long" => "6h", "short" => "30m", "factor" => 6},
    {"severity" => "ticket", "long" => "1d", "short" => "2h", "factor" => 3},
    {"severity" => "ticket", "long" => "3d", "short" => "6h", "factor" => 1}
  ]
end

def ranges()
  %w[5m 30m 1h 2h 6h 1d 3d]
end

def selector(name)
  "service=\"#{name}\""
end

@doc """
error_ratio: The failing-request ratio over a window.

    error_ratio("hello", "5m") #=> "sum(rate(http_requests_total{service=\"hello\",code=\"5xx\"}[5m])) / sum(rate(http_requests_total{service=\"hello\"}[5m]))"
"""
def error_ratio(name, w)
  "sum(rate(http_requests_total{#{selector(name)},code=\"5xx\"}[#{w}])) / sum(rate(http_requests_total{#{selector(name)}}[#{w}]))"
end

@doc """
slow_ratio: The ratio of requests slower than a bound.

    slow_ratio("hello", "0.25", "1h") #=> "1 - sum(rate(http_request_duration_seconds_bucket{service=\"hello\",le=\"0.25\"}[1h])) / sum(rate(http_request_duration_seconds_count{service=\"hello\"}[1h]))"
"""
def slow_ratio(name, le, w)
  "1 - sum(rate(http_request_duration_seconds_bucket{#{selector(name)},le=\"#{le}\"}[#{w}])) / sum(rate(http_request_duration_seconds_count{#{selector(name)}}[#{w}]))"
end

def indicators(name, o)
  [
    [
      "availability",
      "slo:error_ratio:rate",
      (w) -> error_ratio(name, w),
      o["availability"]
    ],
    [
      "latency",
      "slo:slow_ratio:rate",
      (w) -> slow_ratio(name, le_of(o["latency_ms"]), w),
      o["latency"]
    ]
  ]
end

def recording(name, o)
  reduce(
    (acc, xs) -> append(acc, xs),
    [],
    map(
      fn(ind)
        map(
          fn(w)
            {
              "record" => "#{second(ind)}#{w}",
              "expr" => ind[2](w),
              "labels" => {"service" => name}
            }
          end,
          ranges
        )
      end,
      indicators(name, o)
    )
  )
end

def capitalized(s)
  "#{upcase(first(chars(s)))}#{join(rest(chars(s)), "")}"
end

@doc """
alerts: multi-window burn alerts for an objective.
"""
def alerts(name, o)
  reduce(
    (acc, xs) -> append(acc, xs),
    [],
    map(
      fn(ind)
        threshold = budget(ind[3])
        map(
          fn(w)
            limit = "(#{to_s(w["factor"])} * #{to_s(threshold)})"
            rec = second(ind)
            {
              "alert" => "Slo#{capitalized(first(ind))}Burn#{capitalized(w["long"])}",
              "expr" => "#{rec}#{w["long"]}{#{selector(name)}} > #{limit} and #{rec}#{w["short"]}{#{selector(name)}} > #{limit}",
              "labels" => {
                "severity" => w["severity"],
                "service" => name,
                "slo" => first(ind)
              },
              "annotations" => {
                "summary" => "#{name} is spending its #{first(ind)} error budget #{to_s(w["factor"])}x too fast over #{w["long"]} and #{w["short"]}",
                "objective" => "#{to_s(ind[3])}% over #{to_s(o["window_days"])}d"
              }
            }
          end,
          windows
        )
      end,
      indicators(name, o)
    )
  )
end

@doc """
rules: recording and alert rules derived from an objective.
"""
def rules(name, svc)
  o = objectives(svc)
  {
    "apiVersion" => "monitoring.coreos.com/v1",
    "kind" => "PrometheusRule",
    "metadata" => {
      "name" => "#{name}-slo",
      "labels" => {
        "app.kubernetes.io/name" => name,
        "app.kubernetes.io/component" => "slo"
      }
    },
    "spec" => {
      "groups" => [
        {"name" => "#{name}-slo-recording", "rules" => recording(name, o)},
        {"name" => "#{name}-slo-alerts", "rules" => alerts(name, o)}
      ]
    }
  }
end

def target(expr, legend)
  {
    "datasource" => {"type" => "prometheus", "uid" => "${datasource}"},
    "expr" => expr,
    "legendFormat" => legend,
    "refId" => "A"
  }
end

def panel(id, title, kind, x, y, targets, unit)
  {
    "id" => id,
    "type" => kind,
    "title" => title,
    "gridPos" => {"h" => 8, "w" => 12, "x" => x, "y" => y},
    "datasource" => {"type" => "prometheus", "uid" => "${datasource}"},
    "fieldConfig" => {"defaults" => {"unit" => unit}, "overrides" => []},
    "targets" => targets
  }
end

@doc """
dashboard: panels showing an objective, built from the same rules.
"""
def dashboard(name, svc)
  o = objectives(svc)
  s = selector(name)
  window = "#{to_s(o["window_days"])}d"
  {
    "uid" => "#{name}-slo",
    "title" => "#{name} service",
    "tags" => ["blue", "slo", name],
    "schemaVersion" => 39,
    "time" => {"from" => "now-6h", "to" => "now"},
    "templating" => {
      "list" => [
        {
          "name" => "datasource",
          "type" => "datasource",
          "query" => "prometheus",
          "label" => "Data source"
        }
      ]
    },
    "panels" => [
      panel(
        1,
        "Requests by status class",
        "timeseries",
        0,
        0,
        [
          target(
            "sum by (code) (rate(http_requests_total{#{s}}[5m]))",
            "{{code}}"
          )
        ],
        "reqps"
      ),
      panel(
        2,
        "Latency p50, p99",
        "timeseries",
        12,
        0,
        [
          target(
            "histogram_quantile(0.5, sum by (le) (rate(http_request_duration_seconds_bucket{#{s}}[5m])))",
            "p50"
          ),
          assoc(
            target(
              "histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{#{s}}[5m])))",
              "p99"
            ),
            "refId",
            "B"
          )
        ],
        "s"
      ),
      panel(
        3,
        "Availability over #{window} (objective #{to_s(o["availability"])}%)",
        "stat",
        0,
        8,
        [target("100 * (1 - (#{error_ratio(name, window)}))", "availability")],
        "percent"
      ),
      panel(
        4,
        "Error budget burn rate, 1h",
        "timeseries",
        12,
        8,
        [
          target(
            "slo:error_ratio:rate1h{#{s}} / #{to_s(budget(o["availability"]))}",
            "availability"
          ),
          assoc(
            target(
              "slo:slow_ratio:rate1h{#{s}} / #{to_s(budget(o["latency"]))}",
              "latency"
            ),
            "refId",
            "B"
          )
        ],
        "none"
      )
    ]
  }
end

def entry(name, version, svc)
  repo = svc["repository"]
  {
    "name" => name,
    "version" => version,
    "owner" => get_or(svc, "owner", split(repo, "/")[1]),
    "endpoints" => [
      {"name" => "http", "port" => svc["port"], "path" => "/"},
      {
        "name" => "health",
        "port" => svc["port"],
        "path" => get_or(svc, "probe", "/healthz")
      },
      {
        "name" => "metrics",
        "port" => svc["port"],
        "path" => kyuuji::metrics_path
      }
    ],
    "slo" => objectives(svc),
    "placement" => {
      "namespace" => get_or(svc, "namespace", name),
      "replicas" => get_or(svc, "replicas", 1)
    },
    "chart" => {
      "name" => name,
      "version" => version,
      "path" => "#{get_or(svc, "output", "deploy/#{name}")}/chart"
    },
    "image" => {"repository" => repo, "tag" => version}
  }
end

def sample()
  {
    "repository" => "ghcr.io/pleme-io/hello",
    "port" => 8080,
    "probe" => "/healthz"
  }
end

test "with no slo declared the objectives are the defaults"
  assert objectives(sample) == defaults
  assert objectives(assoc(sample, "slo", nil)) == defaults
end

test "a declared objective overrides only itself"
  o = objectives(
    assoc(sample, "slo", {"availability" => 99.9, "latency_ms" => 1000})
  )
  assert o["availability"] == 99.9
  assert o["latency_ms"] == 1000
  assert o["latency"] == 99
  assert le_of(1000) == "1"
end

test "a latency off the histogram bounds is refused by name"
  e = begin
    objectives(assoc(sample, "slo", {"latency_ms" => 300}))
  rescue e
    e
  end
  assert error?(e) == true
  assert contains?(e.message, "no histogram bound") == true
end

test "the rules record both ratios per window and alert on each multi-window pair"
  r = rules("hello", sample)
  groups = r["spec"]["groups"]
  rec = first(groups)["rules"]
  al = second(groups)["rules"]
  assert count(rec) == 14
  assert count(al) == 8
  assert first(rec)["record"] == "slo:error_ratio:rate5m"
  assert first(al)["expr"] ==
    "slo:error_ratio:rate1h{service=\"hello\"} > (14.4 * 0.005) and slo:error_ratio:rate5m{service=\"hello\"} > (14.4 * 0.005)"
  assert first(al)["alert"] == "SloAvailabilityBurn1h"
  assert contains?(rec[7]["expr"], "le=\"0.25\"") == true
end

test "the dashboard and the catalog entry read the same objectives"
  d = dashboard("hello", sample)
  assert d["uid"] == "hello-slo"
  assert count(d["panels"]) == 4
  assert contains?(d["panels"][2]["title"], "99.5%") == true
  e = entry("hello", "0.1.0", sample)
  assert e["owner"] == "pleme-io"
  assert e["slo"] == defaults
  assert e["image"]["tag"] == "0.1.0"
  assert e["endpoints"][2]["path"] == "/metrics"
  assert entry("hello", "0.1.0", assoc(sample, "owner", "edge"))["owner"] ==
    "edge"
end

test "budget is the share of requests an objective lets fail"
  assert budget(99.5) == 0.005
  assert budget(99) == 0.01
  assert budget(100) == 0
  assert budget(0) == 1
  assert budget(50) == 0.5
end

test "error_ratio is the 5xx rate over the total rate of one service in one window"
  assert error_ratio("hello", "5m") ==
    "sum(rate(http_requests_total{service=\"hello\",code=\"5xx\"}[5m])) / sum(rate(http_requests_total{service=\"hello\"}[5m]))"
  assert contains?(error_ratio("a-b", "3d"), "service=\"a-b\"")
  assert contains?(error_ratio("a-b", "3d"), "[3d]")
  assert contains?(error_ratio("a", "1h"), "service=\"b\"") == false
end

test "slow_ratio is one minus the share of requests within the bucket bound"
  assert slow_ratio("hello", "0.25", "1h") ==
    "1 - sum(rate(http_request_duration_seconds_bucket{service=\"hello\",le=\"0.25\"}[1h])) / sum(rate(http_request_duration_seconds_count{service=\"hello\"}[1h]))"
  assert contains?(slow_ratio("x", "1", "6h"), "le=\"1\"")
  assert contains?(slow_ratio("x", "1", "6h"), "[6h]")
end

test "alerts has a burn alert per window for each of the two indicators, in order"
  al = alerts("hello", objectives(sample))
  assert count(al) == 8
  assert map((a) -> a["alert"], al) ==
    %w[
      SloAvailabilityBurn1h
      SloAvailabilityBurn6h
      SloAvailabilityBurn1d
      SloAvailabilityBurn3d
      SloLatencyBurn1h
      SloLatencyBurn6h
      SloLatencyBurn1d
      SloLatencyBurn3d
    ]
  assert map((a) -> a["labels"]["severity"], take(4, al)) ==
    %w[page page ticket ticket]
end

test "alerts carry the service, the indicator and the objective they spend"
  al = alerts("hello", objectives(sample))
  a = first(al)
  assert a["labels"]["service"] == "hello"
  assert a["labels"]["slo"] == "availability"
  assert a["annotations"]["objective"] == "99.5% over 30d"
  assert al[4]["annotations"]["objective"] == "99% over 30d"
  assert contains?(
    a["annotations"]["summary"],
    "hello is spending its availability error budget 14.4x too fast over 1h and 5m"
  )
end

test "alerts threshold follows the declared objective and window"
  o = objectives(
    assoc(sample, "slo", {"availability" => 99, "window_days" => 7})
  )
  a = first(alerts("hello", o))
  assert contains?(a["expr"], "> (14.4 * 0.01)")
  assert a["annotations"]["objective"] == "99% over 7d"
  assert contains?(a["expr"], "service=\"hello\"")
end
