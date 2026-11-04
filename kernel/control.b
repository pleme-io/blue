@moduledoc """
control: The test file every `vm_check` of the kernel suites must see fail. Its first test passes against the real kernel, its second asserts an answer the kernel does not give, so its tally of one and one shows the machine loaded a program and a red reached the exit status. `checks.vm-kernel-*` is not green unless this file is red.

    blue test --allow host kernel/control.b
"""

use("bpf", %i[alu assemble exit_program])

use("kaaneru", %i[load run])

use("retsu", [:repeat])

def answer()
  get(
    run(
      load(
        assemble([alu(:mov, 0, 2), exit_program]),
        {kind: :xdp, name: "control"}
      ),
      {packet: repeat(0, 64)}
    ),
    :ret
  )
end

test "the kernel answers what the program returns"
  assert answer == 2
end

test "this one is wrong on purpose, and must stay red"
  assert answer == 1
end
