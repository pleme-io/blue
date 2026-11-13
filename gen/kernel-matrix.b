@moduledoc """
kernel-matrix: The workflow that boots each kernel a Bluefile's `vm_check` names, on a hosted runner with KVM. It runs on a schedule, by hand, on a `kernel-matrix/**` branch and after a push to main that touches the kernel, so a land waits on none of it.

    blue run gen/kernel-matrix.b
"""

# waive B0085: rendering debt recorded 2026-11-13: no test of this generator declared kind: :rendering feeds its output to the output's reader yet
use("deeta", [:yaml])

use("retsu", [:first])

@doc """
kernels_of: Each `vm_check` kernel of a manifest, as the name its package carries.

    kernels_of({"vm_checks" => {"k" => {"kernels" => {"a" => {}, "b" => {}}}}}) #=> ["vm-k-a", "vm-k-b"]
    kernels_of({}) #=> []
"""
def kernels_of(manifest)
  checks = json_get(manifest, :vm_checks)
  if checks.nil?
    []
  else
    retsu::flat_map(
      map_entries(checks),
      fn(c)
        map(
          (k) -> "vm-#{first(c)}-#{first(k)}",
          map_entries(json_get(second(c), :kernels))
        )
      end
    )
  end
end

@doc """
triggers: When the matrix runs: never on a land's own branch.

    triggers(["kernel/**"])["push"]["branches"] #=> ["main", "kernel-matrix/**"]
    triggers(["kernel/**"])["schedule"] #=> [{"cron" => "17 6 * * *"}]
"""
def triggers(paths)
  {
    "schedule" => [{"cron" => "17 6 * * *"}],
    "workflow_dispatch" => {},
    "push" => {"branches" => %w[main kernel-matrix/**], "paths" => paths}
  }
end

@doc """
workflow: The whole workflow for these packages.

    workflow(["vm-k-a"])["jobs"]["machine"]["strategy"]["matrix"]["kernel"] #=> ["vm-k-a"]
"""
def workflow(kernels)
  {
    "name" => "kernel-matrix",
    "on" => triggers(
      %w[
        kernel/**
        bidamas/baito/**
        bidamas/kaaneru/bpf/**
        bidamas/kaaneru/btf/**
        bidamas/kaaneru/erufu/**
        bidamas/kaaneru/**
        crates/blue-lang-kernel/**
        nix/vm-*
        .github/workflows/kernel-matrix.yml
      ]
    ),
    "permissions" => {"contents" => "read"},
    "jobs" => {
      "machine" => {
        "runs-on" => "ubuntu-latest",
        "timeout-minutes" => 340,
        "strategy" => {"fail-fast" => false, "matrix" => {"kernel" => kernels}},
        "steps" => [
          {"uses" => "actions/checkout@v4"},
          {"name" => "open /dev/kvm", "run" => "sudo chmod 666 /dev/kvm"},
          {
            "id" => "build",
            "uses" => "pleme-io/actions/nix-build@main",
            "with" => {
              "flake-ref" => ".#${{ matrix.kernel }}",
              "github-token" => "${{ secrets.GITHUB_TOKEN }}",
              "extra-conf" => "extra-system-features = kvm nixos-test",
              "max-silent-time" => "1800"
            }
          },
          {
            "name" => "the kernel booted and its tallies",
            "run" => join_lines(
              [
                "cat ${{ steps.build.outputs.out-path }}/vm-*.log",
                "cat ${{ steps.build.outputs.out-path }}/vm-*.log >> \"$GITHUB_STEP_SUMMARY\""
              ]
            )
          },
          {
            "name" => "the machine's log, on a red",
            "if" => "failure()",
            "run" => "nix log .#${{ matrix.kernel }} > \"$RUNNER_TEMP/machine.log\"; cat \"$RUNNER_TEMP/machine.log\""
          }
        ]
      }
    }
  }
end

def main()
  lock = path_join(getenv("GEN_ROOT", "."), "Bluefile.lock")
  manifest = json_get(json_read(read_file(lock)), :manifest)
  write_file(
    getenv("GEN_OUT", ".github/workflows/kernel-matrix.yml"),
    yaml(workflow(kernels_of(manifest)))
  )
end

test "every kernel a manifest names is one job, and a manifest with none has none"
  m = {"vm_checks" => {"k" => {"kernels" => {"six" => {}, "seven" => {}}}}}
  assert member?("vm-k-six", kernels_of(m))
  assert member?("vm-k-seven", kernels_of(m))
  assert kernels_of({}) == []
  jobs = workflow(kernels_of(m))["jobs"]["machine"]
  assert count(jobs["strategy"]["matrix"]["kernel"]) == 2
end

test "the workflow never runs on a land's branch"
  on = triggers(["kernel/**"])
  assert not member?("land/**", on["push"]["branches"])
  assert on["push"]["paths"] == ["kernel/**"]
end
