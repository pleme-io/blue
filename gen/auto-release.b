@moduledoc """
auto-release: blue's release workflow, rendered from blue (docs/TESTING.md T7). A push to main, a tick every 15 minutes and a hand dispatch each call substrate's `rust-auto-release.yml`, which bumps the shared workspace version, tags it and publishes each crate. The tick resumes a crates.io bootstrap across the registry's rate-limit refill and is a no-op once every crate is published. blue is a workspace with one `[workspace.package].version`, so the reusable is `rust-auto-release.yml`: `cargo-auto-release.yml` releases a single crate and stops at a workspace root.

    blue run gen/auto-release.b
"""

use("deeta", %i[parse yaml])

@doc """
source_paths: The paths whose change is a release. `blue-lang-pkg` compiles `bidamas/` into the crate, so a `.b` change is one. A git pathspec with no wildcard matches only at the root, so every path that appears at depth is written with `**/`.

    source_paths #=> "*.rs *.b **/Bluefile **/Cargo.toml **/Cargo.lock Cargo.gen.lock"
"""
def source_paths()
  join(%w[*.rs *.b **/Bluefile **/Cargo.toml **/Cargo.lock Cargo.gen.lock], " ")
end

@doc """
reusable: The release workflow this one calls.

    reusable #=> "pleme-io/substrate/.github/workflows/rust-auto-release.yml@main"
"""
def reusable()
  "pleme-io/substrate/.github/workflows/rust-auto-release.yml@main"
end

@doc """
workflow: The release workflow as data.

    workflow["name"] #=> "auto-release"
    workflow["on"]["schedule"] #=> [{"cron" => "*/15 * * * *"}]
"""
def workflow()
  {
    "name" => "auto-release",
    "on" => {
      "push" => {"branches" => ["main"]},
      "schedule" => [{"cron" => "*/15 * * * *"}],
      "workflow_dispatch" => {
        "inputs" => {
          "bump-type" => {
            "description" => "patch | minor | major",
            "required" => false,
            "default" => "patch"
          }
        }
      }
    },
    "jobs" => {
      "release" => {
        "uses" => reusable,
        "with" => {"source-paths" => source_paths, "release-ref-mode" => "tag"},
        "secrets" => "inherit"
      }
    }
  }
end

def main()
  write_file(
    getenv("GEN_OUT", ".github/workflows/auto-release.yml"),
    yaml(workflow)
  )
end

test "the rendered release workflow reads back as the workflow it renders", {
  kind: :rendering
}
  w = workflow
  assert parse(yaml(w), :yaml) == w
  assert w["jobs"]["release"]["with"]["release-ref-mode"] == "tag"
end

test "every source path that appears at depth carries its wildcard"
  bare = filter(
    (p) -> not contains?(p, "*") and p != "Cargo.gen.lock",
    split(source_paths, " ")
  )
  assert bare == []
end
