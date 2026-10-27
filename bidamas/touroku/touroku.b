@moduledoc """
touroku (登録) — registry: a project published to and resolved from registry backends, each a rendering of the Bluefile, never its truth.

    visibility_of(manifest_with(nil, {})) #=> "private"
"""

use("deeta", [:yaml])
use("kousei", [:entry, :field, :flag, :judge, :list_of, :one_of, :text])
use("kyohi", [:kinds, :refusal])
use("moji", [:is_hex, :strip_prefix])
use("retsu", [:contains, :first, :is_empty, :size])

def visibilities()
  ["public", "unlisted", "private"]
end

def built_backends()
  ["sui", "flakehub"]
end

def planned_backends()
  ["porto", "github"]
end

def backend_kinds()
  {"sui" => :sui, "flakehub" => :flakehub}
end

def schema()
  {
    sui: [
      field("outputs", list_of(text)),
      field("enabled", flag),
      field("output", text)
    ],
    flakehub: [
      field("tag", one_of(["rolling", "semver"])),
      field("directory", text),
      field("plan", one_of(["free", "paid"])),
      field("enabled", flag),
      field("output", text)
    ]
  }
end

def visibility_of(manifest)
  v = manifest["visibility"]
  if v.nil?
    "private"
  else
    v
  end
end

def spec_whys(backend, spec)
  if not map?(spec)
    ["the spec is not a record"]
  elsif spec["visibility"] != nil
    ["visibility is the package's, declared once in package(name, version, visibility); a registry entry never sets it"]
  elsif backend == "sui" and is_empty(spec["outputs"] or [])
    ["outputs is required: the flake packages whose closures sui serves"]
  else
    []
  end
end

def world_whys(backend, spec, visibility)
  if backend == "flakehub" and
      visibility == "private" and
      spec["plan"] != "paid"
    ["FlakeHub serves private flakes only on a paid org plan (a fact about FlakeHub, docs.determinate.systems/flakehub/concepts/visibility); declare plan: :paid once the org has one, or keep the private path, a git source"]
  else
    []
  end
end

def entries_of(manifest)
  regs = manifest["registries"] or {}
  map((p) -> [first(p), p[1]], map_entries(regs))
end

def entry_refusals(backend, spec, visibility)
  if contains(planned_backends, backend)
    [
      refusal(
        :not_built,
        "registry #{backend}: a row in docs/REGISTRY.md, not built yet"
      )
    ]
  elsif not contains(built_backends, backend)
    [
      refusal(
        :unknown_backend,
        "registry #{backend}: no such backend; built: #{join(built_backends, ", ")}"
      )
    ]
  else
    whys = spec_whys(backend, spec)
    pre = if is_empty(whys)
      world_whys(backend, spec, visibility)
    else
      []
    end
    shaped = if is_empty(whys)
      map(
        (r) -> refusal(:invalid, "registry #{backend}: #{r[1]}"),
        get(
          judge(schema, [entry(get(backend_kinds, backend), backend, spec)]),
          :refusals
        )
      )
    else
      []
    end
    append(
      map((w) -> refusal(:invalid, "registry #{backend}: #{w}"), whys),
      map((w) -> refusal(:world, "registry #{backend}: #{w}"), pre),
      shaped
    )
  end
end

def enabled?(spec)
  spec["enabled"] != false
end

def settle(manifest)
  visibility = visibility_of(manifest)
  judged = map(
    fn(p)
      backend = first(p)
      spec = p[1]
      {backend:, spec:, refusals: entry_refusals(backend, spec, visibility)}
    end,
    entries_of(manifest)
  )
  {
    visibility:,
    standing: map(
      (j) -> {backend: j[:backend], spec: j[:spec], on: enabled?(j[:spec])},
      filter((j) -> is_empty(j[:refusals]), judged)
    ),
    refusals: reduce((acc, j) -> append(acc, j[:refusals]), [], judged)
  }
end

def output_of(entry)
  entry[:spec]["output"]
end

def flakehub_visibility(visibility)
  if contains(visibilities, visibility)
    visibility
  else
    "private"
  end
end

def sui_workflow(entry)
  spec = entry[:spec]
  gate = if entry[:on]
    "${{ vars.SUI_MODE == 'on' }}"
  else
    false
  end
  {
    "name" => "registry-sui",
    "on" => {"push" => {"branches" => ["main"]}, "workflow_dispatch" => {}},
    "permissions" => {"contents" => "read"},
    "jobs" => {
      "publish" => {
        "if" => gate,
        "runs-on" => "${{ vars.PRIVATE_BUILDER_RUNNER || 'pleme-private' }}",
        "strategy" => {
          "fail-fast" => false,
          "matrix" => {"output" => spec["outputs"]}
        },
        "steps" => [
          {"uses" => "actions/checkout@v4"},
          {
            "id" => "build",
            "uses" => "pleme-io/actions/nix-build@main",
            "with" => {"flake-ref" => ".#${{ matrix.output }}"}
          },
          {
            "uses" => "pleme-io/actions/sui-cache-push@main",
            "with" => {"paths" => "${{ steps.build.outputs.out-path }}"}
          }
        ]
      }
    }
  }
end

def flakehub_workflow(manifest, entry)
  spec = entry[:spec]
  semver = spec["tag"] == "semver"
  trigger = if semver
    {"push" => {"tags" => ["v*"]}, "workflow_dispatch" => {}}
  else
    {"push" => {"branches" => ["main"]}, "workflow_dispatch" => {}}
  end
  job = {
    "uses" => "pleme-io/substrate/.github/workflows/reusable-flakehub.yml@main",
    "with" => {
      "visibility" => flakehub_visibility(visibility_of(manifest)),
      "rolling" => not semver,
      "directory" => spec["directory"] or "."
    }
  }
  {
    "name" => "registry-flakehub",
    "on" => trigger,
    "permissions" => {"contents" => "read", "id-token" => "write"},
    "jobs" => {
      "publish" => if entry[:on]
        job
      else
        assoc(job, "if", false)
      end
    }
  }
end

def workflow(manifest, entry)
  if entry[:backend] == "sui"
    sui_workflow(entry)
  else
    flakehub_workflow(manifest, entry)
  end
end

def render(manifest, backend)
  s = settle(manifest)
  hit = filter((e) -> e[:backend] == backend, s[:standing])
  if is_empty(hit)
    mine = filter(
      (r) -> starts_with?(r[1], "registry #{backend}:"),
      s[:refusals]
    )
    {
      refusals: if is_empty(mine)
        [
          refusal(
            :undeclared,
            "registry #{backend}: the Bluefile declares no such entry"
          )
        ]
      else
        mine
      end
    }
  else
    e = first(hit)
    {output: output_of(e), text: yaml(workflow(manifest, e))}
  end
end

def host_refusal(r)
  {kind: to_s(r[0]), why: r[1]}
end

def render_text(manifest_text, backend)
  r = render(json_read(manifest_text), backend)
  if r[:refusals] != nil
    {refusals: map(host_refusal, r[:refusals])}
  else
    r
  end
end

def backends_text(manifest_text)
  s = settle(json_read(manifest_text))
  {
    standing: map((e) -> e[:backend], s[:standing]),
    refusals: map(host_refusal, s[:refusals])
  }
end

def api_root()
  "https://api.flakehub.com"
end

def flakehub_request(url)
  flakehub = starts_with?(url, "flakehub:")
  parts = if flakehub
    split(strip_prefix(url, "flakehub:"), "/")
  else
    []
  end
  if not flakehub
    {refused: refusal(:not_flakehub, "#{url} is not a flakehub: url")}
  elsif size(parts) != 3 or any?((p) -> p == "", parts)
    {
      refused: refusal(
        :malformed,
        "#{url}: a FlakeHub source is flakehub:<org>/<project>/<range>"
      )
    }
  else
    org = parts[0]
    project = parts[1]
    range = parts[2]
    {
      org:,
      project:,
      range:,
      api: "#{api_root}/version/#{org}/#{project}/#{range}"
    }
  end
end

def revision?(r)
  string?(r) and length(r) == 40 and is_hex(r)
end

def answered(name, req, body)
  doc = json_read(body)
  revision = doc["revision"]
  version = doc["version"]
  fetch = doc["pretty_download_url"]
  if not map?(doc)
    {
      refused: refusal(
        :unreadable,
        "#{name}: the FlakeHub answer is not a record"
      )
    }
  elsif doc["yanked_at"] != nil
    {refused: refusal(:yanked, "#{name}: #{version} is yanked on FlakeHub")}
  elsif not revision?(revision)
    {
      refused: refusal(
        :unreadable,
        "#{name}: the FlakeHub answer has no 40-hex revision"
      )
    }
  elsif not (string?(version) and string?(fetch))
    {
      refused: refusal(
        :unreadable,
        "#{name}: the FlakeHub answer has no version or download url"
      )
    }
  elsif doc["org"] != req[:org] or doc["project"] != req[:project]
    {
      refused: refusal(
        :unreadable,
        "#{name}: FlakeHub answered for #{doc["org"]}/#{doc["project"]}"
      )
    }
  else
    {version:, revision:, fetch:}
  end
end

def credential_hint(credential)
  if credential.nil?
    "no credential file (determinate-nixd login writes /nix/var/determinate/netrc; BLUE_FLAKEHUB_NETRC names another)"
  else
    "the credential in #{credential}"
  end
end

def flakehub_pin(name, url, status, body, credential)
  req = flakehub_request(url)
  if req[:refused] != nil
    req
  elsif status == 200
    answered(name, req, body)
  elsif status == 401 or status == 403
    {
      refused: refusal(
        :credentials,
        "#{name}: FlakeHub refused #{credential_hint(credential)} (#{status})"
      )
    }
  elsif status == 404
    {
      refused: refusal(
        :absent,
        "#{name}: FlakeHub has no #{req[:org]}/#{req[:project]} matching #{req[:range]}, or it is private and #{credential_hint(credential)} does not reach it"
      )
    }
  else
    {
      refused: refusal(
        :unavailable,
        "#{name}: FlakeHub did not answer (#{status}); the lock keeps its pin"
      )
    }
  end
end

def sui_verdict(origin, status)
  if origin.nil? or origin == ""
    {
      state: :absent,
      why: "no sui origin on this host (SUI_CACHE_URL unset); builds fetch and build locally"
    }
  elsif status == 0
    {state: :warm, why: "#{origin} serves the pinned tree"}
  elsif status == 1
    {
      state: :cold,
      why: "#{origin} does not hold the pinned tree yet; builds fetch it"
    }
  else
    {
      state: :absent,
      why: "#{origin} did not answer (#{status}); builds fetch and build locally"
    }
  end
end

def recorded_version()
  "{\"org\":\"DeterminateSystems\",\"project\":\"flake-checker\",\"visibility\":\"public\",\"description\":null,\"revision\":\"9ffd1b0af33ab1d18f1a1903d5f351af8ede16ea\",\"repo_url\":\"https://github.com/DeterminateSystems/flake-checker\",\"source_subdirectory\":null,\"version\":\"0.1.20\",\"simplified_version\":\"0.1.20\",\"commit_count\":483,\"mirrored\":false,\"spdx_identifier\":\"Apache-2.0\",\"created_at\":\"2024-07-01T17:02:15.804321Z\",\"updated_at\":\"2024-07-01T17:02:16.287229Z\",\"published_at\":\"2024-07-01T17:02:16.505994Z\",\"yanked_at\":null,\"download_url\":\"https://api.flakehub.com/f/DeterminateSystems/flake-checker/0.1.20.tar.gz\",\"pretty_download_url\":\"https://flakehub.com/f/DeterminateSystems/flake-checker/0.1.20.tar.gz\",\"source_github_owner_repo_pair\":\"DeterminateSystems/flake-checker\"}"
end

def recorded_absent()
  "\"Flake `pleme-io/blue/*` not found.\\n\\nEither it doesn't exist (did you make a typo?), or you do not have adequate permissions to see it (are you logged in to FlakeHub?).\\n\""
end

def checker()
  "flakehub:DeterminateSystems/flake-checker/0.1.*"
end

def manifest_with(visibility, registries)
  base = {"name" => "p", "version" => "0.1.0", "registries" => registries}
  if visibility.nil?
    base
  else
    assoc(base, "visibility", visibility)
  end
end

def fh(spec)
  manifest_with("public", {"flakehub" => spec})
end

test "a range resolves to the recorded exact version and revision"
  p = flakehub_pin("checker", checker, 200, recorded_version, nil)
  assert p[:version] == "0.1.20"
  assert p[:revision] == "9ffd1b0af33ab1d18f1a1903d5f351af8ede16ea"
  assert p[:fetch] ==
    "https://flakehub.com/f/DeterminateSystems/flake-checker/0.1.20.tar.gz"
end

test "the request names the version endpoint"
  r = flakehub_request(checker)
  assert r[:api] ==
    "https://api.flakehub.com/version/DeterminateSystems/flake-checker/0.1.*"
  assert kinds([flakehub_request("flakehub:a/b")[:refused]]) == [:malformed]
  assert kinds([flakehub_request("github:a/b")[:refused]]) == [:not_flakehub]
end

test "absence, credentials and an outage are typed refusals of the one source"
  assert first(
    get(
      flakehub_pin("b", "flakehub:pleme-io/blue/*", 404, recorded_absent, nil),
      :refused
    )
  ) == :absent
  assert first(flakehub_pin("b", checker, 401, "", "/run/netrc")[:refused]) ==
    :credentials
  assert first(flakehub_pin("b", checker, 0, "", nil)[:refused]) == :unavailable
  assert first(flakehub_pin("b", checker, 503, "", nil)[:refused]) ==
    :unavailable
end

test "a yanked, foreign or revisionless answer is refused, not pinned"
  doc = json_read(recorded_version)
  yanked = json_stringify(assoc(doc, "yanked_at", "2026-01-01T00:00:00Z"))
  assert first(flakehub_pin("c", checker, 200, yanked, nil)[:refused]) ==
    :yanked
  short = json_stringify(assoc(doc, "revision", "9ffd1b0"))
  assert first(flakehub_pin("c", checker, 200, short, nil)[:refused]) ==
    :unreadable
  other = json_stringify(assoc(doc, "project", "nix"))
  assert first(flakehub_pin("c", checker, 200, other, nil)[:refused]) ==
    :unreadable
end

test "a private package never renders public, on any tag"
  map(
    fn(tag)
      r = render(
        manifest_with(
          "private",
          {"flakehub" => {"tag" => tag, "plan" => "paid"}}
        ),
        "flakehub"
      )
      assert contains?(r[:text], "visibility: \"private\"")
      assert not contains?(r[:text], "\"public\"")
    end,
    ["rolling", "semver"]
  )
end

test "an undeclared visibility is private"
  assert visibility_of(manifest_with(nil, {})) == "private"
  r = render(manifest_with(nil, {"flakehub" => {"plan" => "paid"}}), "flakehub")
  assert contains?(r[:text], "visibility: \"private\"")
end

test "public and unlisted render as declared"
  assert contains?(render(fh({}), "flakehub")[:text], "visibility: \"public\"")
  u = render(manifest_with("unlisted", {"flakehub" => {}}), "flakehub")
  assert contains?(u[:text], "visibility: \"unlisted\"")
end

test "a registry entry that sets visibility is refused alone"
  m = manifest_with(
    "private",
    {
      "flakehub" => {"visibility" => "public"},
      "sui" => {"outputs" => ["default"]}
    }
  )
  s = settle(m)
  assert kinds(s[:refusals]) == [:invalid]
  assert map((e) -> e[:backend], s[:standing]) == ["sui"]
end

test "private on FlakeHub without a paid plan is refused as a world fact"
  s = settle(manifest_with("private", {"flakehub" => {}}))
  assert kinds(s[:refusals]) == [:world]
  assert is_empty(s[:standing])
end

test "sui renders a gated publish of each output through sui-cache-push"
  r = render(
    manifest_with("private", {"sui" => {"outputs" => ["default", "blue"]}}),
    "sui"
  )
  t = r[:text]
  assert r[:output].nil?
  o = render(
    manifest_with(
      "private",
      {"sui" => {"outputs" => ["x"], "output" => "ci/sui.yml"}}
    ),
    "sui"
  )
  assert o[:output] == "ci/sui.yml"
  assert contains?(t, "pleme-io/actions/sui-cache-push@main")
  assert contains?(t, "vars.SUI_MODE == 'on'")
  assert contains?(t, "- \"blue\"")
  assert not contains?(t, "rio")
end

test "sui needs its outputs"
  s = settle(manifest_with("public", {"sui" => {}}))
  assert kinds(s[:refusals]) == [:invalid]
end

test "configured off renders the job with a false gate"
  r = render(
    manifest_with(
      "public",
      {"sui" => {"outputs" => ["x"], "enabled" => false}}
    ),
    "sui"
  )
  assert contains?(r[:text], "if: false")
  f = render(fh({"enabled" => false}), "flakehub")
  assert contains?(f[:text], "if: false")
  assert not contains?(render(fh({}), "flakehub")[:text], "if: false")
end

test "semver publishes on tags, rolling on main"
  s = render(fh({"tag" => "semver"}), "flakehub")[:text]
  assert contains?(s, "rolling: false")
  assert contains?(s, "- \"v*\"")
  r = render(fh({}), "flakehub")[:text]
  assert contains?(r, "rolling: true")
end

test "planned and unknown backends are refused by kind"
  s = settle(
    manifest_with(
      "public",
      {"porto" => {}, "npm" => {}, "sui" => {"outputs" => ["x"]}}
    )
  )
  assert kinds(s[:refusals]) == [:unknown_backend, :not_built]
  assert size(s[:standing]) == 1
end

test "rendering an undeclared backend names it"
  assert kinds(render(manifest_with("public", {}), "sui")[:refusals]) ==
    [:undeclared]
end

test "a sui probe never fails a build"
  assert sui_verdict(nil, 0)[:state] == :absent
  assert sui_verdict("http://o:5000", 0)[:state] == :warm
  assert sui_verdict("http://o:5000", 1)[:state] == :cold
  assert sui_verdict("http://o:5000", 7)[:state] == :absent
end
