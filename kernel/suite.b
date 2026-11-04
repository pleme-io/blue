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
    attach_raw_tracepoint
    attach_sampling
    attach_tracepoint
    attach_uprobes
    close_object
    create_map
    detach
    drain
    entry_offset_of
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
  get(
    kaaneru::run(
      load(p, {kind: :xdp, name: "suite", signed_division: :trust}),
      {packet:}
    ),
    :packet
  )
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

def lowest_by_minus_one?(pair, width)
  if width == 64
    first(pair) == shift_left(1, 63) and pair[1] == -1
  else
    bit_and(first(pair), 4_294_967_295) == 2_147_483_648 and
      bit_and(pair[1], 4_294_967_295) == 4_294_967_295
  end
end

def traps_here?(op, pair, width)
  kaaneru::division_traps?(kaaneru::kernel_release) and
    member?(op, %i[sdiv smod]) and
    lowest_by_minus_one?(pair, width)
end

def safe_pairs(op, width)
  retsu::reject((pair) -> traps_here?(op, pair, width), edge_pairs)
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
    fn(op)
      map((pair) -> [[op, pair], alu_probe(alu, op, pair)], safe_pairs(op, 64))
    end
  )
  bad = disagreements(probes)
  assert map(first, bad) == []
end

test "the machine and the kernel agree on every 32-bit ALU operation over edge values"
  probes = flat_map(
    regular_ops,
    fn(op)
      map(
        (pair) -> [[op, pair], alu_probe(alu32, op, pair)],
        safe_pairs(op, 32)
      )
    end
  )
  bad = disagreements(probes)
  assert map(first, bad) == []
end

def lowest_by_minus_one(form)
  assemble(
    in_packet_then(
      [imm64(0, shift_left(1, 63)), imm64(3, -1), form(:sdiv, 0, r(3))]
    )
  )
end

test "the lowest value by -1 is refused by name where it would panic the kernel, and agrees where it cannot"
  release = kaaneru::kernel_release
  mode = if getenv("KERNEL_SUITE_DIVISION_GUARD") == "off"
    :trust
  else
    :refuse
  end
  probes = [lowest_by_minus_one(alu), lowest_by_minus_one(alu32)]
  if kaaneru::division_traps?(release) and mode == :refuse
    refused = map(
      fn(p)
        begin
          load(p, {kind: :xdp, name: "suite"})
          nil
        rescue :division_trap as e
          e.data.release
        end
      end,
      probes
    )
    assert refused == [release, release]
    write_stderr(
      unlines(
        ["skipped on #{release}: sdiv and smod of the lowest value by -1"]
      )
    )
  else
    assert disagreements(map((p) -> [nil, p], probes)) == []
  end
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

test "one source with a global subprogram: the interpreter, the machine and the real kernel agree, and a raise inside it is a fault"
  compiled = compile(
    "kernel/suite.b",
    {entry: :mix_entry, kind: :xdp, on_fault: 0, global: [:mix]}
  )
  assert size(compiled[:funcs]) == 2
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
  ring = open_events(map_named(live, :opens_events))
  answer = begin
    link = attach_kprobes(live[:prog], ["do_sys_openat2"])
    read_file("/proc/version")
    got = next_event(ring, 2000)
    detach(link)
    assert not got.nil?
    "attached"
  rescue :kernel_refused as e
    e.data.name
  end
  want = getenv("KERNEL_SUITE_KPROBE_MULTI")
  if want.nil?
    assert member?(answer, %w[attached EOPNOTSUPP])
  else
    assert answer == want
  end
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

def ip_frame(proto, ttl, pad)
  append(
    *[
      repeat(0, 12),
      [8, 0, 69],
      repeat(0, 7),
      [ttl, proto],
      repeat(0, 10),
      repeat(0, pad)
    ]
  )
end

def other_frame(pad)
  append(*[repeat(0, 12), [18, 52], repeat(0, pad)])
end

def frames()
  append(
    flat_map(
      [1, 6, 17, 255],
      (proto) -> map((pad) -> ip_frame(proto, 64, pad), [0, 1, 40, 200])
    ),
    map(other_frame, [0, 1, 5, 19, 20, 21, 64])
  )
end

def parity_row(kind, file, entry)
  compiled = compile(file, {entry:, kind:, on_fault: 1})
  live = install(compiled)
  bad = filter(
    fn(frame)
      kernel = kaaneru::run(live[:prog], {packet: frame})[:ret]
      model = bpf::run(compiled, {packet: frame, maps: compiled[:maps]})[:ret]
      kernel != model
    end,
    frames
  )
  [kind, size(bad)]
end

test "the machine and the kernel agree on every socket-buffer program type over one set of frames"
  rows = [
    [:sched_cls, "kernel/programs/tc_filter.b", :tc_filter],
    [:sched_act, "kernel/programs/tc_filter.b", :tc_filter],
    [:flow_dissector, "kernel/programs/tc_filter.b", :tc_filter],
    [:cgroup_skb, "kernel/programs/socket_len.b", :short_frame],
    [:lwt_in, "kernel/programs/l3_filter.b", :l3_filter],
    [:lwt_out, "kernel/programs/l3_filter.b", :l3_filter],
    [:lwt_xmit, "kernel/programs/l3_filter.b", :l3_filter],
    [:socket_filter, "kernel/programs/socket_len.b", :socket_len]
  ]
  got = map((row) -> parity_row(*row), rows)
  assert got == map((row) -> [first(row), 0], rows)
end

def cgroup_skb_reads?(release)
  if starts_with?(release, "6.6.") or starts_with?(release, "6.12.")
    false
  elsif starts_with?(release, "7.")
    true
  end
end

test "BPF_PROG_RUN gives a cgroup skb program a packet to read directly at 7.0.11, and none at 6.6 and 6.12, where that read is measured attached"
  live = install(
    compile(
      "kernel/programs/l3_filter.b",
      {entry: :l3_filter, kind: :cgroup_skb, on_fault: 1}
    )
  )
  got = kaaneru::run(live[:prog], {packet: ip_frame(1, 64, 40)})[:ret]
  seen = bytes_int(map_get(map_named(live, :l3_seen), int_bytes(1, 4)), 0, 8)
  assert [got, seen] == [0, 1] or [got, seen] == [1, 0]
  reads = cgroup_skb_reads?(kaaneru::kernel_release)
  if reads != nil
    assert seen == 1 == reads
  end
end

test "a socket-buffer program's map counts in the kernel what the machine counts"
  compiled = compile(
    "kernel/programs/l3_filter.b",
    {entry: :l3_filter, kind: :lwt_in, on_fault: 1}
  )
  live = install(compiled)
  seen = map_named(live, :l3_seen)
  map((f) -> kaaneru::run(live[:prog], {packet: f}), frames)
  key = int_bytes(1, 4)
  model = reduce(
    fn(acc, f)
      st = bpf::run(compiled, {packet: f, maps: compiled[:maps]})
      acc + bytes_int(bpf::map_value(st, :l3_seen, key), 0, 8)
    end,
    0,
    frames
  )
  assert bytes_int(map_get(seen, key), 0, 8) == model
  assert model == 4
end

def lookup_ctx(family, protocol, port)
  append(
    *[
      repeat(0, 8),
      int_bytes(family, 4),
      int_bytes(protocol, 4),
      repeat(0, 44),
      int_bytes(port, 4),
      repeat(0, 8)
    ]
  )
end

test "an sk_lookup program decides on its context in the machine and the kernel alike"
  compiled = compile(
    "kernel/programs/sk_lookup.b",
    {entry: :sk_lookup, kind: :sk_lookup, on_fault: 1}
  )
  live = install(compiled)
  cases = [[2, 6, 80, 0], [2, 6, 81, 1], [2, 17, 80, 1], [10, 6, 80, 1]]
  got = map(
    fn(c)
      ctx = lookup_ctx(c[0], c[1], c[2])
      [
        kaaneru::run(live[:prog], {ctx:})[:ret],
        bpf::run(compiled, {ctx:})[:ret],
        c[3]
      ]
    end,
    cases
  )
  assert got == map((c) -> [c[3], c[3], c[3]], cases)
end

test "a raw tracepoint program runs on arguments it is given, and the machine agrees"
  compiled = compile(
    "kernel/programs/args.b",
    {entry: :sum_args, kind: :raw_tracepoint, on_fault: 0}
  )
  live = install(compiled)
  got = map(
    fn(pair)
      ctx = append(int_bytes(first(pair), 8), int_bytes(pair[1], 8))
      [
        kaaneru::run(live[:prog], {ctx:})[:ret],
        bpf::run(compiled, {ctx:})[:ret],
        first(pair) + pair[1]
      ]
    end,
    [[1, 2], [0, 0], [40, 2]]
  )
  assert got == [[3, 3, 3], [0, 0, 0], [42, 42, 42]]
end

test "a syscall program runs sleepable on its context, and its writes come back"
  compiled = compile(
    "kernel/programs/args.b",
    {entry: :sum_words, kind: :syscall, on_fault: 0}
  )
  live = install(compiled)
  ctx = append(int_bytes(30, 4), int_bytes(12, 4))
  assert kaaneru::run(live[:prog], {ctx:})[:ret] == 42
  assert bpf::run(compiled, {ctx:})[:ret] == 42
  writer = assemble(
    [
      bpf::load(:w, 2, 1, 0),
      alu(:add, 2, 1),
      store(:w, 1, 4, r(2)),
      alu(:mov, 0, 7),
      exit_program
    ]
  )
  answer = kaaneru::run(
    load(writer, {kind: :syscall, name: "suite_sys"}),
    {ctx:}
  )
  assert answer[:ret] == 7
  assert bytes_int(answer[:ctx], 4, 4) == 31
end

test "a netfilter program runs on a frame it is given, and decides from the real socket buffer"
  table = btf::open(btf::vmlinux_path)
  live = install(
    compile(
      "kernel/programs/nf_filter.b",
      {entry: :nf_filter, kind: :netfilter, on_fault: 1}
    ),
    {btf: table}
  )
  local_in = append([1, 2], repeat(0, 46))
  ret = fn(proto, ttl)
    get(
      kaaneru::run(
        live[:prog],
        {packet: ip_frame(proto, ttl, 20), ctx: local_in}
      ),
      :ret
    )
  end
  assert ret(1, 33) == 0
  assert ret(1, 34) == 1
  assert ret(6, 33) == 1
  seen = map_named(live, :nf_seen)
  assert bytes_int(map_get(seen, int_bytes(1, 4)), 0, 8) == 2
  assert bytes_int(map_get(seen, int_bytes(6, 4)), 0, 8) == 1
end

test "fexit reads the kernel's own argument and return value at its test function"
  table = btf::open(btf::vmlinux_path)
  live = install_hook(
    compile(
      "kernel/programs/fexit_args.b",
      {entry: :on_return, kind: :tracing, on_fault: 0}
    ),
    table,
    {fexit: "bpf_fentry_test1"}
  )
  seen = map_named(live, :fexit_seen)
  kaaneru::run(live[:prog], {})
  arg = bytes_int(map_get(seen, int_bytes(0, 4)), 0, 8)
  ret = bytes_int(map_get(seen, int_bytes(1, 4)), 0, 8)
  detach(live[:link])
  assert [arg, ret] == [1, 2]
end

test "fmod_ret replaces a kernel function's answer and skips its body"
  table = btf::open(btf::vmlinux_path)
  live = install_hook(
    compile(
      "kernel/programs/fmod_ret.b",
      {entry: :replaced, kind: :tracing, on_fault: 0}
    ),
    table,
    {fmod_ret: "bpf_modify_return_test"}
  )
  got = kaaneru::run(live[:prog], {})[:ret]
  detach(live[:link])
  side_effects = 1
  second_function = 29
  assert got == shift_left(side_effects, 16) + 5 + second_function
end

test "an LSM program has no BPF_PROG_RUN, and the refusal names it"
  table = btf::open(btf::vmlinux_path)
  live = install_hook(
    compile(
      "kernel/programs/count.b",
      {entry: :on_event, kind: :lsm, on_fault: 0}
    ),
    table,
    {lsm: "file_open"}
  )
  got = begin
    kaaneru::run(live[:prog], {ctx: repeat(0, 8)})
    :ran
  rescue :kernel_refused as e
    e.data.name
  end
  detach(live[:link])
  assert got == "ENOTSUPP"
end

def task_ids_program(pid_offset)
  assemble(
    [
      bpf::load(:dw, 6, 1, 0),
      bpf::load(:dw, 7, 1, 8),
      jump(:eq, 7, 0, :out),
      bpf::load(:dw, 1, 6, 0),
      bpf::load(:w, 8, 7, pid_offset),
      store(:w, 10, -4, r(8)),
      alu(:mov, 2, r(10)),
      alu(:add, 2, -4),
      alu(:mov, 3, 4),
      call(:seq_write),
      label(:out),
      alu(:mov, 0, 0),
      exit_program
    ]
  )
end

test "a task iterator lists this very thread through a pin read back"
  table = btf::open(btf::vmlinux_path)
  compiled = assoc(
    assoc(
      task_ids_program(btf::field(table, "task_struct", ["pid"])[:offset]),
      :kind,
      :tracing
    ),
    :name,
    "suite_tasks"
  )
  live = install_hook(compiled, table, {iter: "task"})
  path = "/sys/fs/bpf/blue_suite_iter_#{to_s(now_ms)}"
  bytes = kaaneru::iterate(live[:link], path)
  detach(live[:link])
  ids = map((i) -> bytes_int(bytes, i * 4, 4), range(0, floor(size(bytes) / 4)))
  assert size(bytes) % 4 == 0
  assert member?(current_tid, ids)
  assert member?(1, ids)
  assert not path_exists(path)
end

test "a raw tracepoint program sees this machine exec, and detach ends it"
  live = install(
    compile(
      "kernel/programs/count.b",
      {entry: :on_event, kind: :raw_tracepoint, on_fault: 0}
    )
  )
  hits = map_named(live, :hits)
  key = int_bytes(0, 4)
  link = attach_raw_tracepoint(live[:prog], "sched_process_exec")
  exec_capture("true")
  during = bytes_int(map_get(hits, key), 0, 8)
  detach(link)
  sleep_ms(50)
  settled = bytes_int(map_get(hits, key), 0, 8)
  exec_capture("true")
  sleep_ms(50)
  assert during >= 1
  assert bytes_int(map_get(hits, key), 0, 8) == settled
end

test "a perf_event program runs on the CPU's clock, and detach ends it"
  live = install(
    compile(
      "kernel/programs/count.b",
      {entry: :on_event, kind: :perf_event, on_fault: 0}
    )
  )
  hits = map_named(live, :hits)
  key = int_bytes(0, 4)
  link = attach_sampling(live[:prog], 1_000_000)
  sleep_ms(200)
  detach(link)
  sleep_ms(20)
  settled = bytes_int(map_get(hits, key), 0, 8)
  sleep_ms(100)
  assert settled >= 1
  assert bytes_int(map_get(hits, key), 0, 8) == settled
end

test "a uprobe_multi link counts an executable's own start, and only while it holds"
  dir = path_join(getenv("TMPDIR", "/tmp"), "blue_suite_uprobe_#{to_s(now_ms)}")
  mkdir_p(dir)
  here = path_join(dir, "head")
  source = trim(exec_capture("sh", "-c", "command -v head").stdout)
  exec_capture("cp", "-L", source, here)
  live = install(
    compile(
      "kernel/programs/count.b",
      {entry: :on_event, kind: :kprobe, on_fault: 0}
    ),
    {attach: :trace_uprobe_multi}
  )
  hits = map_named(live, :hits)
  key = int_bytes(0, 4)
  result = begin
    link = attach_uprobes(live[:prog], here, [entry_offset_of(here)])
    ran = exec_capture(here, "--version").status
    exec_capture(source, "--version")
    during = bytes_int(map_get(hits, key), 0, 8)
    detach(link)
    exec_capture(here, "--version")
    [ran, during, bytes_int(map_get(hits, key), 0, 8)]
  ensure
    rm_rf(dir)
  end
  assert result == [0, 1, 1]
end
