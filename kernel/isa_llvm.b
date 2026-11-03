use(
  "bpf",
  %i[
    alu
    alu32
    atomic
    atomic_ops
    call
    encode_insn
    exit_program
    imm64
    ja
    jump
    jump32
    jump_ops
    load
    load_signed
    neg
    r
    regular_ops
    store
    swap
    text
  ]
)

use("retsu", %i[first flat_map size zip])
use("shinsuu", [:from_base])

def extending_ops()
  %i[movsx8 movsx16 movsx32]
end

def every_alu()
  flat_map(
    regular_ops,
    fn(op)
      [alu(op, 1, r(2)), alu(op, 3, 7), alu32(op, 1, r(2)), alu32(op, 3, 7)]
    end
  )
end

def every_extension()
  append(
    map((op) -> alu(op, 1, r(2)), extending_ops),
    [alu32(:movsx8, 1, r(2)), alu32(:movsx16, 1, r(2))]
  )
end

def every_swap()
  flat_map(
    [16, 32, 64],
    (bits) -> [swap(:be, 1, bits), swap(:le, 1, bits), swap(:any, 1, bits)]
  )
end

def every_jump()
  conds = map(first, jump_ops)
  flat_map(
    conds,
    fn(op)
      [
        jump(op, 1, r(2), 3),
        jump(op, 1, 7, -3),
        jump32(op, 1, r(2), 3),
        jump32(op, 1, 7, -3)
      ]
    end
  )
end

def every_memory()
  flat_map(
    %i[b h w dw],
    fn(size)
      [
        load(size, 1, 2, 4),
        load(size, 1, 2, -4),
        store(size, 1, 4, r(2)),
        store(size, 1, -4, r(2)),
        store(size, 1, 4, 7)
      ]
    end
  )
end

def every_signed_load()
  map((size) -> load_signed(size, 1, 2, 4), %i[b h w])
end

def every_atomic()
  flat_map(
    map(first, atomic_ops),
    (op) -> [atomic(op, :dw, 1, 8, 2), atomic(op, :w, 1, 8, 2)]
  )
end

def every_other()
  [
    neg(1),
    neg(1, 32),
    ja(3),
    ja(-3),
    ja(100, true),
    call(5),
    exit_program,
    imm64(1, 5),
    imm64(1, 81_985_529_216_486_895)
  ]
end

def variants()
  append(
    *[
      every_alu,
      every_extension,
      every_swap,
      every_jump,
      every_memory,
      every_signed_load,
      every_atomic,
      every_other
    ]
  )
end

def resolved_of(i)
  fixed = if i[:target] != nil
    dissoc(assoc(i, :off, i[:target]), :target)
  elsif i[:wide_target] != nil
    dissoc(assoc(i, :imm, i[:wide_target]), :wide_target)
  else
    i
  end
  fixed
end

def encoding_of(line)
  at = split(line, "encoding: [")
  if size(at) < 2
    nil
  else
    body = first(split(at[1], "]"))
    map((h) -> from_base(replace(trim(h), "0x", ""), 16), split(body, ","))
  end
end

def main()
  all = map(resolved_of, variants)
  source = join(map(text, all), line_break)
  tmp = path_join(getenv("TMPDIR", "/tmp"), "bpf-isa-llvm.s")
  write_file(tmp, concat(source, line_break))
  got = exec_capture(
    first(argv),
    "--arch=bpfel",
    "--mcpu=v4",
    "--show-encoding",
    tmp
  )
  if got.status != 0
    raise(:llvm, got.stderr)
  end
  encoded = filter(
    (e) -> not e.nil?,
    map(encoding_of, split(got.stdout, line_break))
  )
  bad = filter((pair) -> encode_insn(first(pair)) != pair[1], zip(all, encoded))
  write_stdout(
    unlines(
      [
        "#{to_s(size(all))} instructions, #{to_s(size(encoded))} encodings from LLVM, #{to_s(size(bad))} differ"
      ]
    )
  )
  map(
    fn(pair)
      write_stdout(
        unlines(
          [
            "❌ #{text(first(pair))}: blue #{to_s(encode_insn(first(pair)))} llvm #{to_s(pair[1])}"
          ]
        )
      )
    end,
    bad
  )
  if size(all) != size(encoded) or size(bad) != 0
    exit(1)
  end
end
