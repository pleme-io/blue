@moduledoc """
object_suite: Global subprograms, a spin lock and a callback in the real kernel, and blue's object files in the kernel's own tools. It needs root, Linux and, on PATH, `bpftool`, `veristat` and `clang`; `kernel/run.b` supplies them.

    blue test --allow host kernel/object_suite.b
"""

use("baito", %i[bytes_int int_bytes])

use(
  "bpf",
  %i[
    alu
    assemble
    call
    call_local
    compile
    declare_locked
    declare_map
    exit_program
    func_ref
    jump
    label
    map_ref
    packet_of
    r
    store
    with_funcs
    xdp_pass
  ]
)

use("erufu")

use("kaaneru", %i[create_map install load map_get map_named prog_info])

use("retsu", %i[first repeat size])

def scratch_dir()
  dir = path_join(getenv("TMPDIR", "/tmp"), "blue-object-#{to_s(now_ms)}")
  mkdir_p(dir)
  dir
end

def tool(name, args)
  got = exec_capture(name, *args)
  if got.status != 0
    raise(:tool, "#{name} #{to_s(args)}: #{got.stdout} #{got.stderr}")
  end
  got
end

def pair_packet(a, b)
  append(*[int_bytes(a, 8, :big), int_bytes(b, 8, :big), repeat(0, 48)])
end

test "the kernel holds the program's functions: two in func_info, and its BTF id"
  live = install(
    compile(
      "kernel/suite.b",
      {entry: :mix_entry, kind: :xdp, on_fault: 0, global: [:mix]}
    )
  )
  info = prog_info(live[:prog])
  assert info[:nr_func_info] == 2
  assert info[:btf_id] > 0
end

test "the default still inlines: one function, no BTF, and the same answers"
  compiled = compile(
    "kernel/suite.b",
    {entry: :mix_entry, kind: :xdp, on_fault: 0}
  )
  assert size(compiled[:funcs]) == 1
  live = install(compiled)
  info = prog_info(live[:prog])
  assert info[:nr_func_info] == 0
  assert info[:btf_id] == 0
  got = kaaneru::run(live[:prog], {packet: pair_packet(40, 2)})
  assert got[:ret] == xdp_pass
  assert bytes_int(got[:packet], 16, 8, :big) == 38
end

def stack_reader(linkage)
  with_funcs(
    assemble(
      [
        alu(:mov, 1, -8),
        call_local(:reader),
        exit_program,
        label(:reader),
        store(:dw, 10, -8, 0),
        alu(:mov, 2, r(10)),
        alu(:add, 2, r(1)),
        bpf::load(:b, 0, 2, 0),
        exit_program
      ]
    ),
    [
      {name: "entry", linkage: :global, params: [:ctx]},
      {name: "reader", label: :reader, linkage:, params: [:int]}
    ]
  )
end

test "a global subprogram is verified alone, where a static one is verified with its caller's argument"
  plain = kaaneru::load_btf(
    bpf::program_btf(assoc(stack_reader(:static), :kind, :xdp))[:bytes]
  )
  shape = bpf::program_btf(assoc(stack_reader(:static), :kind, :xdp))
  accepted = load(
    stack_reader(:static),
    {
      kind: :xdp,
      name: "static_read",
      btf_fd: plain[:fd],
      func_info: shape[:func_info]
    }
  )
  assert accepted[:fd] != nil
  global_shape = bpf::program_btf(assoc(stack_reader(:global), :kind, :xdp))
  global_btf = kaaneru::load_btf(global_shape[:bytes])
  refusal = begin
    load(
      stack_reader(:global),
      {
        kind: :xdp,
        name: "global_read",
        btf_fd: global_btf[:fd],
        func_info: global_shape[:func_info]
      }
    )
    "loaded"
  rescue :kernel_refused as e
    e.data.log
  end
  assert refusal != "loaded"
  assert contains?(refusal, "unbounded")
end

test "one source with a global subprogram that takes the context: the machine and the kernel write the same packet"
  compiled = compile(
    "kernel/programs/object.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0, global: [:sum_into]}
  )
  live = install(compiled)
  input = pair_packet(40, 2)
  vm = bpf::run(compiled, {packet: input, maps: compiled[:maps]})
  in_kernel = kaaneru::run(live[:prog], {packet: input})
  assert in_kernel[:ret] == xdp_pass
  assert in_kernel[:packet] == packet_of(vm)
  assert bytes_int(in_kernel[:packet], 16, 8, :big) == 42
  assert bytes_int(in_kernel[:packet], 24, 8, :big) == 42
  counts = map_named(live, :object_counts)
  assert bytes_int(map_get(counts, int_bytes(1, 4)), 0, 8) == 1
end

test "a spin lock taken in the real kernel: every add counted over a thousand runs, and the machine says the same of the first"
  compiled = compile(
    "kernel/programs/spin.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0}
  )
  live = install(compiled)
  totals = map_named(live, :spin_totals)
  input = repeat(0, 64)
  vm = bpf::run(compiled, {packet: input, maps: compiled[:maps]})
  once = kaaneru::run(live[:prog], {packet: input})
  assert once[:packet] == packet_of(vm)
  assert bytes_int(once[:packet], 0, 8, :big) == 5
  kaaneru::run(live[:prog], {packet: input, repeat: 1000})
  assert bytes_int(map_get(totals, int_bytes(0, 4)), 8, 8) == 5005
end

def lock_program(ending)
  assemble(
    [
      store(:w, 10, -4, 0),
      alu(:mov, 2, r(10)),
      alu(:add, 2, -4),
      map_ref(1, :locks),
      call(:map_lookup_elem),
      jump(:eq, 0, 0, :out),
      alu(:mov, 1, r(0)),
      call(:spin_lock),
      ending,
      label(:out),
      alu(:mov, 0, 2),
      exit_program
    ]
  )
end

test "the kernel holds the lock's rules: a map with no BTF is refused, and so is a return with the lock held"
  plain = create_map(declare_map(:locks, :array, 4, 16, 1))
  no_btf = begin
    load(lock_program([]), {kind: :xdp, maps: [plain], name: "lock_plain"})
    "loaded"
  rescue :kernel_refused as e
    e.data.log
  end
  assert contains?(no_btf, "BTF")
  spec = declare_locked(:locks, :array, 4, 1)
  p = assoc(assoc(lock_program([]), :maps, [spec]), :kind, :xdp)
  held = begin
    install(p)
    "loaded"
  rescue :kernel_refused as e
    e.data.log
  end
  assert contains?(held, "spin")
end

def loop_program()
  with_funcs(
    assemble(
      [
        alu(:mov, 1, 3),
        func_ref(2, :turn),
        alu(:mov, 3, 0),
        alu(:mov, 4, 0),
        call(:loop),
        exit_program,
        label(:turn),
        alu(:mov, 0, 0),
        exit_program
      ]
    ),
    [
      {name: "entry", linkage: :global, params: [:ctx]},
      {name: "turn", label: :turn, linkage: :static, params: %i[int int]}
    ]
  )
end

test "a callback in the real kernel: bpf_loop runs it, and the machine counts the same"
  p = assoc(loop_program, :kind, :xdp)
  live = install(p)
  in_kernel = kaaneru::run(live[:prog], {packet: repeat(0, 64)})
  assert in_kernel[:ret] == 3
  assert bpf::run(p, {packet: repeat(0, 64)}).ret == 3
end

def object_of(file, entry, globals)
  erufu::object(
    compile(file, {entry:, kind: :xdp, on_fault: 0, global: globals})
  )
end

def bpftool_run(pin, input_path, output_path)
  got = tool(
    "bpftool",
    [
      "prog",
      "run",
      "pinned",
      pin,
      "data_in",
      input_path,
      "data_out",
      output_path
    ]
  )
  got.stdout
end

test "bpftool reads a blue object's BTF, loads it and runs it, with the answer the kernel's own call gives"
  dir = scratch_dir
  path = path_join(dir, "object.o")
  write_bytes(
    path,
    object_of("kernel/programs/object.b", :on_packet, [:sum_into])
  )
  dumped = tool("bpftool", ["btf", "dump", "file", path]).stdout
  assert contains?(dumped, "FUNC 'on_packet'")
  assert contains?(dumped, "FUNC 'sum_into'")
  assert contains?(dumped, "DATASEC '.maps'")
  pin = "/sys/fs/bpf/blue_object_#{to_s(now_ms)}"
  tool("bpftool", ["prog", "load", path, pin])
  input = path_join(dir, "in")
  output = path_join(dir, "out")
  write_bytes(input, pair_packet(40, 2))
  said = begin
    bpftool_run(pin, input, output)
  ensure
    rm(pin)
  end
  assert contains?(said, "Return value: 2,")
  got = read_bytes(output)
  assert bytes_int(got, 16, 8, :big) == 42
  assert bytes_int(got, 24, 8, :big) == 42
  rm_rf(dir)
end

test "veristat loads a blue object with a global subprogram and a spin lock, and reports each program verified"
  dir = scratch_dir
  path = path_join(dir, "object.o")
  write_bytes(
    path,
    object_of("kernel/programs/object.b", :on_packet, [:sum_into])
  )
  said = tool("veristat", [path]).stdout
  assert contains?(said, "on_packet")
  assert contains?(said, "success")
  assert contains?(said, "Done. Processed 1 files")
  rm_rf(dir)
end

test "an object clang built reads back and loads through blue, and answers as blue's own does"
  dir = scratch_dir
  source = path_join(dir, "c.c")
  path = path_join(dir, "c.o")
  write_file(
    source,
    unlines(
      [
        "struct xdp_md { unsigned int data; };",
        "struct bpf_spin_lock { unsigned int val; };",
        "struct v { struct bpf_spin_lock lock; long long n; };",
        "struct { int (*type)[2]; unsigned int *key; struct v *value; int (*max_entries)[1]; } locks __attribute__((section(\".maps\"), used));",
        "char _license[] __attribute__((section(\"license\"), used)) = \"GPL\";",
        "static void *(*lookup)(void *, const void *) = (void *) 1;",
        "static void (*lock)(struct bpf_spin_lock *) = (void *) 93;",
        "static void (*unlock)(struct bpf_spin_lock *) = (void *) 94;",
        "__attribute__((noinline)) int add(int a) { return a + 40; }",
        "__attribute__((section(\"xdp\"), used)) int entry(struct xdp_md *ctx) {",
        "  unsigned int k = 0;",
        "  struct v *found = lookup(&locks, &k);",
        "  if (!found) return 0;",
        "  lock(&found->lock);",
        "  found->n += 1;",
        "  unlock(&found->lock);",
        "  return add(2) == 42 ? 2 : 0;",
        "}"
      ]
    )
  )
  tool("clang", ["-target", "bpf", "-O2", "-g", "-c", source, "-o", path])
  back = erufu::program_of(erufu::decode(read_bytes(path)))
  assert back[:kind] == :xdp
  assert first(back[:maps])[:lock] == true
  assert size(back[:funcs]) == 2
  live = install(back)
  assert kaaneru::run(live[:prog], {packet: repeat(0, 64)})[:ret] == 2
  values = map_get(map_named(live, "locks"), int_bytes(0, 4))
  assert bytes_int(values, 8, 8) == 1
  rm_rf(dir)
end

test "blue's reading of its own object loads as the compiled program does"
  compiled = compile(
    "kernel/programs/object.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0, global: [:sum_into]}
  )
  back = erufu::program_of(erufu::decode(erufu::object(compiled)))
  live = install(back)
  got = kaaneru::run(live[:prog], {packet: pair_packet(40, 2)})
  assert got[:ret] == xdp_pass
  assert bytes_int(got[:packet], 24, 8, :big) == 42
end
