@moduledoc """
ci: blue's CI workflow, rendered from blue (docs/TESTING.md T5). The workflow
holds no logic of its own: it builds blue once, then hands each question to the
blue binary or to nix. The `check` job is substrate's `cargo-ci.yml`, because
it carries the git credentials a private pleme-io git dependency needs; that
job runs `nix flake check` (every `check` row of the Bluefile, whatever its
stage) and `cargo test`, which the suite proof (`gen/proof.b`) may skip. A land
also runs the first gates (`gen/prepush.b --first-gates`), the consumer sweep
(`gen/consumers.b`) and the stop-on-red watcher (`gen/land.b`).

    blue run gen/ci.b
"""

use("deeta", %i[parse yaml])

use("retsu", %i[first last reject])

@doc """
blue_out: The expression a step reads the built blue's store path from.

    blue_out #=> "${{ steps.blue.outputs.out-path }}"
"""
def blue_out()
  "${{ steps.blue.outputs.out-path }}"
end

@doc """
held: The condition every job after the first holds to: the land run holds
the land turn, or the run is no land.

    held #=> "needs.blue.outputs.held != 'false'"
"""
def held()
  "needs.blue.outputs.held != 'false'"
end

@doc """
on_land: A job condition that also asks the run to be a push to a land ref,
unless the repository variable `name` is off.

    on_land("BLUE_LAND_STOP_ON_RED") #=> "${{ needs.blue.outputs.held != 'false' && github.event_name == 'push' && startsWith(github.ref_name, 'land/') && vars.BLUE_LAND_STOP_ON_RED != 'off' }}"
"""
def on_land(name)
  "${{ #{held} && github.event_name == 'push' && startsWith(github.ref_name, 'land/') && vars.#{name} != 'off' }}"
end

@doc """
build_blue: The step that builds blue from this checkout, as `steps.blue`.

    build_blue["uses"] #=> "pleme-io/actions/nix-build@main"
"""
def build_blue()
  {
    "id" => "blue",
    "uses" => "pleme-io/actions/nix-build@main",
    "with" => {
      "flake-ref" => ".#default",
      "github-token" => "${{ secrets.GITHUB_TOKEN }}"
    }
  }
end

@doc """
from_closure: The steps a later job takes to build blue: nix, then the closure
the first job exported, then the build, which the closure answers.

    count(from_closure) #=> 5
"""
def from_closure()
  [
    {"uses" => "actions/checkout@v4"},
    {
      "uses" => "pleme-io/actions/nix-setup@main",
      "with" => {"github-token" => "${{ secrets.GITHUB_TOKEN }}"}
    },
    {
      "uses" => "actions/download-artifact@v4",
      "continue-on-error" => true,
      "with" => {
        "name" => "blue-closure",
        "path" => "${{ runner.temp }}/blue-closure"
      }
    },
    {
      "continue-on-error" => true,
      "run" => "nix copy --from \"file://$RUNNER_TEMP/blue-closure\" --no-check-sigs \"$(cat \"$RUNNER_TEMP/blue-closure/out-path\")\""
    },
    build_blue
  ]
end

@doc """
blue_job: The first job: build blue, take the land turn on a land, read the
suite proof, and export the closure for the jobs that build it again.

    blue_job["outputs"]["held"] #=> "${{ steps.turn.outputs.held }}"
"""
def blue_job()
  {
    "runs-on" => "ubuntu-latest",
    "permissions" => {"contents" => "read", "actions" => "read"},
    "outputs" => {
      "proven" => "${{ steps.proof.outputs.proven }}",
      "held" => "${{ steps.turn.outputs.held }}"
    },
    "steps" => [
      {"uses" => "actions/checkout@v4"},
      build_blue,
      {
        "name" => "take the land turn before the suite runs",
        "id" => "turn",
        "if" => "${{ github.event_name == 'push' && startsWith(github.ref_name, 'land/') && !startsWith(github.ref_name, 'land/dry-') && vars.BLUE_LAND_TURN != 'off' }}",
        "env" => {
          "GH_TOKEN" => "${{ github.token }}",
          "BLUE_LAND_BATCH" => "${{ vars.BLUE_LAND_BATCH }}"
        },
        "run" => join_lines(
          [
            "held=\"$(#{blue_out}/bin/blue run --quiet gen/land.b -- --turn \"$GITHUB_RUN_ID\" \"$GITHUB_REF_NAME\" \"$GITHUB_SHA\")\"",
            "echo \"held=$held\" >> \"$GITHUB_OUTPUT\""
          ]
        )
      },
      {
        "name" => "read the suite proof noted on this commit",
        "id" => "proof",
        "continue-on-error" => true,
        "run" => "echo \"proven=$(#{blue_out}/bin/blue run --quiet gen/proof.b -- --verify HEAD)\" >> \"$GITHUB_OUTPUT\""
      },
      {
        "name" => "export blue's closure for the jobs that build it again",
        "continue-on-error" => true,
        "env" => {"OUT" => blue_out},
        "run" => join_lines(
          [
            "nix copy --to \"file://$RUNNER_TEMP/blue-closure?compression=zstd\" \"$OUT\"",
            "echo \"$OUT\" > \"$RUNNER_TEMP/blue-closure/out-path\""
          ]
        )
      },
      {
        "uses" => "actions/upload-artifact@v4",
        "continue-on-error" => true,
        "with" => {
          "name" => "blue-closure",
          "path" => "${{ runner.temp }}/blue-closure",
          "retention-days" => 1
        }
      }
    ]
  }
end

@doc """
check_job: substrate's cargo-ci flow: `nix flake check` in shards, and `cargo
test` unless the suite proof covers this commit.

    check_job["uses"] #=> "pleme-io/substrate/.github/workflows/cargo-ci.yml@main"
"""
def check_job()
  {
    "needs" => "blue",
    "if" => "${{ #{held} }}",
    "uses" => "pleme-io/substrate/.github/workflows/cargo-ci.yml@main",
    "with" => {
      "test-args" => "--workspace --no-fail-fast",
      "runner" => "${{ (github.event_name == 'push' || github.event_name == 'workflow_dispatch') && vars.BLUE_LAND_RUNNER || '' }}",
      "test-runner" => "ubuntu-latest",
      "cargo-test" => "${{ needs.blue.outputs.proven != 'true' }}",
      "closure-artifact" => "blue-closure",
      "flake-check-shards" => "${{ fromJSON(vars.BLUE_FLAKE_CHECK_SHARDS || '6') }}"
    },
    "secrets" => "inherit"
  }
end

@doc """
first_gates_job: On a land, the gates `gen/prepush.b --first-gates` names, so
a red one stops the run minutes in.

    first_gates_job["if"] #=> on_land("BLUE_LAND_FIRST_GATES")
"""
def first_gates_job()
  {
    "needs" => "blue",
    "if" => on_land("BLUE_LAND_FIRST_GATES"),
    "runs-on" => "ubuntu-latest",
    "steps" => append(
      from_closure,
      [
        {
          "id" => "gates",
          "env" => {"BLUE" => "#{blue_out}/bin/blue"},
          "run" => join_lines(
            [
              "echo \"checks=$(\"$BLUE\" run --quiet gen/prepush.b -- --first-gates x86_64-linux)\" >> \"$GITHUB_OUTPUT\"",
              "dirname \"$BLUE\" >> \"$GITHUB_PATH\""
            ]
          )
        },
        {
          "uses" => "pleme-io/actions/nix-flake-check@main",
          "with" => {
            "only" => "${{ steps.gates.outputs.checks }}",
            "github-token" => "${{ secrets.GITHUB_TOKEN }}"
          }
        }
      ]
    )
  }
end

@doc """
consumers_job: Every consumer of blue checked at this blue (`gen/consumers.b
sweep`).

    contains?(last(consumers_job["steps"])["run"], "gen/consumers.b sweep --clone") #=> true
"""
def consumers_job()
  {
    "needs" => "blue",
    "if" => "${{ #{held} }}",
    "runs-on" => "ubuntu-latest",
    "steps" => append(
      from_closure,
      [
        {
          "run" => "#{blue_out}/bin/blue gen/consumers.b sweep --clone \"$RUNNER_TEMP/consumers\""
        }
      ]
    )
  }
end

@doc """
stop_on_red_job: On a land, a watcher that cancels the run at the first red
job (`gen/land.b --stop-on-red`).

    stop_on_red_job["permissions"]["actions"] #=> "write"
"""
def stop_on_red_job()
  {
    "needs" => "blue",
    "if" => on_land("BLUE_LAND_STOP_ON_RED"),
    "continue-on-error" => true,
    "runs-on" => "ubuntu-latest",
    "permissions" => {"contents" => "read", "actions" => "write"},
    "steps" => append(
      from_closure,
      [
        {
          "env" => {"GH_TOKEN" => "${{ github.token }}"},
          "run" => "#{blue_out}/bin/blue run --quiet gen/land.b -- --stop-on-red \"$GITHUB_RUN_ID\""
        }
      ]
    )
  }
end

@doc """
jobs_of: The jobs, from the lock's manifest: the consumer sweep runs only when
the Bluefile declares the `consumers` check that holds its program.

    map(first, map_entries(jobs_of({"checks" => {"consumers" => {}}}))) #=> ["blue", "check", "consumers", "first-gates", "stop-on-red"]
    map(first, map_entries(jobs_of({"checks" => {}}))) #=> ["blue", "check", "first-gates", "stop-on-red"]
"""
def jobs_of(manifest)
  base = {
    "blue" => blue_job,
    "check" => check_job,
    "first-gates" => first_gates_job,
    "stop-on-red" => stop_on_red_job
  }
  if (manifest["checks"] or {})["consumers"].nil?
    base
  else
    assoc(base, "consumers", consumers_job)
  end
end

@doc """
workflow: The whole workflow: on a push to main, a pull request, by hand, and
as the reusable flow land.yml calls, whose `held` output says whether the
land holds its turn.

    workflow({})["name"] #=> "ci"
    workflow({})["on"]["workflow_call"]["outputs"]["held"]["value"] #=> "${{ jobs.blue.outputs.held }}"
"""
def workflow(manifest)
  {
    "name" => "ci",
    "on" => {
      "push" => {"branches" => ["main"]},
      "pull_request" => {"branches" => ["main"]},
      "workflow_dispatch" => {},
      "workflow_call" => {
        "outputs" => {
          "held" => {
            "description" => "false when a land run does not hold the land turn (gen/land.b --turn); empty otherwise",
            "value" => "${{ jobs.blue.outputs.held }}"
          }
        }
      }
    },
    "permissions" => {"contents" => "read"},
    "jobs" => jobs_of(manifest)
  }
end

@doc """
hand_workflows: The workflows still written by hand: debt that only shrinks. A
workflow leaves this list when a `generate` row renders it; a new workflow is
rendered from its first commit.

    count(hand_workflows) #=> 6
"""
def hand_workflows()
  %w[
    .github/workflows/gen-spec.yml
    .github/workflows/land.yml
    .github/workflows/post-merge.yml
    .github/workflows/registry-flakehub.yml
    .github/workflows/registry-sui.yml
    .github/workflows/runner-overflow.yml
  ]
end

@doc """
unrendered: The workflow files no `generate` row renders and the hand list
does not hold: each is refused.

    unrendered([".github/workflows/a.yml", ".github/workflows/b.yml"], [".github/workflows/a.yml"], []) #=> [".github/workflows/b.yml"]
    unrendered([".github/workflows/b.yml"], [], [".github/workflows/b.yml"]) #=> []
"""
def unrendered(files, outputs, hand)
  reject((f) -> member?(f, outputs) or member?(f, hand), files)
end

@doc """
stale_hand: The hand list's entries that a `generate` row now renders or that
no longer exist: each must leave the list, so the debt shrinks as it is paid.

    stale_hand([".github/workflows/a.yml"], [".github/workflows/a.yml"], [".github/workflows/a.yml", ".github/workflows/gone.yml"]) #=> [".github/workflows/a.yml", ".github/workflows/gone.yml"]
"""
def stale_hand(files, outputs, hand)
  filter((h) -> member?(h, outputs) or not member?(h, files), hand)
end

@doc """
workflow_files: The workflow files under a project root, as project paths.

    workflow_files("/nonexistent") #=> []
"""
def workflow_files(root)
  dir = path_join(root, ".github/workflows")
  if is_dir?(dir)
    sort_keyed(
      (f) -> f,
      map(
        (f) -> ".github/workflows/#{path_basename(f)}",
        filter((f) -> ends_with?(f, ".yml") or ends_with?(f, ".yaml"), ls(dir))
      )
    )
  else
    []
  end
end

def manifest()
  lock = path_join(getenv("GEN_ROOT", "."), "Bluefile.lock")
  json_read(read_file(lock))["manifest"]
end

def main()
  write_file(
    getenv("GEN_OUT", ".github/workflows/ci.yml"),
    yaml(workflow(manifest))
  )
end

test "the rendered workflow reads back as the workflow it renders", {
  kind: :rendering
}
  w = workflow({"checks" => {"consumers" => {}}})
  assert parse(yaml(w), :yaml) == w
end

test "every job after the first waits on blue and on the land turn"
  jobs = jobs_of({"checks" => {"consumers" => {}}})
  later = filter((e) -> first(e) != "blue", map_entries(jobs))
  assert count(later) == 4
  assert every?((e) -> last(e)["needs"] == "blue", later)
  assert every?((e) -> contains?(last(e)["if"], held), later)
end

test "a project with no consumers check renders no sweep"
  assert jobs_of({})["consumers"].nil?
end

test "every workflow is rendered by a generate row or held as hand debt, and paid debt leaves the list"
  root = getenv("GEN_ROOT", ".")
  files = workflow_files(root)
  outputs = map((e) -> last(e)["output"], map_entries(manifest["generated"]))
  assert member?(".github/workflows/ci.yml", outputs)
  assert unrendered(files, outputs, hand_workflows) == []
  assert stale_hand(files, outputs, hand_workflows) == []
end

test "a workflow written by hand outside the list is refused, and a rendered one may not stay on it"
  files = %w[.github/workflows/ci.yml .github/workflows/new.yml]
  outputs = [".github/workflows/ci.yml"]
  assert unrendered(files, outputs, []) == [".github/workflows/new.yml"]
  assert stale_hand(files, outputs, [".github/workflows/ci.yml"]) ==
    [".github/workflows/ci.yml"]
end
