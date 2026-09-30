# checks.hello-virt32-qemu: boot the N0 image on QEMU riscv32 `virt` and read
# its serial console, then run the same program under the interpreter.
#
#   BOOT_ELF      the image
#   BOOT_PROGRAM  the blue program it was compiled from
#   BOOT_EXPECT   what both must print
#
# Red without the compiler (no image to boot), and red with a broken emitter
# (the image prints something else): the check reads the console, not the
# exit status alone.
use("kiban", [:kb_board])

def boot(elf)
  q = get(kb_board("qemu-virt32"), :qemu)
  r = exec_capture(
    "timeout",
    "60",
    get(q, :system),
    "-machine",
    get(q, :machine),
    "-bios",
    "none",
    "-nographic",
    "-monitor",
    "none",
    "-serial",
    "stdio",
    "-kernel",
    elf
  )
  [second(first(r)), second(second(r))]
end

def interpret(program)
  r = exec_capture(self_exe(), "run", "--quiet", program)
  [second(first(r)), second(second(r))]
end

test "the image prints the expected text on the UART and exits through the finisher"
  booted = boot(env_required("BOOT_ELF"))
  assert first(booted) == 0
  assert second(booted) == env_required("BOOT_EXPECT")
end

test "the image and the interpreter print the same text"
  assert second(boot(env_required("BOOT_ELF"))) ==
    second(interpret(env_required("BOOT_PROGRAM")))
end
