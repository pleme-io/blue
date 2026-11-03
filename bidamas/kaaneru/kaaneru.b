@moduledoc """
kaaneru (カーネル) — the Linux kernel, spoken from blue: maps, programs, links and ring buffers over `bpf(2)`, with every struct a `baito` layout and no C library in the path.

`bpf` builds programs and runs them on a pure machine anywhere; this package loads them into the kernel on Linux. Off Linux each call raises :unsupported. A kernel refusal raises :kernel_refused with data {errno:, name:, log:}, the verifier's log included.

The words need the `kernel_bpf` capability, which holds the kernel: grant it to what would otherwise run as root. The pure words here (the layouts, `kind_id`, `errno_name`, `struct_fields`) need nothing.

    errno_name(13) #=> "EACCES"
    kind_id(:prog, :xdp) #=> 6
    width(prog_load_layout) #=> 152
"""

use("baito", %i[field_of layout offset unpack width])
use("bpf", %i[bind_fields encode_insn])
use("btf")
use("retsu", %i[first flat_map index_of last size take_while])

@doc """
commands: `enum bpf_cmd`, each by its number.

    first(commands) #=> :map_create
"""
def commands()
  %i[
    map_create
    map_lookup_elem
    map_update_elem
    map_delete_elem
    map_get_next_key
    prog_load
    obj_pin
    obj_get
    prog_attach
    prog_detach
    prog_test_run
    prog_get_next_id
    map_get_next_id
    prog_get_fd_by_id
    map_get_fd_by_id
    obj_get_info_by_fd
    prog_query
    raw_tracepoint_open
    btf_load
    btf_get_fd_by_id
    task_fd_query
    map_lookup_and_delete_elem
    map_freeze
    btf_get_next_id
    map_lookup_batch
    map_lookup_and_delete_batch
    map_update_batch
    map_delete_batch
    link_create
    link_update
    link_get_fd_by_id
    link_get_next_id
    enable_stats
    iter_create
    link_detach
    prog_bind_map
    token_create
  ]
end

@doc """
map_kinds: `enum bpf_map_type`, each by its number.

    nth(2, map_kinds) #=> :array
"""
def map_kinds()
  %i[
    unspec
    hash
    array
    prog_array
    perf_event_array
    percpu_hash
    percpu_array
    stack_trace
    cgroup_array
    lru_hash
    lru_percpu_hash
    lpm_trie
    array_of_maps
    hash_of_maps
    devmap
    sockmap
    cpumap
    xskmap
    sockhash
    cgroup_storage_deprecated
    reuseport_sockarray
    percpu_cgroup_storage_deprecated
    queue
    stack
    sk_storage
    devmap_hash
    struct_ops
    ringbuf
    inode_storage
    task_storage
    bloom_filter
    user_ringbuf
    cgrp_storage
    arena
  ]
end

@doc """
prog_kinds: `enum bpf_prog_type`, each by its number.

    nth(6, prog_kinds) #=> :xdp
"""
def prog_kinds()
  %i[
    unspec
    socket_filter
    kprobe
    sched_cls
    sched_act
    tracepoint
    xdp
    perf_event
    cgroup_skb
    cgroup_sock
    lwt_in
    lwt_out
    lwt_xmit
    sock_ops
    sk_skb
    cgroup_device
    sk_msg
    raw_tracepoint
    cgroup_sock_addr
    lwt_seg6local
    lirc_mode2
    sk_reuseport
    flow_dissector
    cgroup_sysctl
    raw_tracepoint_writable
    cgroup_sockopt
    tracing
    struct_ops
    ext
    lsm
    sk_lookup
    syscall
    netfilter
  ]
end

@doc """
attach_kinds: `enum bpf_attach_type`, each by its number.

    nth(37, attach_kinds) #=> :xdp
"""
def attach_kinds()
  %i[
    cgroup_inet_ingress
    cgroup_inet_egress
    cgroup_inet_sock_create
    cgroup_sock_ops
    sk_skb_stream_parser
    sk_skb_stream_verdict
    cgroup_device
    sk_msg_verdict
    cgroup_inet4_bind
    cgroup_inet6_bind
    cgroup_inet4_connect
    cgroup_inet6_connect
    cgroup_inet4_post_bind
    cgroup_inet6_post_bind
    cgroup_udp4_sendmsg
    cgroup_udp6_sendmsg
    lirc_mode2
    flow_dissector
    cgroup_sysctl
    cgroup_udp4_recvmsg
    cgroup_udp6_recvmsg
    cgroup_getsockopt
    cgroup_setsockopt
    trace_raw_tp
    trace_fentry
    trace_fexit
    modify_return
    lsm_mac
    trace_iter
    cgroup_inet4_getpeername
    cgroup_inet6_getpeername
    cgroup_inet4_getsockname
    cgroup_inet6_getsockname
    xdp_devmap
    cgroup_inet_sock_release
    xdp_cpumap
    sk_lookup
    xdp
    sk_skb_verdict
    sk_reuseport_select
    sk_reuseport_select_or_migrate
    perf_event
    trace_kprobe_multi
    lsm_cgroup
    struct_ops
    netfilter
    tcx_ingress
    tcx_egress
    trace_uprobe_multi
    cgroup_unix_connect
    cgroup_unix_sendmsg
    cgroup_unix_recvmsg
    cgroup_unix_getpeername
    cgroup_unix_getsockname
    netkit_primary
    netkit_peer
    trace_kprobe_session
    trace_uprobe_session
  ]
end

@doc """
kind_id: the kernel's number for a name in one of its tables, :command, :map, :prog or :attach, from `include/uapi/linux/bpf.h` at 6.16. An unknown name raises.

    kind_id(:command, :prog_load) #=> 5
    kind_id(:map, :ringbuf) #=> 27
    kind_id(:attach, :xdp) #=> 37
    (kind_id(:map, :nope) rescue :refused) #=> :refused
"""
def kind_id(table, name)
  names = case table
  when :command
    commands
  when :map
    map_kinds
  when :prog
    prog_kinds
  when :attach
    attach_kinds
  else
    raise(:bad_option, "no kernel table #{to_s(table)}")
  end
  at = index_of(names, name)
  if at.nil? or at < 0
    raise(:bad_option, "the kernel's #{to_s(table)} table has no #{to_s(name)}")
  end
  at
end

@doc """
errno_name: the name of an errno, or its number as text when this table does not hold it.

    errno_name(22) #=> "EINVAL"
    errno_name(9999) #=> "9999"
"""
def errno_name(n)
  row = find(
    [
      [1, "EPERM"],
      [2, "ENOENT"],
      [3, "ESRCH"],
      [4, "EINTR"],
      [7, "E2BIG"],
      [9, "EBADF"],
      [11, "EAGAIN"],
      [12, "ENOMEM"],
      [13, "EACCES"],
      [14, "EFAULT"],
      [16, "EBUSY"],
      [17, "EEXIST"],
      [19, "ENODEV"],
      [22, "EINVAL"],
      [28, "ENOSPC"],
      [38, "ENOSYS"],
      [95, "EOPNOTSUPP"],
      [524, "ENOTSUPP"]
    ],
    (x) -> first(x) == n
  )
  if row.nil?
    to_s(n)
  else
    row[1]
  end
end

@doc """
map_create_layout: `union bpf_attr` as BPF_MAP_CREATE reads it.

    width(map_create_layout) #=> 72
"""
def map_create_layout()
  layout(
    [
      %i[map_type u32],
      %i[key_size u32],
      %i[value_size u32],
      %i[max_entries u32],
      %i[map_flags u32],
      %i[inner_map_fd u32],
      %i[numa_node u32],
      [:map_name, [:text, 16]],
      %i[map_ifindex u32],
      %i[btf_fd u32],
      %i[btf_key_type_id u32],
      %i[btf_value_type_id u32],
      %i[btf_vmlinux_value_type_id u32],
      %i[map_extra u64]
    ]
  )
end

@doc """
map_elem_layout: `union bpf_attr` as the map element commands read it.

    width(map_elem_layout) #=> 32
"""
def map_elem_layout()
  layout([%i[map_fd u32], %i[key u64], %i[value u64], %i[flags u64]])
end

@doc """
prog_load_layout: `union bpf_attr` as BPF_PROG_LOAD reads it, through `prog_token_fd`.

    offset(prog_load_layout, :prog_name) #=> 48
    offset(prog_load_layout, :attach_btf_id) #=> 108
"""
def prog_load_layout()
  layout(
    [
      %i[prog_type u32],
      %i[insn_cnt u32],
      %i[insns u64],
      %i[license u64],
      %i[log_level u32],
      %i[log_size u32],
      %i[log_buf u64],
      %i[kern_version u32],
      %i[prog_flags u32],
      [:prog_name, [:text, 16]],
      %i[prog_ifindex u32],
      %i[expected_attach_type u32],
      %i[prog_btf_fd u32],
      %i[func_info_rec_size u32],
      %i[func_info u64],
      %i[func_info_cnt u32],
      %i[line_info_rec_size u32],
      %i[line_info u64],
      %i[line_info_cnt u32],
      %i[attach_btf_id u32],
      %i[attach_prog_fd u32],
      %i[core_relo_cnt u32],
      %i[fd_array u64],
      %i[core_relos u64],
      %i[core_relo_rec_size u32],
      %i[log_true_size u32],
      %i[prog_token_fd i32]
    ]
  )
end

@doc """
test_run_layout: `union bpf_attr` as BPF_PROG_RUN reads it.

    width(test_run_layout) #=> 80
"""
def test_run_layout()
  layout(
    [
      %i[prog_fd u32],
      %i[retval u32],
      %i[data_size_in u32],
      %i[data_size_out u32],
      %i[data_in u64],
      %i[data_out u64],
      %i[repeat u32],
      %i[duration u32],
      %i[ctx_size_in u32],
      %i[ctx_size_out u32],
      %i[ctx_in u64],
      %i[ctx_out u64],
      %i[flags u32],
      %i[cpu u32],
      %i[batch_size u32]
    ]
  )
end

@doc """
obj_layout: `union bpf_attr` as BPF_OBJ_PIN and BPF_OBJ_GET read it.

    width(obj_layout) #=> 24
"""
def obj_layout()
  layout(
    [%i[pathname u64], %i[bpf_fd u32], %i[file_flags u32], %i[path_fd i32]]
  )
end

@doc """
link_layout: `union bpf_attr` as BPF_LINK_CREATE reads it for most hooks.

    width(link_layout) #=> 48
"""
def link_layout()
  layout(
    [
      %i[prog_fd u32],
      %i[target_fd u32],
      %i[attach_type u32],
      %i[flags u32],
      %i[target_btf_id u32],
      %i[pad u32],
      %i[cookie u64],
      %i[spare u64],
      %i[spare2 u64]
    ]
  )
end

@doc """
kprobe_multi_layout: `union bpf_attr` as BPF_LINK_CREATE reads it for kprobe_multi.

    width(kprobe_multi_layout) #=> 48
"""
def kprobe_multi_layout()
  layout(
    [
      %i[prog_fd u32],
      %i[target_fd u32],
      %i[attach_type u32],
      %i[flags u32],
      %i[kprobe_flags u32],
      %i[cnt u32],
      %i[syms u64],
      %i[addrs u64],
      %i[cookies u64]
    ]
  )
end

@doc """
raw_tracepoint_layout: `union bpf_attr` as BPF_RAW_TRACEPOINT_OPEN reads it.

    width(raw_tracepoint_layout) #=> 24
"""
def raw_tracepoint_layout()
  layout([%i[name u64], %i[prog_fd u32], %i[pad u32], %i[cookie u64]])
end

@doc """
info_layout: `union bpf_attr` as BPF_OBJ_GET_INFO_BY_FD reads it.

    width(info_layout) #=> 16
"""
def info_layout()
  layout([%i[bpf_fd u32], %i[info_len u32], %i[info u64]])
end

@doc """
prog_info_layout: the front of `struct bpf_prog_info`, through its name.

    offset(prog_info_layout, :id) #=> 4
"""
def prog_info_layout()
  layout(
    [
      %i[type u32],
      %i[id u32],
      [:tag, [:bytes, 8]],
      %i[jited_prog_len u32],
      %i[xlated_prog_len u32],
      %i[jited_prog_insns u64],
      %i[xlated_prog_insns u64],
      %i[load_time u64],
      %i[created_by_uid u32],
      %i[nr_map_ids u32],
      %i[map_ids u64],
      [:name, [:text, 16]]
    ]
  )
end

@doc """
seam_kind: the width the seam writes a scalar kind at.

    seam_kind(:i32) #=> :u32
    seam_kind(:u64) #=> :u64
"""
def seam_kind(kind)
  if member?(kind, %i[u8 i8])
    :u8
  elsif member?(kind, %i[u16 i16])
    :u16
  elsif member?(kind, %i[u32 i32])
    :u32
  elsif member?(kind, %i[u64 i64])
    :u64
  else
    :bytes
  end
end

@doc """
field_slot: one record field as the seam's `[offset, kind, value]`.

    field_slot(layout([[:a, :u32]]), :a, 7) #=> [0, :u32, 7]
    field_slot(layout([[:a, :u64]]), :a, {out: 8}) #=> [0, :out, 8]
"""
def field_slot(l, name, value)
  f = field_of(l, name)
  at = f[:offset]
  if map?(value) and value[:in] != nil
    [at, :in, value[:in]]
  elsif map?(value) and value[:out] != nil
    [at, :out, value[:out]]
  elsif map?(value) and value[:inout] != nil
    [at, :inout, value[:inout]]
  elsif map?(value) and value[:fd] != nil
    [at, :fd, value[:fd]]
  elsif map?(value) and value[:strings] != nil
    [at, :strings, value[:strings]]
  elsif integer?(value)
    [at, seam_kind(f[:kind]), value]
  elsif string?(value)
    [at, :bytes, text_bytes(value)]
  elsif list?(value)
    [at, :bytes, value]
  else
    raise(
      :bad_option,
      "field #{to_s(name)} has no form the seam takes: #{to_s(value)}"
    )
  end
end

@doc """
struct_fields: a record over a layout as the seam's fields: an integer at its width, {in: bytes}, {out: capacity} and {inout: bytes} as a buffer's address, {strings: names} as an array of pointers to them, {fd: handle} as a descriptor. Absent fields stay zero.

    struct_fields(layout([[:a, :u32], [:b, :u64]]), [[:b, {out: 8}]]) #=> [[8, :out, 8]]
    struct_fields(layout([[:a, :u32]]), [[:a, 7]]) #=> [[0, :u32, 7]]
    struct_fields(layout([[:a, :u32]]), []) #=> []
"""
def struct_fields(l, pairs)
  map((p) -> field_slot(l, first(p), p[1]), pairs)
end

@doc """
refused_data: what a kernel refusal carries: the errno, its name, the log.

    refused_data({errno: 13}, "x").name #=> "EACCES"
"""
def refused_data(answer, log)
  {errno: answer[:errno], name: errno_name(answer[:errno]), log:}
end

@doc """
checked: an answer the kernel accepted, or the refusal for one it did not.

    checked({errno: nil, ret: 1}, "w").ret #=> 1
    (checked({errno: 13}, "w") rescue :refused) #=> :refused
"""
def checked(answer, what, log?)
  if answer[:errno].nil?
    answer
  else
    name = errno_name(answer[:errno])
    raise(
      :kernel_refused,
      "#{what}: #{name}",
      {data: refused_data(answer, log)}
    )
  end
end

@doc """
call_bpf: one `bpf(2)` command over a layout and a record.

    (call_bpf(:nope, map_elem_layout, [], false) rescue :refused) #=> :refused
"""
def call_bpf(command, l, pairs, fd_result)
  bpf_syscall(
    kind_id(:command, command),
    width(l),
    struct_fields(l, pairs),
    fd_result
  )
end

@doc """
create_map: a kernel map from a `bpf::declare_map` shape: the shape plus {fd:}. `{flags:}` in the shape sets `map_flags`.

    (create_map(bpf::declare_map(:m, :nope, 4, 8, 1)) rescue :refused) #=> :refused
"""
def create_map(spec)
  a = call_bpf(
    :map_create,
    map_create_layout,
    [
      [:map_type, kind_id(:map, spec[:kind])],
      [:key_size, spec[:key_size]],
      [:value_size, spec[:value_size]],
      [:max_entries, spec[:max_entries]],
      [:map_flags, spec[:flags] or 0],
      [:map_name, pack_name(spec[:name])]
    ],
    true
  )
  assoc(spec, :fd, checked(a, "create_map #{to_s(spec[:name])}")[:fd])
end

@doc """
pack_name: an object name as the kernel takes it: at most 15 of the letters, digits, `_` and `.` it allows, the rest changed to `_`.

    pack_name(:counts) #=> [99, 111, 117, 110, 116, 115]
    size(pack_name("abcdefghijklmnopqrstuvwxyz")) #=> 15
    pack_name("a-b") #=> [97, 95, 98]
"""
def pack_name(name)
  allowed = text_bytes("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
  map(
    fn(b)
      if member?(b, allowed)
        b
      else
        95
      end
    end,
    take(15, text_bytes(to_s(name)))
  )
end

@doc """
map_put: a key's value set in a kernel map, both as bytes. `flags` 1 refuses an existing key and 2 a missing one.

    (map_put({}, [], []) rescue :refused) #=> :refused
"""
def map_put(m, key, value, flags?)
  a = call_bpf(
    :map_update_elem,
    map_elem_layout,
    [
      [:map_fd, {fd: m[:fd]}],
      [:key, {in: key}],
      [:value, {in: value}],
      [:flags, flags or 0]
    ],
    false
  )
  checked(a, "map_put")
  nil
end

@doc """
map_get: a key's value bytes in a kernel map, nil when the map holds none. A per-CPU map answers one value per possible CPU, joined, and `{value_bytes:}` sizes the buffer.

    (map_get({}, []) rescue :refused) #=> :refused
"""
def map_get(m, key)
  a = call_bpf(
    :map_lookup_elem,
    map_elem_layout,
    [
      [:map_fd, {fd: m[:fd]}],
      [:key, {in: key}],
      [:value, {out: m[:value_bytes] or m[:value_size]}]
    ],
    false
  )
  if a[:errno] == 2
    nil
  else
    first(checked(a, "map_get")[:out])
  end
end

@doc """
map_delete: a key taken out of a kernel map: true when it was there, false when it was not.

    (map_delete({}, []) rescue :refused) #=> :refused
"""
def map_delete(m, key)
  a = call_bpf(
    :map_delete_elem,
    map_elem_layout,
    [[:map_fd, {fd: m[:fd]}], [:key, {in: key}]],
    false
  )
  if a[:errno] == 2
    false
  else
    checked(a, "map_delete")
    true
  end
end

@doc """
next_key: the key after this one in a kernel map, nil past the last.

    (next_key({}, nil) rescue :refused) #=> :refused
"""
def next_key(m, key)
  fields = if key.nil?
    [[:map_fd, {fd: m[:fd]}], [:value, {out: m[:key_size]}]]
  else
    [[:map_fd, {fd: m[:fd]}], [:key, {in: key}], [:value, {out: m[:key_size]}]]
  end
  a = call_bpf(:map_get_next_key, map_elem_layout, fields, false)
  if a[:errno] == 2
    nil
  else
    first(checked(a, "map_keys")[:out])
  end
end

@doc """
map_keys: every key a kernel map holds, as bytes, in the kernel's order.

    (map_keys({}) rescue :refused) #=> :refused
"""
def map_keys(m)
  acc = {keys: [], at: next_key(m, nil)}
  while(
    not acc[:at].nil?,
    set!(acc, {keys: append(acc[:keys], [acc[:at]]), at: next_key(m, acc[:at])})
  )
  acc[:keys]
end

@doc """
fields_bound: a program with its kernel fields bound from BTF, refused when it reads some and has no table.

    fields_bound({fields: []}, nil)[:fields] #=> []
    (fields_bound({fields: [{}]}, nil) rescue :refused) #=> :refused
"""
def fields_bound(program, table)
  if program[:fields] == [] or program[:fields].nil?
    program
  else
    if table.nil?
      raise(
        :bad_option,
        "this program reads kernel fields: give install {btf: btf::open(btf::vmlinux_path)}"
      )
    end
    bind_fields(program, (s, path) -> btf::field(table, s, path))
  end
end

@doc """
patched: a program's instructions with each map reference holding its descriptor's number.

    size(patched({relocs: [], insns: [bpf::exit_program]}, [])) #=> 1
"""
def patched(program, maps)
  by_slot = reduce(
    fn(acc, reloc)
      m = find(maps, (x) -> x[:name] == reloc[:map])
      if m.nil?
        raise(
          :bad_option,
          "the program names the map #{to_s(reloc[:map])}, which is not given"
        )
      end
      assoc(acc, reloc[:at], fd_number(m[:fd]))
    end,
    {},
    program[:relocs]
  )
  placed = reduce(
    fn(acc, i)
      fd = get(by_slot, acc[:at])
      fixed = if fd.nil?
        i
      else
        assoc(i, :imm, fd)
      end
      {at: acc[:at] + slot_count(i), insns: append(acc[:insns], [fixed])}
    end,
    {at: 0, insns: []},
    program[:insns]
  )
  placed[:insns]
end

@doc """
slot_count: the slots an instruction takes.

    slot_count({imm2: 0}) #=> 2
    slot_count({}) #=> 1
"""
def slot_count(i)
  if i[:imm2].nil?
    1
  else
    2
  end
end

@doc """
load_fields: BPF_PROG_LOAD's record for a program's bytes.

    first(load_fields(:xdp, [], {}, 0)) #=> [:prog_type, 6]
"""
def load_fields(kind, encoded, opts, log)
  base = [
    [:prog_type, kind_id(:prog, kind)],
    [:insn_cnt, floor(length(encoded) / 8)],
    [:insns, {in: encoded}],
    [:license, {in: append(text_bytes(opts[:license] or "GPL"), [0])}],
    [:prog_name, pack_name(opts[:name] or "blue")]
  ]
  attach = if opts[:attach].nil?
    []
  else
    [[:expected_attach_type, kind_id(:attach, opts[:attach])]]
  end
  btf = if opts[:attach_btf_id].nil?
    []
  else
    [[:attach_btf_id, opts[:attach_btf_id]]]
  end
  logging = if log == 0
    []
  else
    [[:log_level, 1], [:log_size, log], [:log_buf, {out: log}]]
  end
  append(*[base, attach, btf, logging])
end

@doc """
log_text: the verifier's log from an answer, empty when there is none.

    log_text({out: [[97, 0]]}) #=> "a"
    log_text({out: []}) #=> ""
"""
def log_text(answer)
  buffers = answer[:out]
  if buffers == [] or buffers.nil?
    ""
  else
    bytes_text(take_until_nul(first(buffers))) or ""
  end
end

@doc """
take_until_nul: bytes up to the first NUL.

    take_until_nul([97, 0, 98]) #=> [97]
"""
def take_until_nul(bytes)
  take_while((b) -> b != 0, bytes)
end

@doc """
load_attempt: one BPF_PROG_LOAD, with a log of this many bytes.

    (load_attempt(:nope, [], {}, 0) rescue :refused) #=> :refused
"""
def load_attempt(kind, encoded, opts, log)
  call_bpf(
    :prog_load,
    prog_load_layout,
    load_fields(kind, encoded, opts, log),
    true
  )
end

@doc """
load: an assembled program into the kernel: {fd:, kind:, maps:, name:}. `opts` takes {kind:, maps:, name:, license:, attach:, attach_btf_id:}, `kind` a program type such as :xdp, `maps` what `create_map` made. The verifier runs here, and its log is in the refusal's data.

    (load(bpf::assemble([]), {kind: :nope}) rescue :refused) #=> :refused
"""
def load(program, opts)
  maps = opts[:maps] or []
  encoded = flat_map(patched(program, maps), encode_insn)
  first_try = load_attempt(opts[:kind], encoded, opts, 0)
  a = if first_try[:errno] == 11
    load_attempt(opts[:kind], encoded, opts, 0)
  else
    first_try
  end
  if a[:errno].nil?
    {fd: a[:fd], kind: opts[:kind], maps:, name: opts[:name]}
  else
    logged = load_attempt(opts[:kind], encoded, opts, 262_144)
    checked(logged, "load #{to_s(opts[:name])}", log_text(logged))
    {fd: logged[:fd], kind: opts[:kind], maps:, name: opts[:name]}
  end
end

@doc """
install: a compiled program into the kernel: its maps created, then the program loaded against them. {prog:, maps:}, each map by its place in `compile`'s list and findable by `map_named`. `opts` adds {attach:, attach_btf_id:} for the hooks that name their target at load.

    (install({maps: [bpf::declare_map(:m, :nope, 4, 8, 1)]}) rescue :refused) #=> :refused
"""
def install(compiled, opts?)
  maps = map(create_map, compiled[:maps] or [])
  given = opts or {}
  prog = load(
    fields_bound(compiled, given[:btf]),
    {
      kind: compiled[:kind],
      maps:,
      name: compiled[:name],
      attach: given[:attach],
      attach_btf_id: given[:attach_btf_id]
    }
  )
  {prog:, maps:}
end

@doc """
hook_of: the attach type and BTF id a hook's spec names.

    hook_of(btf::read(btf::sample), {fentry: "run"}).id #=> 5
    (hook_of(btf::read(btf::sample), {}) rescue :refused) #=> :refused
"""
def hook_of(table, spec)
  if spec[:fentry] != nil
    {kind: :trace_fentry, id: btf::function_id(table, spec[:fentry])}
  elsif spec[:fexit] != nil
    {kind: :trace_fexit, id: btf::function_id(table, spec[:fexit])}
  elsif spec[:lsm] != nil
    {kind: :lsm_mac, id: btf::function_id(table, "bpf_lsm_#{spec[:lsm]}")}
  else
    raise(:bad_option, "a hook is {fentry:}, {fexit:} or {lsm:}")
  end
end

@doc """
install_hook: a compiled :tracing or :lsm program loaded onto a kernel function and attached: `spec` {fentry: name}, {fexit: name} or {lsm: hook}, the target found in `table`, this kernel's BTF. {prog:, maps:, link:}. The attachment needs no netlink and no perf event.

    hook_of(btf::read(btf::sample), {fentry: "run"}).id #=> 5
    hook_of(btf::read(btf::sample), {fentry: "run"}).kind #=> :trace_fentry
    (install_hook({}, btf::read(btf::sample), {}) rescue :refused) #=> :refused
"""
def install_hook(compiled, table, spec)
  hook = hook_of(table, spec)
  live = install(
    compiled,
    {btf: table, attach: hook[:kind], attach_btf_id: hook[:id]}
  )
  assoc(live, :link, attach(live[:prog], hook[:kind]))
end

@doc """
map_named: the map of this name among those `install` made.

    map_named({maps: [{name: :a}]}, :a) #=> {name: :a}
"""
def map_named(installed, name)
  found = find(installed[:maps], (m) -> m[:name] == name)
  if found.nil?
    raise(:bad_option, "no map #{to_s(name)}")
  end
  found
end

@doc """
run: a loaded program once through BPF_PROG_RUN, attached to nothing: {ret:, packet:, ctx:, duration_ns:}. `input` takes {packet:, ctx:, repeat:}, each packet at least 14 bytes for XDP.

    (run({}, {}) rescue :refused) #=> :refused
"""
def run(p, input)
  packet = input[:packet] or []
  ctx = input[:ctx] or []
  room = length(packet) + 256
  fields = append(
    *[
      [[:prog_fd, {fd: p[:fd]}]],
      if packet == []
        []
      else
        [
          [:data_size_in, length(packet)],
          [:data_size_out, room],
          [:data_in, {in: packet}],
          [:data_out, {out: room}]
        ]
      end,
      if ctx == []
        []
      else
        [
          [:ctx_size_in, length(ctx)],
          [:ctx_size_out, length(ctx)],
          [:ctx_in, {in: ctx}],
          [:ctx_out, {out: length(ctx)}]
        ]
      end,
      if input[:repeat].nil?
        []
      else
        [[:repeat, input[:repeat]]]
      end
    ]
  )
  a = checked(
    call_bpf(:prog_test_run, test_run_layout, fields, false),
    "run #{to_s(p[:name])}"
  )
  back = unpack(test_run_layout, a[:attr])
  {
    ret: back[:retval],
    packet: if packet == []
      []
    else
      take(back[:data_size_out], first(a[:out]))
    end,
    ctx: if ctx == []
      []
    else
      last(a[:out])
    end,
    duration_ns: back[:duration]
  }
end

@doc """
prog_id: the kernel's id of a loaded program, what `bpftool prog show id` names.

    (prog_id({}) rescue :refused) #=> :refused
"""
def prog_id(p)
  count = width(prog_info_layout)
  a = checked(
    call_bpf(
      :obj_get_info_by_fd,
      info_layout,
      [[:bpf_fd, {fd: p[:fd]}], [:info_len, count], [:info, {out: count}]],
      false
    ),
    "prog_id"
  )
  unpack(prog_info_layout, first(a[:out]))[:id]
end

@doc """
pin: a map, program or link at a path under a bpffs, where it outlives this process until the file is removed.

    (pin({}, "/no/such/pin") rescue :refused) #=> :refused
"""
def pin(object, path)
  a = call_bpf(
    :obj_pin,
    obj_layout,
    [
      [:pathname, {in: append(text_bytes(path), [0])}],
      [:bpf_fd, {fd: object[:fd]}]
    ],
    false
  )
  checked(a, "pin #{path}")
  path
end

@doc """
open_pinned: a descriptor for what a bpffs path holds.

    (open_pinned("/no/such/pin") rescue :refused) #=> :refused
"""
def open_pinned(path)
  a = call_bpf(
    :obj_get,
    obj_layout,
    [[:pathname, {in: append(text_bytes(path), [0])}]],
    true
  )
  {fd: checked(a, "open_pinned #{path}")[:fd]}
end

@doc """
attach: a loaded program to a hook through BPF_LINK_CREATE: `kind` an attach type such as :xdp or :tcx_ingress, `target` an interface index or a descriptor's holder, `opts` {flags:, target_btf_id:, cookie:}. The answer is {fd:, kind:}, and the attachment lives as long as that descriptor or its pin.

    (attach({}, :nope) rescue :refused) #=> :refused
"""
def attach(p, kind, target?, opts?)
  o = opts or {}
  target_field = if target.nil?
    []
  elsif integer?(target)
    [[:target_fd, target]]
  else
    [[:target_fd, {fd: target[:fd]}]]
  end
  extras = append(
    *[
      if o[:flags].nil?
        []
      else
        [[:flags, o[:flags]]]
      end,
      if o[:target_btf_id].nil?
        []
      else
        [[:target_btf_id, o[:target_btf_id]]]
      end,
      if o[:cookie].nil?
        []
      else
        [[:cookie, o[:cookie]]]
      end
    ]
  )
  a = call_bpf(
    :link_create,
    link_layout,
    append(
      *[
        [[:prog_fd, {fd: p[:fd]}], [:attach_type, kind_id(:attach, kind)]],
        target_field,
        extras
      ]
    ),
    true
  )
  {fd: checked(a, "attach #{to_s(kind)}")[:fd], kind:}
end

@doc """
attach_kprobes: a kprobe program to kernel functions by name through one kprobe_multi link, on their return when `retprobe` is true. The program loads with {attach: :trace_kprobe_multi}, and a kernel without FPROBE answers EOPNOTSUPP.

    (attach_kprobes({}, []) rescue :refused) #=> :refused
"""
def attach_kprobes(p, symbols, retprobe?)
  flags = if retprobe == true
    1
  else
    0
  end
  a = call_bpf(
    :link_create,
    kprobe_multi_layout,
    [
      [:prog_fd, {fd: p[:fd]}],
      [:attach_type, kind_id(:attach, :trace_kprobe_multi)],
      [:kprobe_flags, flags],
      [:cnt, size(symbols)],
      [:syms, {strings: symbols}]
    ],
    true
  )
  {fd: checked(a, "attach_kprobes")[:fd], kind: :trace_kprobe_multi}
end

@doc """
perf_attr_layout: the front of `struct perf_event_attr`, through `config2`.

    width(perf_attr_layout) #=> 72
    offset(perf_attr_layout, :config1) #=> 56
"""
def perf_attr_layout()
  layout(
    [
      %i[type u32],
      %i[size u32],
      %i[config u64],
      %i[sample_period u64],
      %i[sample_type u64],
      %i[read_format u64],
      %i[flags u64],
      %i[wakeup_events u32],
      %i[bp_type u32],
      %i[config1 u64],
      %i[config2 u64]
    ]
  )
end

@doc """
tracepoint_id: a kernel tracepoint's number from tracefs, what perf_event_open takes.

    (tracepoint_id("no_such", "tracepoint") rescue :refused) #=> :refused
"""
def tracepoint_id(category, name)
  to_int(trim(read_file("/sys/kernel/tracing/events/#{category}/#{name}/id")))
end

@doc """
attach_tracepoint: a tracepoint program to `category/name`, through one perf event and a link on it. A tracepoint program runs for the whole system whichever CPU its event names, and a second event for the same program is refused with EEXIST. `detach` ends both.

    (attach_tracepoint({}, "no_such", "tracepoint") rescue :refused) #=> :refused
"""
def attach_tracepoint(p, category, name)
  fields = [
    [:type, 2],
    [:size, width(perf_attr_layout)],
    [:config, tracepoint_id(category, name)],
    [:sample_period, 1],
    [:wakeup_events, 1]
  ]
  attach_event(p, fields)
end

@doc """
attach_event: a program linked to a new perf event, the event kept for `detach`.

    (attach_event({}, [[:nope, 1]]) rescue :refused) #=> :refused
"""
def attach_event(p, fields)
  event = perf_event_open(
    width(perf_attr_layout),
    struct_fields(perf_attr_layout, fields),
    -1,
    0,
    nil,
    8
  )
  link = attach(p, :perf_event, {fd: event})
  assoc(link, :event, event)
end

@doc """
pmu_type: a perf event source's type number, from sysfs.

    (pmu_type("no_such_pmu") rescue :refused) #=> :refused
"""
def pmu_type(pmu)
  to_int(trim(read_file("/sys/bus/event_source/devices/#{pmu}/type")))
end

@doc """
retprobe_bit: the `config` bit a kprobe or uprobe PMU reads as "on return", from its format text.

    retprobe_bit("config:0") #=> 1
    retprobe_bit("config:3") #=> 8
"""
def retprobe_bit(format)
  shift_left(1, to_int(last(split(trim(format), ":"))))
end

@doc """
attach_kprobe: a kprobe program to one kernel function by name, on its return when `retprobe` is true, through a perf event and a link. It needs no FPROBE, which `attach_kprobes` does, and a NixOS 25.11 kernel leaves FPROBE off.

    (attach_kprobe({}, "no_such_function") rescue :refused) #=> :refused
"""
def attach_kprobe(p, symbol, retprobe?)
  config = if retprobe == true
    retprobe_bit(
      read_file("/sys/bus/event_source/devices/kprobe/format/retprobe")
    )
  else
    0
  end
  attach_event(
    p,
    [
      [:type, pmu_type("kprobe")],
      [:size, width(perf_attr_layout)],
      [:config, config],
      [:config1, {in: append(text_bytes(symbol), [0])}],
      [:sample_period, 1],
      [:wakeup_events, 1]
    ]
  )
end

@doc """
attach_raw_tracepoint: a raw tracepoint or BTF-enabled program by its tracepoint's name; for an fentry, fexit or LSM program the name is nil and the kernel takes the target from the program's BTF id.

    (attach_raw_tracepoint({}) rescue :refused) #=> :refused
"""
def attach_raw_tracepoint(p, name?)
  fields = if name.nil?
    [[:prog_fd, {fd: p[:fd]}]]
  else
    [[:name, {in: append(text_bytes(name), [0])}], [:prog_fd, {fd: p[:fd]}]]
  end
  a = call_bpf(:raw_tracepoint_open, raw_tracepoint_layout, fields, true)
  {fd: checked(a, "attach_raw_tracepoint")[:fd], kind: :raw_tracepoint}
end

@doc """
detach: an attachment ended, by closing its descriptors.

    (detach({}) rescue :refused) #=> :refused
"""
def detach(link)
  fd_close(link[:fd])
  if link[:event] != nil
    fd_close(link[:event])
  end
  nil
end

@doc """
close_object: a map or program's descriptor closed now, rather than when its last reference goes.

    (close_object({}) rescue :refused) #=> :refused
"""
def close_object(object)
  fd_close(object[:fd])
  nil
end

@doc """
open_events: a consumer of a ring buffer map, whose `max_entries` is its size in bytes.

    (open_events({}) rescue :refused) #=> :refused
"""
def open_events(m)
  ringbuf_open(m[:fd], m[:max_entries])
end

@doc """
next_event: the next record's bytes from `open_events`, waiting at most `timeout_ms`; nil when none came.

    (next_event(nil, 0) rescue :refused) #=> :refused
"""
def next_event(ring, timeout_ms)
  ringbuf_next(ring, timeout_ms)
end

@doc """
drain: every record a consumer has now, oldest first.

    (drain(nil) rescue :refused) #=> :refused
"""
def drain(ring)
  acc = {events: [], at: ringbuf_next(ring, 0)}
  while(
    not acc[:at].nil?,
    set!(
      acc,
      {events: append(acc[:events], [acc[:at]]), at: ringbuf_next(ring, 0)}
    )
  )
  acc[:events]
end

@doc """
kernel_release: the running kernel's release, from procfs.

    string?(kernel_release rescue "none") #=> true
"""
def kernel_release()
  trim(read_file("/proc/sys/kernel/osrelease"))
end

test "the layouts place every field where the UAPI header does, counted by hand from bpf.h"
  assert offset(prog_load_layout, :prog_type) == 0
  assert offset(prog_load_layout, :insns) == 8
  assert offset(prog_load_layout, :license) == 16
  assert offset(prog_load_layout, :log_buf) == 32
  assert offset(prog_load_layout, :prog_name) == 48
  assert offset(prog_load_layout, :expected_attach_type) == 68
  assert offset(prog_load_layout, :attach_btf_id) == 108
  assert offset(prog_load_layout, :fd_array) == 120
  assert offset(prog_load_layout, :prog_token_fd) == 144
  assert offset(map_create_layout, :map_name) == 28
  assert offset(map_create_layout, :map_extra) == 64
  assert offset(map_elem_layout, :key) == 8
  assert offset(map_elem_layout, :flags) == 24
  assert offset(test_run_layout, :data_in) == 16
  assert offset(test_run_layout, :duration) == 36
  assert offset(test_run_layout, :ctx_in) == 48
  assert offset(test_run_layout, :flags) == 64
  assert offset(link_layout, :target_btf_id) == 16
  assert offset(link_layout, :cookie) == 24
end

test "the tables hold the kernel's numbers, each read off bpf.h"
  assert kind_id(:command, :map_create) == 0
  assert kind_id(:command, :token_create) == 36
  assert kind_id(:map, :arena) == 33
  assert kind_id(:prog, :netfilter) == 32
  assert kind_id(:prog, :lsm) == 29
  assert kind_id(:attach, :tcx_ingress) == 46
  assert kind_id(:attach, :trace_uprobe_session) == 57
end

test "a field the seam cannot take is refused by name, and an empty record is no fields"
  l = layout([%i[a u32]])
  assert struct_fields(l, []) == []
  assert (struct_fields(l, [[:a, nil]]) rescue :refused) == :refused
  assert (struct_fields(l, [[:b, 1]]) rescue :refused) == :refused
end

test "a name the kernel would refuse is made one it takes"
  assert pack_name("a b") == [97, 95, 98]
  assert size(pack_name("abcdefghijklmnopqrst")) == 15
  assert pack_name("") == []
end

test "off Linux the kernel words raise a named absence, on Linux a closed table name still refuses first"
  assert (kind_id(:command, :nope) rescue :refused) == :refused
end
