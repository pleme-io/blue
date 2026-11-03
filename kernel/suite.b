use("baito", %i[bytes_int int_bytes])

use(
  "bpf",
  %i[
    alu
    alu32
    assemble
    atomic
    call
    compile
    declare_map
    exit_program
    imm64
    jump
    jump32
    label
    load_signed
    map_ref
    neg
    packet_int
    packet_of
    packet_put
    r
    regular_ops
    store
    swap
    xdp_drop
    xdp_pass
  ]
)

use("btf")

use(
  "kaaneru",
  %i[
    attach_kprobe
    attach_kprobes
    attach_tracepoint
    close_object
    create_map
    detach
    drain
    install
    install_hook
    load
    map_delete
    map_get
    map_keys
    map_named
    map_put
    next_event
    open_events
    open_pinned
    pin
    prog_id
  ]
)

use("retsu", %i[first flat_map repeat size])

SEED = 7

def mix(a, b)
  low = bit_and(a, 255)
  high = bit_and(b, 65535)
  product = low * high + SEED
  if product % 5 == 3
    wrapping_mul(a, b)
  elsif a > b
    a - b
  elsif a == b
    bit_xor(shift_left(low, 3), shift_right_logical(b, 60))
  else
    a + b
  end
end

def mix_entry(ctx)
  packet_put(ctx, 16, 8, mix(packet_int(ctx, 0, 8), packet_int(ctx, 8, 8)))
  xdp_pass
end

def packet()
  repeat(0, 64)
end

def xdp(items)
  load(assemble(items), {kind: :xdp, name: "suite"})
end

def in_packet_then(body)
  [
    bpf::load(:w, 6, 1, 0),
    bpf::load(:w, 7, 1, 4),
    alu(:mov, 2, r(6)),
    alu(:add, 2, 8),
    jump(:gt, 2, r(7), :out),
    body,
    store(:dw, 6, 0, r(0)),
    label(:out),
    alu(:mov, 0, 2),
    exit_program
  ]
end

def kernel_out(p)
  kaaneru::run(load(p, {kind: :xdp, name: "suite"}), {packet:})[:packet]
end

def model_out(p)
  packet_of(bpf::run(p, {packet:}))
end

def agree?(p)
  kernel_out(p) == model_out(p)
end

def edge_values()
  [
    0,
    1,
    -1,
    2,
    7,
    -7,
    31,
    32,
    63,
    64,
    255,
    4_294_967_295,
    2_147_483_648,
    -2_147_483_648,
    9_223_372_036_854_775_807,
    shift_left(1, 63)
  ]
end

def edge_pairs()
  flat_map(edge_values, (a) -> map((b) -> [a, b], edge_values))
end

def alu_probe(form, op, pair)
  assemble(
    in_packet_then(
      [imm64(0, first(pair)), imm64(3, pair[1]), form(op, 0, r(3))]
    )
  )
end

def disagreements(probes)
  filter((row) -> not agree?(row[1]), probes)
end

test "a program assembled in blue loads into the real kernel and runs"
  got = kaaneru::run(xdp([alu(:mov, 0, 2), exit_program]), {packet:})
  assert got[:ret] == 2
  assert got[:packet] == packet
end

test "the kernel's verifier refuses a bad program and its log comes back"
  refusal = begin
    xdp([alu(:mov, 0, r(5)), exit_program])
  rescue :kernel_refused as e
    e
  end
  assert refusal.data.name == "EACCES"
  assert contains?(refusal.data.log, "R5 !read_ok")
end

test "the machine and the kernel agree on every 64-bit ALU operation over edge values"
  probes = flat_map(
    regular_ops,
    (op) -> map((pair) -> [[op, pair], alu_probe(alu, op, pair)], edge_pairs)
  )
  bad = disagreements(probes)
  assert map(first, bad) == []
end

test "the machine and the kernel agree on every 32-bit ALU operation over edge values"
  probes = flat_map(
    regular_ops,
    (op) -> map((pair) -> [[op, pair], alu_probe(alu32, op, pair)], edge_pairs)
  )
  bad = disagreements(probes)
  assert map(first, bad) == []
end

test "the machine and the kernel agree on sign extension, negation and byte swaps"
  unary = flat_map(
    edge_values,
    fn(v)
      [
        [[:movsx8, v], in_packet_then([imm64(3, v), alu(:movsx8, 0, r(3))])],
        [[:movsx16, v], in_packet_then([imm64(3, v), alu(:movsx16, 0, r(3))])],
        [[:movsx32, v], in_packet_then([imm64(3, v), alu(:movsx32, 0, r(3))])],
        [[:movsx8w, v], in_packet_then([imm64(3, v), alu32(:movsx8, 0, r(3))])],
        [[:neg, v], in_packet_then([imm64(0, v), neg(0)])],
        [[:neg32, v], in_packet_then([imm64(0, v), neg(0, 32)])],
        [[:be16, v], in_packet_then([imm64(0, v), swap(:be, 0, 16)])],
        [[:be32, v], in_packet_then([imm64(0, v), swap(:be, 0, 32)])],
        [[:be64, v], in_packet_then([imm64(0, v), swap(:be, 0, 64)])],
        [[:le16, v], in_packet_then([imm64(0, v), swap(:le, 0, 16)])],
        [[:le32, v], in_packet_then([imm64(0, v), swap(:le, 0, 32)])],
        [[:le64, v], in_packet_then([imm64(0, v), swap(:le, 0, 64)])],
        [[:swap16, v], in_packet_then([imm64(0, v), swap(:any, 0, 16)])],
        [[:swap32, v], in_packet_then([imm64(0, v), swap(:any, 0, 32)])],
        [[:swap64, v], in_packet_then([imm64(0, v), swap(:any, 0, 64)])]
      ]
    end
  )
  bad = filter((row) -> not agree?(assemble(row[1])), unary)
  assert map(first, bad) == []
end

test "the machine and the kernel agree on every jump condition over edge values"
  conds = %i[eq ne gt ge lt le sgt sge slt sle set]
  probes = flat_map(
    conds,
    fn(op)
      flat_map(
        edge_pairs,
        fn(pair)
          body = fn(form)
            in_packet_then(
              [
                imm64(3, first(pair)),
                imm64(4, pair[1]),
                alu(:mov, 0, 1),
                form(op, 3, r(4), :taken),
                alu(:mov, 0, 0),
                label(:taken)
              ]
            )
          end
          [
            [[op, pair, 64], assemble(body(jump))],
            [[op, pair, 32], assemble(body(jump32))]
          ]
        end
      )
    end
  )
  bad = disagreements(probes)
  assert map(first, bad) == []
end

test "the machine and the kernel agree on loads, stores and atomics at every width"
  value = 81_985_529_216_486_895
  rows = flat_map(
    %i[b h w dw],
    fn(sz)
      [
        in_packet_then(
          [imm64(3, value), store(sz, 6, 0, r(3)), bpf::load(sz, 0, 6, 0)]
        ),
        in_packet_then(
          [imm64(0, 0), store(sz, 6, 0, -2), bpf::load(sz, 0, 6, 0)]
        )
      ]
    end
  )
  signed = map(
    fn(sz)
      in_packet_then(
        [imm64(3, -2), store(sz, 6, 0, r(3)), load_signed(sz, 0, 6, 0)]
      )
    end,
    %i[b h w]
  )
  atomics = flat_map(
    %i[add or and xor fetch_add fetch_or fetch_and fetch_xor xchg cmpxchg],
    fn(op)
      map(
        fn(sz)
          in_packet_then(
            [
              imm64(3, value),
              store(:dw, 10, -8, r(3)),
              imm64(0, 5),
              imm64(4, 12),
              atomic(op, sz, 10, -8, 4),
              bpf::load(:dw, 5, 10, -8),
              alu(:add, 0, r(5)),
              alu(:add, 0, r(4))
            ]
          )
        end,
        %i[w dw]
      )
    end
  )
  bad = filter((p) -> not agree?(assemble(p)), append(*[rows, signed, atomics]))
  assert size(bad) == 0
end

test "a map made in blue holds, misses and gives back what the kernel says"
  m = create_map(declare_map("suite_hash", :hash, 4, 8, 8))
  key = int_bytes(7, 4)
  assert map_get(m, key).nil?
  map_put(m, key, int_bytes(99, 8))
  assert bytes_int(map_get(m, key), 0, 8) == 99
  assert map_keys(m) == [key]
  assert map_delete(m, key) == true
  assert map_delete(m, key) == false
  assert map_keys(m) == []
  refused = map_put(m, key, int_bytes(1, 8), 2) rescue :refused
  assert refused == :refused
  close_object(m)
end

test "a program counts into a map, and the kernel's count equals the machine's"
  spec = declare_map(:suite_counts, :array, 4, 8, 4)
  m = create_map(spec)
  p = assemble(
    [
      store(:w, 10, -4, 2),
      alu(:mov, 2, r(10)),
      alu(:add, 2, -4),
      map_ref(1, :suite_counts),
      call(:map_lookup_elem),
      jump(:eq, 0, 0, :out),
      alu(:mov, 1, 5),
      atomic(:add, :dw, 0, 0, 1),
      label(:out),
      alu(:mov, 0, 2),
      exit_program
    ]
  )
  loaded = load(p, {kind: :xdp, maps: [m], name: "suite_count"})
  assert kaaneru::run(loaded, {packet:, repeat: 3})[:ret] == 2
  assert bytes_int(map_get(m, int_bytes(2, 4)), 0, 8) == 15
  model = bpf::run(p, {packet:, maps: [spec]})
  assert bpf::map_value(model, :suite_counts, int_bytes(2, 4)) ==
    int_bytes(5, 8)
end

test "a ring buffer record from the kernel reaches blue, and an empty one answers nil"
  m = create_map(declare_map(:suite_ring, :ringbuf, 0, 0, 4096))
  ring = open_events(m)
  assert next_event(ring, 0).nil?
  p = assemble(
    [
      map_ref(1, :suite_ring),
      alu(:mov, 2, 8),
      alu(:mov, 3, 0),
      call(:ringbuf_reserve),
      jump(:eq, 0, 0, :out),
      imm64(1, 81_985_529_216_486_895),
      store(:dw, 0, 0, r(1)),
      alu(:mov, 1, r(0)),
      alu(:mov, 2, 0),
      call(:ringbuf_submit),
      label(:out),
      alu(:mov, 0, 2),
      exit_program
    ]
  )
  loaded = load(p, {kind: :xdp, maps: [m], name: "suite_ring"})
  kaaneru::run(loaded, {packet:, repeat: 2})
  got = drain(ring)
  assert size(got) == 2
  assert bytes_int(first(got), 0, 8) == 81_985_529_216_486_895
  assert next_event(ring, 0).nil?
end

test "a pinned map outlives its descriptor and comes back from its path"
  path = "/sys/fs/bpf/blue_suite_#{to_s(now_ms)}"
  m = create_map(declare_map(:suite_pin, :array, 4, 8, 1))
  map_put(m, int_bytes(0, 4), int_bytes(41, 8))
  pin(m, path)
  close_object(m)
  back = open_pinned(path)
  shaped = assoc(declare_map(:suite_pin, :array, 4, 8, 1), :fd, back[:fd])
  assert bytes_int(map_get(shaped, int_bytes(0, 4)), 0, 8) == 41
  rm(path)
end

test "the kernel gives a loaded program an id"
  assert prog_id(xdp([alu(:mov, 0, 2), exit_program])) > 0
end

test "a tracepoint program attached in blue sees this machine exec, and detach ends it"
  m = create_map(declare_map(:suite_exec, :ringbuf, 0, 0, 65536))
  ring = open_events(m)
  p = assemble(
    [
      call(:get_current_pid_tgid),
      alu(:mov, 6, r(0)),
      map_ref(1, :suite_exec),
      alu(:mov, 2, 8),
      alu(:mov, 3, 0),
      call(:ringbuf_reserve),
      jump(:eq, 0, 0, :out),
      store(:dw, 0, 0, r(6)),
      alu(:mov, 1, r(0)),
      alu(:mov, 2, 0),
      call(:ringbuf_submit),
      label(:out),
      alu(:mov, 0, 0),
      exit_program
    ]
  )
  loaded = load(p, {kind: :tracepoint, maps: [m], name: "suite_exec"})
  link = attach_tracepoint(loaded, "sched", "sched_process_exec")
  exec_capture("true")
  first_event = next_event(ring, 2000)
  assert not first_event.nil?
  assert bytes_int(first_event, 0, 8) != 0
  detach(link)
  drain(ring)
  exec_capture("true")
  assert next_event(ring, 200).nil?
end

def ip_packet(proto)
  append(*[repeat(0, 12), [8, 0], repeat(0, 9), [proto], repeat(0, 20)])
end

test "a filter written in blue and compiled by blue drops ICMP in the real kernel and counts it"
  compiled = compile(
    "kernel/programs/filter.b",
    {entry: :filter, kind: :xdp, on_fault: 0}
  )
  live = install(compiled)
  counts = map_named(live, :filter_counts)
  assert kaaneru::run(live[:prog], {packet: ip_packet(1)})[:ret] == xdp_drop
  assert kaaneru::run(live[:prog], {packet: ip_packet(1)})[:ret] == xdp_drop
  assert kaaneru::run(live[:prog], {packet: ip_packet(6)})[:ret] == xdp_pass
  assert kaaneru::run(live[:prog], {packet: repeat(0, 20)})[:ret] == xdp_pass
  assert bytes_int(map_get(counts, int_bytes(1, 4)), 0, 8) == 2
  assert bytes_int(map_get(counts, int_bytes(6, 4)), 0, 8) == 1
  assert bytes_int(map_get(counts, int_bytes(17, 4)), 0, 8) == 0
  model = bpf::run(compiled, {packet: ip_packet(1), maps: compiled[:maps]})
  assert model[:ret] == xdp_drop
end

def mix_inputs()
  append(
    edge_pairs,
    map(
      fn(i)
        [i * 2_654_435_761, wrapping_mul(i + 11, -7_046_029_254_386_353_131)]
      end,
      range(0, 200)
    )
  )
end

def interpreted(pair)
  {ret: xdp_pass, out: mix(first(pair), pair[1])} rescue {ret: 0}
end

def mix_packet(pair)
  append(
    *[
      int_bytes(first(pair), 8, :big),
      int_bytes(pair[1], 8, :big),
      repeat(0, 48)
    ]
  )
end

def answer_of(ret, bytes)
  if ret == 0
    {ret: 0}
  else
    {ret:, out: bytes_int(bytes, 16, 8, :big, true)}
  end
end

test "one source: the interpreter, the machine and the real kernel agree, and a raise is a fault"
  compiled = compile(
    "kernel/suite.b",
    {entry: :mix_entry, kind: :xdp, on_fault: 0}
  )
  live = install(compiled)
  bad = filter(
    fn(pair)
      input = mix_packet(pair)
      want = interpreted(pair)
      vm = bpf::run(compiled, {packet: input})
      in_kernel = kaaneru::run(live[:prog], {packet: input})
      vm_answer = answer_of(vm[:ret], packet_of(vm))
      kernel_answer = answer_of(in_kernel[:ret], in_kernel[:packet])
      not (want == vm_answer and want == kernel_answer)
    end,
    mix_inputs
  )
  assert map(first, bad) == []
end

test "a nil answered by the kernel's map narrows as blue narrows it, and tail recursion is a bounded loop"
  compiled = compile(
    "kernel/programs/arith.b",
    {entry: :entry, kind: :xdp, on_fault: 0}
  )
  live = install(compiled)
  input = append(int_bytes(5, 8, :big), int_bytes(5, 8, :big), repeat(0, 48))
  once = kaaneru::run(live[:prog], {packet: input})
  twice = kaaneru::run(live[:prog], {packet: input})
  assert once[:ret] == xdp_pass
  assert bytes_int(once[:packet], 24, 8, :big) == 28
  assert bytes_int(once[:packet], 32, 8, :big) == 0
  assert bytes_int(twice[:packet], 32, 8, :big) == 5
end

test "a blue kprobe on a kernel function reports through a ring buffer, and detach ends it"
  live = install(
    compile(
      "kernel/programs/opens.b",
      {entry: :on_open, kind: :kprobe, on_fault: 0}
    )
  )
  ring = open_events(map_named(live, :opens_events))
  link = attach_kprobe(live[:prog], "do_sys_openat2")
  read_file("/proc/version")
  got = next_event(ring, 2000)
  detach(link)
  assert not got.nil?
  assert size(got) == 16
  assert bytes_int(got, 8, 8) == 7
  drain(ring)
  read_file("/proc/version")
  assert next_event(ring, 200).nil?
end

test "a kprobe_multi link works where the kernel has FPROBE, and is a named refusal where it has none"
  live = install(
    compile(
      "kernel/programs/opens.b",
      {entry: :on_open, kind: :kprobe, on_fault: 0}
    ),
    {attach: :trace_kprobe_multi}
  )
  answer = begin
    detach(attach_kprobes(live[:prog], ["do_sys_openat2"]))
    :attached
  rescue :kernel_refused as e
    e.data.name
  end
  assert member?(answer, [:attached, "EOPNOTSUPP"])
end

test "fentry found through BTF reads a kernel struct whose offset came from this kernel"
  table = btf::open(btf::vmlinux_path)
  compiled = compile(
    "kernel/programs/fentry.b",
    {entry: :on_open, kind: :tracing, on_fault: 0}
  )
  live = install_hook(compiled, table, {fentry: "do_sys_openat2"})
  ring = open_events(map_named(live, :fentry_events))
  read_file("/proc/version")
  got = next_event(ring, 2000)
  detach(live[:link])
  assert not got.nil?
  tid = bit_and(bytes_int(got, 0, 8), 4_294_967_295)
  assert bytes_int(got, 8, 8) == tid
end

test "an LSM program counts this machine's file opens, allowing each"
  table = btf::open(btf::vmlinux_path)
  compiled = compile(
    "kernel/programs/lsm_count.b",
    {entry: :on_file_open, kind: :lsm, on_fault: 0}
  )
  live = install_hook(compiled, table, {lsm: "file_open"})
  read_file("/proc/version")
  count = bytes_int(map_get(map_named(live, :lsm_opens), int_bytes(0, 4)), 0, 8)
  detach(live[:link])
  assert count >= 1
end

test "an LSM program denies exactly this process, and only while its target is set"
  table = btf::open(btf::vmlinux_path)
  compiled = compile(
    "kernel/programs/lsm_deny.b",
    {entry: :on_file_open, kind: :lsm, on_fault: 0}
  )
  live = install_hook(compiled, table, {lsm: "file_open"})
  target = map_named(live, :lsm_target)
  assert (read_file("/proc/version") rescue :refused) != :refused
  tid = current_tid
  map_put(target, int_bytes(0, 4), int_bytes(tid, 8))
  denied = read_file("/proc/version") rescue :refused
  map_put(target, int_bytes(0, 4), int_bytes(0, 8))
  allowed = read_file("/proc/version") rescue :refused
  detach(live[:link])
  assert denied == :refused
  assert allowed != :refused
end

def current_tid()
  to_int(first_word(read_file("/proc/thread-self/stat")))
end

def first_word(text)
  first(split(text, " "))
end

test "compile refuses a file that does not check, naming why"
  dir = path_join(getenv("TMPDIR", "/tmp"), "bpf-compile-#{to_s(now_ms)}")
  mkdir_p(dir)
  bad = path_join(dir, "bad.b")
  write_program(bad, unlines(["def entry(ctx)", "  missing_name", "end"]))
  refused = begin
    compile(bad, {entry: :entry, kind: :xdp, on_fault: 0})
  rescue :bpf_compile as e
    e.message
  end
  rm_rf(dir)
  assert contains?(refused, "does not check")
end
