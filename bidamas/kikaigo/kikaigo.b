@moduledoc """
kikaigo (機械語) — x86-64 machine code from blue: instructions as values, encoded to the bytes the CPU runs and printed as the AT&T text an assembler reads, held byte-identical to llvm-mc (docs/PURE-BLUE.md B2).

The method is kaaneru/bpf's: an opcode table, operand encoders, and an oracle that hands the printed text to llvm-mc and compares every byte. A register is a name (rax … r15); an instruction is {op:, dst:, src:} for register to register, {op:, dst:, imm:} for an immediate, or {op:} for ret and syscall.

    encode({op: "mov", dst: "rax", src: "rsi"}) #=> [72, 137, 240]
"""

use("kazu", [:fits])
use("retsu", %i[find_first flat_map index_of])

@doc """
REGS: the sixteen 64-bit general registers in hardware order, rax as 0 to r15 as 15.

    REGS[7] #=> "rdi"
"""
REGS = %w[rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15]

@doc """
ALU: the opcode table: per operation its register-form opcode, its immediate-form ModRM digit, and its accumulator-form opcode for rax with a 32-bit immediate.

    ALU[1][0] #=> "add"
"""
ALU = [
  ["mov", 137, 0, nil],
  ["add", 1, 0, 5],
  ["sub", 41, 5, 45],
  ["cmp", 57, 7, 61],
  ["and", 33, 4, 37]
]

@doc """
reg: the hardware number of a 64-bit register name, 0 for rax to 15 for r15.

    reg("r12") #=> 12
"""
def reg(name)
  i = index_of(REGS, name)
  if i < 0
    raise(:unknown_register, "kikaigo: no register `#{name}`")
  else
    i
  end
end

@doc """
row: the opcode table row of an ALU operation: [name, register-form opcode, immediate-form digit, accumulator-form opcode for rax with a 32-bit immediate].

    row("sub")[2] #=> 5
"""
def row(op)
  r = find_first((x) -> x[0] == op, ALU)
  if r.nil?
    raise(:unknown_op, "kikaigo: no operation `#{op}`")
  else
    r
  end
end

@doc """
rex: the REX prefix byte with W set: 64-bit operands, and the high bit of the reg and rm fields.

    rex(8, 15) #=> 77
"""
def rex(reg_field, rm_field)
  64 + 8 + floor(reg_field / 8) * 4 + floor(rm_field / 8)
end

@doc """
modrm: the ModRM byte for a register-direct operand pair.

    modrm(6, 0) #=> 240
"""
def modrm(reg_field, rm_field)
  192 + reg_field % 8 * 8 + rm_field % 8
end

@doc """
le32: a signed 32-bit integer as four little-endian bytes, two's complement.

    le32(-1) #=> [255, 255, 255, 255]
    le32(300) #=> [44, 1, 0, 0]
"""
def le32(n)
  m = if n < 0
    n + 4_294_967_296
  else
    n
  end
  [
    m % 256,
    floor(m / 256) % 256,
    floor(m / 65536) % 256,
    floor(m / 16_777_216) % 256
  ]
end

@doc """
imm8?: whether an immediate fits a sign-extended byte, so an ALU operation takes its short form.

    imm8?(127) #=> true
    imm8?(128) #=> false
"""
def imm8?(n)
  fits(n, true, 8)
end

@doc """
byte8: a signed byte as its unsigned value.

    byte8(-128) #=> 128
"""
def byte8(n)
  if n < 0
    n + 256
  else
    n
  end
end

@doc """
check_imm: an immediate that fits 32 bits, or :out_of_range.

    check_imm(7) #=> 7
"""
def check_imm(n)
  if n < -2_147_483_648 or n > 2_147_483_647
    raise(:out_of_range, "kikaigo: #{to_s(n)} does not fit 32 bits")
  else
    n
  end
end

@doc """
encode: the bytes of one instruction.

    encode({op: "syscall"}) #=> [15, 5]
    encode({op: "add", dst: "rax", imm: 1}) #=> [72, 131, 192, 1]
"""
def encode(i)
  op = i[:op]
  if op == "ret"
    [195]
  elsif op == "syscall"
    [15, 5]
  elsif op == "label"
    []
  elsif op == "push"
    r = reg(i[:src])
    if r < 8
      [80 + r]
    else
      [65, 72 + r]
    end
  elsif op == "pop"
    r = reg(i[:dst])
    if r < 8
      [88 + r]
    else
      [65, 80 + r]
    end
  elsif op == "movabs"
    d = reg(i[:dst])
    n = i[:imm]
    append(
      [rex(0, d), 184 + d % 8],
      append(
        le32(bit_and(n, 4_294_967_295)),
        le32(bit_and(shift_right(n, 32), 4_294_967_295))
      )
    )
  elsif op == "cqo"
    [72, 153]
  elsif op == "idiv"
    r = reg(i[:src])
    [rex(0, r), 247, modrm(7, r)]
  elsif op == "shr1"
    r = reg(i[:dst])
    [rex(0, r), 209, modrm(5, r)]
  elsif op == "load_byte"
    r = reg(i[:dst])
    b = byte_base(i)
    [rex(r, b), 15, 182, r % 8 * 8 + b % 8]
  elsif op == "store_byte"
    r = reg(i[:src])
    if r > 3
      raise(:unsupported, "kikaigo: a byte store takes al, cl, dl or bl")
    end
    b = byte_base(i)
    if b < 8
      [136, r * 8 + b % 8]
    else
      [65, 136, r * 8 + b % 8]
    end
  elsif op == "sar1"
    r = reg(i[:dst])
    [rex(0, r), 209, modrm(7, r)]
  elsif op == "call_label"
    append([232], le32(i[:rel] or 0))
  elsif op == "lea_label"
    d = reg(i[:dst] or "rax")
    append([rex(d, 0), 141, d % 8 * 8 + 5], le32(i[:rel] or 0))
  elsif op == "bytes"
    i[:bytes]
  elsif op == "align"
    map((k) -> 0, range(0, i[:pad] or 0))
  elsif op == "call_r11"
    [65, 255, 19]
  elsif op == "push_rbp"
    [85]
  elsif op == "pop_rbp"
    [93]
  elsif op == "movzx"
    [72, 15, 182, 192]
  elsif op == "set"
    [15, cond_row(i[:cond])[1], 192]
  elsif op == "jmp"
    append([233], le32(i[:rel] or 0))
  elsif op == "j"
    append([15, cond_row(i[:cond])[2]], le32(i[:rel] or 0))
  elsif op == "imul"
    d = reg(i[:dst])
    s = reg(i[:src])
    [rex(d, s), 15, 175, modrm(d, s)]
  elsif op == "load_at" or op == "store_at"
    r = if op == "load_at"
      reg(i[:dst])
    else
      reg(i[:src])
    end
    [
      rex(r, 1),
      if op == "load_at"
        139
      else
        137
      end,
      r % 8 * 8 + 1
    ]
  elsif op == "load" or op == "store"
    r = if op == "load"
      reg(i[:dst])
    else
      reg(i[:src])
    end
    code = if op == "load"
      139
    else
      137
    end
    disp = check_imm(i[:disp])
    b = base_of(i)
    if disp == 0 and b % 8 != 5
      [rex(r, b), code, r % 8 * 8 + b % 8]
    elsif imm8?(disp)
      [rex(r, b), code, 64 + r % 8 * 8 + b % 8, byte8(disp)]
    else
      append([rex(r, b), code, 128 + r % 8 * 8 + b % 8], le32(disp))
    end
  elsif i[:imm] != nil
    d = reg(i[:dst])
    n = check_imm(i[:imm])
    if op == "mov"
      append([rex(0, d), 199, modrm(0, d)], le32(n))
    elsif imm8?(n)
      [rex(0, d), 131, modrm(row(op)[2], d), byte8(n)]
    elsif d == 0
      append([72, row(op)[3]], le32(n))
    else
      append([rex(0, d), 129, modrm(row(op)[2], d)], le32(n))
    end
  else
    d = reg(i[:dst])
    s = reg(i[:src])
    [rex(s, d), row(op)[1], modrm(s, d)]
  end
end

@doc """
text: the AT&T line an assembler reads for one instruction.

    text({op: "mov", dst: "rax", src: "rsi"}) #=> "movq %rsi, %rax"
"""
def text(i)
  op = i[:op]
  if op == "ret"
    "retq"
  elsif op == "syscall"
    "syscall"
  elsif op == "push_rbp"
    "pushq %rbp"
  elsif op == "pop_rbp"
    "popq %rbp"
  elsif op == "movzx"
    "movzbq %al, %rax"
  elsif op == "set"
    "set#{i[:cond]} %al"
  elsif op == "imul"
    "imulq %#{i[:src]}, %#{i[:dst]}"
  elsif op == "load_at"
    "movq (%rcx), %#{i[:dst]}"
  elsif op == "store_at"
    "movq %#{i[:src]}, (%rcx)"
  elsif op == "call_r11"
    "callq *(%r11)"
  elsif op == "push"
    "pushq %#{i[:src]}"
  elsif op == "pop"
    "popq %#{i[:dst]}"
  elsif op == "sar1"
    "sarq %#{i[:dst]}"
  elsif op == "shr1"
    "shrq %#{i[:dst]}"
  elsif op == "movabs"
    "movabsq $#{to_s(i[:imm])}, %#{i[:dst]}"
  elsif op == "cqo"
    "cqto"
  elsif op == "idiv"
    "idivq %#{i[:src]}"
  elsif op == "load_byte"
    "movzbq (%#{i[:base]}), %#{i[:dst]}"
  elsif op == "store_byte"
    "movb %#{%w[al cl dl bl][reg(i[:src])]}, (%#{i[:base]})"
  elsif op == "load"
    "movq #{to_s(i[:disp])}(%#{i[:base] or "rbp"}), %#{i[:dst]}"
  elsif op == "store"
    "movq %#{i[:src]}, #{to_s(i[:disp])}(%#{i[:base] or "rbp"})"
  elsif i[:imm] != nil
    "#{op}q $#{to_s(i[:imm])}, %#{i[:dst]}"
  else
    "#{op}q %#{i[:src]}, %#{i[:dst]}"
  end
end

@doc """
CONDS: the condition codes: per code its setcc second byte and its jcc rel32 second byte.

    CONDS[0][0] #=> "l"
"""
CONDS = [
  ["l", 156, 140],
  ["g", 159, 143],
  ["e", 148, 132],
  ["ne", 149, 133],
  ["le", 158, 142],
  ["ge", 157, 141]
]

@doc """
cond_row: the condition table row of a condition code.

    cond_row("e")[2] #=> 132
"""
def cond_row(name)
  r = find_first((x) -> x[0] == name, CONDS)
  if r.nil?
    raise(:unknown_condition, "kikaigo: no condition `#{name}`")
  else
    r
  end
end

@doc """
link: a sequence with every jump's label resolved to a rel32 from the end of the jump to the label; every jump is the 32-bit form, so sizes are known before any target is.

    link([{op: "jmp", label: "a"}, {op: "label", name: "a"}])[0][:rel] #=> 0
"""
def link(insns)
  padded = reduce(
    fn(acc, i)
      pos = last_or0(acc[1])
      j = if i[:op] == "align"
        assoc(i, :pad, (i[:to] - pos % i[:to]) % i[:to])
      else
        i
      end
      [append(acc[0], [j]), append(acc[1], [pos + length(encode(j))])]
    end,
    [[], []],
    insns
  )
  laid = padded[0]
  ends = padded[1]
  at = (name) -> ends[index_of(map((i) -> i[:name], laid), name)]
  map(
    fn(k)
      i = laid[k]
      if i[:label] != nil
        assoc(i, :rel, at(i[:label]) - ends[k])
      else
        i
      end
    end,
    range(0, length(laid))
  )
end

@doc """
last_or0: the last element of a list of numbers, or 0 for none.

    last_or0([]) #=> 0
"""
def last_or0(xs)
  if length(xs) == 0
    0
  else
    xs[length(xs) - 1]
  end
end

@doc """
base_of: the base register of a memory operand, rbp when none is named; rsp and r12 need a SIB byte this encoder does not write, so they are refused.

    base_of({disp: 8}) #=> 5
    base_of({base: "r15", disp: 8}) #=> 15
"""
def base_of(i)
  b = reg(i[:base] or "rbp")
  if b % 8 == 4
    raise(
      :unsupported_base,
      "kikaigo: `#{i[:base]}` as a base needs a SIB byte"
    )
  else
    b
  end
end

@doc """
le64: a non-negative integer as eight little-endian bytes.

    le64(1) #=> [1, 0, 0, 0, 0, 0, 0, 0]
"""
def le64(n)
  append(le32(n % 4_294_967_296), le32(floor(n / 4_294_967_296)))
end

@doc """
byte_base: the base register of a byte load or store, which takes no displacement: rsp, rbp, r12 and r13 cannot be such a base.

    byte_base({base: "rsi"}) #=> 6
"""
def byte_base(i)
  b = reg(i[:base])
  if b % 8 == 4 or b % 8 == 5
    raise(:unsupported_base, "kikaigo: `#{i[:base]}` cannot be a byte base")
  else
    b
  end
end

@doc """
assemble: the bytes of a sequence of instructions, in order.

    assemble([{op: "syscall"}, {op: "ret"}]) #=> [15, 5, 195]
"""
def assemble(insns)
  flat_map(link(insns), encode)
end

@doc """
corpus: every register-register form of every ALU operation, every immediate form at the edges that pick between the short and long encodings, and ret and syscall: what the oracle compares.

    length(corpus) > 1000 #=> true
"""
def corpus()
  ops = map((r) -> r[0], ALU)
  rr = flat_map(
    ops,
    (op) -> flat_map(REGS, (d) -> map((s) -> {op:, dst: d, src: s}, REGS))
  )
  imms = [0, 1, -1, 127, 128, -128, -129, 300, 2_147_483_647, -2_147_483_648]
  ri = flat_map(
    ops,
    (op) -> flat_map(REGS, (d) -> map((n) -> {op:, dst: d, imm: n}, imms))
  )
  disps = [-8, -128, -129, -2048, 8, 127]
  mem = flat_map(
    REGS,
    fn(r)
      flat_map(
        disps,
        (d) -> [{op: "load", dst: r, disp: d}, {op: "store", src: r, disp: d}]
      )
    end
  )
  at = flat_map(
    REGS,
    (r) -> [{op: "load_at", dst: r}, {op: "store_at", src: r}]
  )
  bases = %w[rax rcx rbx rbp r11 r13 r15]
  based = flat_map(
    bases,
    fn(b)
      flat_map(
        [0, 8, -2048],
        fn(d)
          [
            {op: "load", dst: "rax", base: b, disp: d},
            {op: "store", src: "r9", base: b, disp: d}
          ]
        end
      )
    end
  )
  mul = flat_map(REGS, (d) -> map((s) -> {op: "imul", dst: d, src: s}, REGS))
  stack = flat_map(
    REGS,
    fn(r)
      [
        {op: "push", src: r},
        {op: "pop", dst: r},
        {op: "sar1", dst: r},
        {op: "shr1", dst: r},
        {op: "idiv", src: r}
      ]
    end
  )
  byte_bases = %w[rax rcx rdx rbx rsi rdi r8 r9 r10 r11 r14 r15]
  bytes = flat_map(
    byte_bases,
    fn(b)
      append(
        map((r) -> {op: "load_byte", dst: r, base: b}, %w[rax rcx r9 r15]),
        map((r) -> {op: "store_byte", src: r, base: b}, %w[rax rcx rdx rbx])
      )
    end
  )
  sets = map((c) -> {op: "set", cond: c[0]}, CONDS)
  rest_ops = [
    {op: "movzx"},
    {op: "push_rbp"},
    {op: "pop_rbp"},
    {op: "call_r11"},
    {op: "cqo"},
    {op: "ret"},
    {op: "syscall"}
  ]
  wide = flat_map(
    REGS,
    fn(d)
      map(
        (n) -> {op: "movabs", dst: d, imm: n},
        [
          4_294_967_296,
          3_400_000_001,
          -3_400_000_001,
          9_223_372_036_854_775_807
        ]
      )
    end
  )
  append(*[rr, ri, mem, at, based, mul, stack, bytes, sets, rest_ops, wide])
end

test "golden encodings from llvm-mc 21.1.7"
  golden = [
    [
      {op: "movabs", dst: "rax", imm: 4_886_718_345},
      [72, 184, 137, 103, 69, 35, 1, 0, 0, 0]
    ],
    [
      {op: "movabs", dst: "r11", imm: -1},
      [73, 187, 255, 255, 255, 255, 255, 255, 255, 255]
    ],
    [{op: "mov", dst: "rax", src: "rsi"}, [72, 137, 240]],
    [{op: "add", dst: "r15", src: "r8"}, [77, 1, 199]],
    [{op: "mov", dst: "r12", imm: -1}, [73, 199, 196, 255, 255, 255, 255]],
    [{op: "sub", dst: "rsp", imm: 300}, [72, 129, 236, 44, 1, 0, 0]],
    [{op: "mov", dst: "r15", src: "r15"}, [77, 137, 255]],
    [{op: "mov", dst: "rbp", src: "rsp"}, [72, 137, 229]],
    [{op: "add", dst: "rdx", src: "rcx"}, [72, 1, 202]],
    [{op: "sub", dst: "r12", src: "r13"}, [77, 41, 236]],
    [{op: "cmp", dst: "r9", src: "rdi"}, [73, 57, 249]],
    [{op: "add", dst: "rbx", imm: -128}, [72, 131, 195, 128]],
    [{op: "add", dst: "r10", imm: 127}, [73, 131, 194, 127]],
    [{op: "add", dst: "r10", imm: 128}, [73, 129, 194, 128, 0, 0, 0]],
    [{op: "sub", dst: "rsi", imm: -129}, [72, 129, 238, 127, 255, 255, 255]],
    [{op: "cmp", dst: "r15", imm: 0}, [73, 131, 255, 0]],
    [{op: "mov", dst: "rax", imm: 0}, [72, 199, 192, 0, 0, 0, 0]],
    [
      {op: "mov", dst: "r11", imm: 2_147_483_647},
      [73, 199, 195, 255, 255, 255, 127]
    ],
    [
      {op: "mov", dst: "rdi", imm: -2_147_483_648},
      [72, 199, 199, 0, 0, 0, 128]
    ],
    [{op: "syscall"}, [15, 5]],
    [{op: "cmp", dst: "rax", imm: 300}, [72, 61, 44, 1, 0, 0]],
    [{op: "add", dst: "rax", imm: 128}, [72, 5, 128, 0, 0, 0]],
    [{op: "sub", dst: "rax", imm: -129}, [72, 45, 127, 255, 255, 255]],
    [{op: "ret"}, [195]]
  ]
  map((g) -> assert encode(g[0]) == g[1], golden)
end

test "the printed text is what llvm-mc reads"
  assert text({op: "add", dst: "r15", src: "r8"}) == "addq %r8, %r15"
  assert text({op: "sub", dst: "rsp", imm: 300}) == "subq $300, %rsp"
  assert text({op: "ret"}) == "retq"
end

test "an unknown register, an unknown op and a wide immediate are refused by name"
  k = fn(f)
    begin
      f()
    rescue e
      e.kind
    end
  end
  assert k(() -> encode({op: "mov", dst: "eax", src: "rax"})) ==
    :unknown_register
  assert k(() -> encode({op: "xor", dst: "rax", src: "rax"})) == :unknown_op
  assert k(() -> encode({op: "add", dst: "rax", imm: 2_147_483_648})) ==
    :out_of_range
end

test "jumps resolve to their labels and conditions refuse a code they do not know"
  linked = link(
    [
      {op: "j", cond: "e", label: "out"},
      {op: "mov", dst: "rax", imm: 1},
      {op: "label", name: "out"},
      {op: "jmp", label: "top"},
      {op: "label", name: "top"}
    ]
  )
  assert linked[0][:rel] == 7
  assert linked[3][:rel] == 0
  assert assemble([{op: "jmp", label: "a"}, {op: "label", name: "a"}]) ==
    [233, 0, 0, 0, 0]
  assert length(CONDS) == 6
  assert cond_row("l")[1] == 156
  assert last_or0([3, 4]) == 4
  k = begin
    cond_row("zz")
  rescue e
    e.kind
  end
  assert k == :unknown_condition
end

test "a memory base is any register but rsp and r12, which need a SIB byte"
  assert base_of({base: "r15", disp: 0}) == 15
  assert encode({op: "store", src: "rax", base: "r15", disp: 0}) == [73, 137, 7]
  assert encode({op: "load", dst: "rax", base: "rbp", disp: 0}) ==
    [72, 139, 69, 0]
  refused = begin
    base_of({base: "rsp", disp: 0})
  rescue e
    e.kind
  end
  assert refused == :unsupported_base
end

test "lea of a label reaches any register, and raw bytes are placed as they are"
  assert encode({op: "lea_label", dst: "rcx", rel: 0}) ==
    [72, 141, 13, 0, 0, 0, 0]
  assert encode({op: "lea_label", dst: "r9", rel: 0}) ==
    [76, 141, 13, 0, 0, 0, 0]
  assert encode({op: "lea_label", rel: 0}) == [72, 141, 5, 0, 0, 0, 0]
  assert encode({op: "bytes", bytes: [1, 2, 3]}) == [1, 2, 3]
  assert le64(4_294_967_297) == [1, 0, 0, 0, 1, 0, 0, 0]
end

test "byte loads and stores take a base with no displacement and a low byte register"
  assert byte_base({base: "rsi"}) == 6
  assert encode({op: "load_byte", dst: "rax", base: "rsi"}) == [72, 15, 182, 6]
  assert encode({op: "store_byte", src: "rcx", base: "rdi"}) == [136, 15]
  assert encode({op: "store_byte", src: "rax", base: "r9"}) == [65, 136, 1]
  assert encode({op: "shr1", dst: "rax"}) == [72, 209, 232]
  base = begin
    byte_base({base: "rbp"})
  rescue e
    e.kind
  end
  assert base == :unsupported_base
  wide = begin
    encode({op: "store_byte", src: "rsi", base: "rdi"})
  rescue e
    e.kind
  end
  assert wide == :unsupported
end

test "align pads to a multiple of its size from where it falls"
  a = assemble(
    [{op: "ret"}, {op: "align", to: 8}, {op: "label", name: "x"}, {op: "ret"}]
  )
  assert length(a) == 9
  assert a[8] == 195
  b = assemble([{op: "align", to: 8}, {op: "ret"}])
  assert b == [195]
  j = link([{op: "syscall"}, {op: "align", to: 4}])
  assert j[1][:pad] == 2
end

test "the helpers are exercised by name"
  assert length(REGS) == 16
  assert length(ALU) == 5
  assert reg("rax") == 0
  assert row("cmp")[1] == 57
  assert rex(0, 0) == 72
  assert modrm(0, 0) == 192
  assert le32(1) == [1, 0, 0, 0]
  assert imm8?(-128)
  assert byte8(5) == 5
  assert check_imm(7) == 7
  assert assemble([{op: "ret"}]) == [195]
  assert length(corpus) ==
    5 * 16 * 16 +
      5 * 16 * 10 +
      16 * 6 * 2 +
      16 * 2 +
      7 * 3 * 2 +
      16 * 16 +
      16 * 5 +
      12 * 8 +
      6 +
      7 +
      16 * 4
  assert encode({op: "push", src: "r12"}) == [65, 84]
  assert encode({op: "pop", dst: "rdi"}) == [95]
  assert encode({op: "sar1", dst: "rax"}) == [72, 209, 248]
  assert encode({op: "call_label", rel: 0}) == [232, 0, 0, 0, 0]
end

test "every corpus instruction prints as text and encodes to bytes beside the encoder"
  bad = filter((i) -> length(text(i)) == 0 or length(encode(i)) == 0, corpus)
  assert bad == []
  assert text({op: "ret"}) == "retq"
  assert text({op: "syscall"}) == "syscall"
  assert text({op: "cqo"}) == "cqto"
  assert text({op: "call_r11"}) == "callq *(%r11)"
end
