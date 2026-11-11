@moduledoc """
object_suite: Global subprograms, a spin lock and a callback in the real kernel, and blue's object files in the kernel's own tools. It needs root, Linux and, on PATH, `bpftool`, `veristat` and `clang`; `kernel/run.b` supplies them.

    blue test --allow host kernel/object_suite.b
"""

use("baito", %i[bytes_int int_bytes])

use("kaaneru", %i[create_map install load map_get map_named prog_info])

use(
  "kaaneru/bpf",
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

use("retsu", %i[first flat_map repeat size])

def scratch_dir()
  dir = path_join(temp_dir("blue-object"), "blue-object")
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
        kaaneru::bpf::load(:b, 0, 2, 0),
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
    kaaneru::bpf::program_btf(assoc(stack_reader(:static), :kind, :xdp))[:bytes]
  )
  shape = kaaneru::bpf::program_btf(assoc(stack_reader(:static), :kind, :xdp))
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
  global_shape = kaaneru::bpf::program_btf(
    assoc(stack_reader(:global), :kind, :xdp)
  )
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
  vm = kaaneru::bpf::run(compiled, {packet: input, maps: compiled[:maps]})
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
  vm = kaaneru::bpf::run(compiled, {packet: input, maps: compiled[:maps]})
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
  assert kaaneru::bpf::run(p, {packet: repeat(0, 64)}).ret == 3
end

def object_of(file, entry, globals)
  kaaneru::erufu::object(
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
  back = kaaneru::erufu::program_of(kaaneru::erufu::decode(read_bytes(path)))
  assert back[:kind] == :xdp
  assert first(back[:maps])[:lock] == true
  assert size(back[:funcs]) == 2
  live = install(back)
  assert kaaneru::run(live[:prog], {packet: repeat(0, 64)})[:ret] == 2
  values = map_get(map_named(live, "locks"), int_bytes(0, 4))
  assert bytes_int(values, 8, 8) == 1
  rm_rf(dir)
end

test "a clang object with a function nothing reaches loads through blue, and linking all of .text is what the verifier refuses"
  dir = scratch_dir
  source = path_join(dir, "dead.c")
  path = path_join(dir, "dead.o")
  write_file(
    source,
    unlines(
      [
        "struct xdp_md { unsigned int data; };",
        "char _license[] __attribute__((section(\"license\"), used)) = \"GPL\";",
        "__attribute__((noinline)) int unreached(int a) { return a * *(volatile int *) 0; }",
        "__attribute__((noinline)) int add(int a) { return a + 40; }",
        "__attribute__((section(\"xdp\"), used)) int entry(struct xdp_md *ctx) {",
        "  return add(2) == 42 ? 2 : 0;",
        "}"
      ]
    )
  )
  tool("clang", ["-target", "bpf", "-O2", "-g", "-c", source, "-o", path])
  o = kaaneru::erufu::decode(read_bytes(path))
  back = kaaneru::erufu::program_of(o)
  assert map((f) -> f[:name], back[:funcs]) == %w[entry add]
  live = install(back)
  assert kaaneru::run(live[:prog], {packet: repeat(0, 64)})[:ret] == 2
  whole = kaaneru::erufu::program_of(o, nil, {keep_unreached: true})
  assert size(whole[:funcs]) == 3
  refusal = begin
    install(whole)
    "loaded"
  rescue :kernel_refused as e
    e.data.log
  end
  assert contains?(refusal, "func_info")
  rm_rf(dir)
end

test "a refusal names the blue line and the reason, and the verifier's own log holds the source"
  compiled = compile(
    "kernel/programs/refused.b",
    {entry: :read_far, kind: :xdp}
  )
  caught = begin
    install(compiled)
    nil
  rescue :kernel_refused as e
    e
  end
  assert contains?(caught.message, "kernel/programs/refused.b:11")
  assert contains?(caught.message, "invalid bpf_context access")
  assert caught.data.at.line == 11
  assert contains?(caught.data.at.text, "ctx_int(c, 1000, 4)")
  assert caught.data.reason == "invalid bpf_context access off=1000 size=4"
  assert contains?(caught.data.log, "; far = ctx_int(c, 1000, 4)")
  names = verifier_names_file?(kaaneru::kernel_release)
  if names != nil
    assert contains?(caught.data.log, "ctx_int(c, 1000, 4) @ refused.b:11") ==
      names
  end
end

@doc """
verifier_names_file?: whether the verifier's log puts ` @ FILE:LINE` after a source line, as measured: 6.6.142 prints the line alone, 6.12.92 and 7.0.11 name the file. nil for a release nothing measured.

    verifier_names_file?("6.6.142") #=> false
    verifier_names_file?("6.12.92") #=> true
    verifier_names_file?("5.15.1").nil? #=> true
"""
def verifier_names_file?(release)
  if starts_with?(release, "6.6.")
    false
  elsif starts_with?(release, "6.12.") or starts_with?(release, "7.")
    true
  end
end

test "with lines off the refusal holds an instruction and no source, as a program with no lines has"
  compiled = compile(
    "kernel/programs/refused.b",
    {entry: :read_far, kind: :xdp, lines: false}
  )
  caught = begin
    install(compiled)
    nil
  rescue :kernel_refused as e
    e
  end
  assert contains?(caught.message, "instruction")
  assert caught.data.at.nil?
  assert not contains?(caught.data.log, "@ refused.b")
end

test "a program that loads stays plain: no BTF and no lines, though it knows them"
  compiled = compile(
    "kernel/suite.b",
    {entry: :mix_entry, kind: :xdp, on_fault: 0}
  )
  assert compiled[:lines] != []
  info = prog_info(install(compiled)[:prog])
  assert info[:btf_id] == 0
  assert info[:nr_line_info] == 0
end

test "a program with BTF loads with its source lines, and bpftool reads them back from the kernel and from its object"
  compiled = compile(
    "kernel/programs/object.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0, global: [:sum_into]}
  )
  info = prog_info(install(compiled)[:prog])
  assert info[:nr_line_info] > 0
  dir = scratch_dir
  path = path_join(dir, "lined.o")
  write_bytes(path, kaaneru::erufu::object(compiled))
  pin = "/sys/fs/bpf/blue_lined_#{to_s(now_ms)}"
  tool("bpftool", ["prog", "load", path, pin])
  said = begin
    tool("bpftool", ["prog", "dump", "xlated", "pinned", pin, "linum"]).stdout
  ensure
    rm(pin)
  end
  assert contains?(said, "sum_into")
  assert contains?(said, "kernel/programs/object.b")
  assert contains?(said, "[file:kernel/programs/object.b line_num:")
  rm_rf(dir)
end

def field_object(dir)
  path = path_join(dir, "core.o")
  write_bytes(
    path,
    kaaneru::erufu::object(
      compile(
        "kernel/programs/fentry.b",
        {entry: :on_open, kind: :tracing, on_fault: 0}
      ),
      {section: "fentry/do_sys_openat2"}
    )
  )
  path
end

def xlated_of(path, extra)
  pin = "/sys/fs/bpf/blue_core_#{to_s(now_ms)}"
  tool("bpftool", append(append(["prog", "load", path, pin], extra), []))
  begin
    tool("bpftool", ["prog", "dump", "xlated", "pinned", pin]).stdout
  ensure
    rm(pin)
  end
end

test "one object holds a CO-RE relocation for an unbound field: libbpf moves it to this kernel's offset, and to another kernel's from that kernel's BTF"
  dir = scratch_dir
  path = field_object(dir)
  table = kaaneru::btf::open(kaaneru::btf::vmlinux_path)
  here = kaaneru::btf::field(table, "task_struct", ["pid"])[:offset]
  assert here > 0
  o = kaaneru::erufu::decode(read_bytes(path))
  relos = kaaneru::btf::read_core(
    kaaneru::erufu::section_of(o, ".BTF.ext")[:bytes],
    kaaneru::erufu::section_of(o, ".BTF")[:bytes]
  )
  assert first(first(relos)[:relos])[:access] == "0:0"
  assert contains?(xlated_of(path, []), "r3 += #{to_s(here)}")
  other_path = path_join(dir, "other.btf")
  word = kaaneru::btf::int_type("int", 4)
  write_bytes(
    other_path,
    kaaneru::btf::encode(
      [
        word,
        kaaneru::btf::sized_type(
          :struct,
          "task_struct",
          16,
          [{name: "pid", type: 1, bits: 96}]
        )
      ]
    )
  )
  other = xlated_of(path, ["kernel_btf", other_path])
  assert contains?(other, "r3 += 12")
  assert not contains?(other, "r3 += #{to_s(here)}")
  rm_rf(dir)
end

test "a clang object's CO-RE record for the same field equals blue's, and blue reads its own and clang's and binds them to this kernel"
  dir = scratch_dir
  source = path_join(dir, "core.c")
  clang_path = path_join(dir, "core_clang.o")
  write_file(
    source,
    unlines(
      [
        "struct task_struct { int pid; } __attribute__((preserve_access_index));",
        "char _license[] __attribute__((section(\"license\"), used)) = \"GPL\";",
        "static long (*probe_read)(void *, unsigned int, const void *) = (void *) 113;",
        "static void *(*current_task)(void) = (void *) 35;",
        "__attribute__((section(\"fentry/do_sys_openat2\"), used)) int on_open(void *ctx) {",
        "  struct task_struct *t = current_task();",
        "  int v = 0;",
        "  probe_read(&v, 4, &t->pid);",
        "  return 0;",
        "}"
      ]
    )
  )
  tool("clang", ["-target", "bpf", "-O2", "-g", "-c", source, "-o", clang_path])
  said = fn(path)
    o = kaaneru::erufu::decode(read_bytes(path))
    blob = kaaneru::erufu::section_of(o, ".BTF")[:bytes]
    t = kaaneru::btf::read(blob)
    map(
      (r) -> [kaaneru::btf::resolved(t, r[:type])[:name], r[:access], r[:kind]],
      flat_map(
        kaaneru::btf::read_core(
          kaaneru::erufu::section_of(o, ".BTF.ext")[:bytes],
          blob
        ),
        (s) -> s[:relos]
      )
    )
  end
  blue_path = field_object(dir)
  assert said(blue_path) == said(clang_path)
  assert said(blue_path) == [["task_struct", "0:0", 0]]
  table = kaaneru::btf::open(kaaneru::btf::vmlinux_path)
  map(
    fn(path)
      back = kaaneru::erufu::program_of(
        kaaneru::erufu::decode(read_bytes(path))
      )
      assert map((f) -> f[:path], back[:fields]) == [["pid"]]
      assert get(
        kaaneru::install_hook(back, table, {fentry: "do_sys_openat2"})[:prog],
        :fd
      ) != nil
    end,
    [blue_path, clang_path]
  )
  rm_rf(dir)
end

def value_program()
  assoc(
    assoc(
      assemble(
        [
          kaaneru::bpf::map_value_ref(1, :globals, 8),
          store(:dw, 1, 0, 40),
          kaaneru::bpf::load(:dw, 0, 1, 0),
          alu(:add, 0, 2),
          exit_program
        ]
      ),
      :maps,
      [declare_map(:globals, :array, 4, 16, 1)]
    ),
    :kind,
    :xdp
  )
end

test "a reference into a map's value in an object: libbpf loads it and it runs, blue reads it back and runs it, and the machine agrees"
  p = value_program
  dir = scratch_dir
  path = path_join(dir, "value.o")
  write_bytes(path, kaaneru::erufu::object(p))
  pin = "/sys/fs/bpf/blue_value_#{to_s(now_ms)}"
  tool("bpftool", ["prog", "load", path, pin])
  input = path_join(dir, "in")
  output = path_join(dir, "out")
  write_bytes(input, repeat(0, 64))
  said = begin
    bpftool_run(pin, input, output)
  ensure
    rm(pin)
  end
  assert contains?(said, "Return value: 42,")
  back = kaaneru::erufu::program_of(kaaneru::erufu::decode(read_bytes(path)))
  live = install(back)
  assert kaaneru::run(live[:prog], {packet: repeat(0, 64)})[:ret] == 42
  values = map_get(map_named(live, "globals"), int_bytes(0, 4))
  assert bytes_int(values, 8, 8) == 40
  assert kaaneru::bpf::run(p, {maps: p[:maps]}).ret == 42
  rm_rf(dir)
end

test "a compiled callback in an object: bpftool loads it and it answers as blue's own load does"
  compiled = compile(
    "kernel/suite.b",
    {entry: :fold_entry, kind: :xdp, on_fault: 0}
  )
  dir = scratch_dir
  path = path_join(dir, "fold.o")
  write_bytes(path, kaaneru::erufu::object(compiled))
  dumped = tool("bpftool", ["btf", "dump", "file", path]).stdout
  assert contains?(dumped, "FUNC 'fold_step' type_id=")
  assert contains?(dumped, "linkage=static")
  pin = "/sys/fs/bpf/blue_fold_#{to_s(now_ms)}"
  tool("bpftool", ["prog", "load", path, pin])
  input = path_join(dir, "in")
  output = path_join(dir, "out")
  write_bytes(input, pair_packet(40, 3))
  said = begin
    bpftool_run(pin, input, output)
  ensure
    rm(pin)
  end
  assert contains?(said, "Return value: 2,")
  live = install(compiled)
  in_kernel = kaaneru::run(live[:prog], {packet: pair_packet(40, 3)})
  assert read_bytes(output) == in_kernel[:packet]
  rm_rf(dir)
end

test "blue's reading of its own object loads as the compiled program does"
  compiled = compile(
    "kernel/programs/object.b",
    {entry: :on_packet, kind: :xdp, on_fault: 0, global: [:sum_into]}
  )
  back = kaaneru::erufu::program_of(
    kaaneru::erufu::decode(kaaneru::erufu::object(compiled))
  )
  live = install(back)
  got = kaaneru::run(live[:prog], {packet: pair_packet(40, 2)})
  assert got[:ret] == xdp_pass
  assert bytes_int(got[:packet], 24, 8, :big) == 42
end
