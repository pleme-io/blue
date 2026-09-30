# kiban (基板, the circuit board): typed board specs for blue native, and the
# host's model of the words a board gives a program.
#
# theory/BLUE-NATIVE.md §1.6. A board spec is data, authored in blue: the ISA
# and the rustc target it lowers to, the word width, the memory regions, the
# devices, how QEMU boots it, and the position ceiling it imposes on every
# program built for it. N0 has one board, QEMU `virt` riscv32; N1 moves the
# spec behind a `board` Bluefile word and a TataraDomain border.
#
# `mmio_write(addr, width, value)` is the one board word at N0. Compiled for a
# board, it is the seam's volatile store; run under `blue run`, it is this
# file's model of the same board, so the interpreter prints what the image's
# UART prints. That is the parity amendment's first row (BLUE-NATIVE.md,
# Review §1): one program, two executions, one output.

# A memory region: a name, a start address, a length in bytes.
def kb_region(name, origin, length)
  {name: name, origin: origin, length: length}
end

# A memory-mapped device: what it is and where its registers start.
def kb_device(name, kind, base)
  {name: name, kind: kind, base: base}
end

# The position a board imposes on every program built for it (the root
# ceiling, §2.1): restricted rigor, no evaluator, no collector, static places,
# monomorphic representation.
def kb_native_ceiling()
  {
    rigor: :restricted,
    evaluator: :absent,
    collector: :absent,
    where: :static,
    representation: :monomorphic
  }
end

# QEMU's `virt` machine with a 32-bit RISC-V hart (T1): an NS16550 UART at
# 0x10000000 and the SiFive test finisher at 0x100000, whose 0x5555 ends QEMU
# with status 0 and (code << 16) | 0x3333 with status `code`.
def kb_qemu_virt32()
  {
    name: "qemu-virt32",
    isa: :rv32imac,
    rust_target: "riscv32imac-unknown-none-elf",
    word: 32,
    memory: [kb_region(:ram, 2147483648, 131072)],
    devices: [
      kb_device(:uart0, :ns16550, 268435456),
      kb_device(:finisher, :sifive_test, 1048576)
    ],
    qemu: {system: "qemu-system-riscv32", machine: "virt", cpu: "rv32"},
    ceiling: kb_native_ceiling()
  }
end

# Every board this package knows, by name.
def kb_boards()
  [kb_qemu_virt32()]
end

# The board named `name`, or nil.
def kb_board(name)
  find(fn(b) get(b, :name) == name end, kb_boards())
end

# The base address of the board's device named `name`, or nil.
def kb_device_base(board, name)
  d = find(fn(x) get(x, :name) == name end, get(board, :devices))
  if d == nil
    nil
  else
    get(d, :base)
  end
end

# The printable ASCII range, in order from code 32, for the UART model.
def kb_ascii()
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
end

# The character a UART prints for byte `c`: printable ASCII and newline. Any
# other byte is refused rather than guessed at.
def kb_char(c)
  if c == 10
    "\n"
  elsif c >= 32 && c < 127
    nth(c - 32, chars(kb_ascii()))
  else
    throw(error(:kiban, "the UART model prints ASCII only, got #{c}"))
  end
end

# The host's model of a store to a board register, against the QEMU virt32
# board: a byte to the UART is printed; a store to the finisher is the end of
# the program, which on the host is simply the end of the run. Any other
# address is a device the model does not have, and is refused.
def mmio_write(addr, width, value)
  board = kb_qemu_virt32()
  if !(width == 8 || width == 32)
    throw(error(:kiban, "mmio_write width is 8 or 32, got #{width}"))
  elsif addr == kb_device_base(board, :uart0)
    write_stdout(kb_char(value))
  elsif addr == kb_device_base(board, :finisher)
    nil
  else
    throw(error(:kiban, "no device at #{addr} on #{get(board, :name)}"))
  end
end

# a + b modulo 2^32: wrapping arithmetic, only where a program asks for it by
# name. Plain + is checked everywhere (overflow is a fault on the board); this
# word is the one way to wrap, and it lowers to u32::wrapping_add.
def wrapping_add(a, b)
  (a + b) % 4294967296
end

test "wrapping_add wraps at the board word"
  assert wrapping_add(4294967295, 1) == 0
  assert wrapping_add(2, 3) == 5
end

test "the virt32 board is found by name and an unknown one is nil"
  assert get(kb_board("qemu-virt32"), :rust_target) ==
    "riscv32imac-unknown-none-elf"
  assert kb_board("no-such-board") == nil
end

test "device bases are the virt machine's"
  b = kb_qemu_virt32()
  assert kb_device_base(b, :uart0) == 268435456
  assert kb_device_base(b, :finisher) == 1048576
  assert kb_device_base(b, :gpio) == nil
end

test "the UART model prints ASCII and newline, and refuses other bytes"
  assert kb_char(104) == "h"
  assert kb_char(126) == "~"
  assert kb_char(32) == " "
  assert kb_char(10) == "\n"
  assert try(kb_char(7), catch(_e(), :refused)) == :refused
end

test "a store to an address with no device is refused"
  assert try(mmio_write(4096, 32, 1), catch(_e(), :refused)) == :refused
  assert try(mmio_write(268435456, 16, 1), catch(_e(), :refused)) == :refused
end
