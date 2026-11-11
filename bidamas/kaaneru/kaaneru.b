@moduledoc """
kaaneru (カーネル) — the Linux kernel, spoken from blue: maps, programs, links and ring buffers over `bpf(2)`, with every struct a `baito` layout and no C library in the path.

The kernel family is one tree: `kaaneru::bpf` builds programs and runs them on a pure machine anywhere, `kaaneru::btf` reads and writes the type format, and `kaaneru::erufu` writes ELF objects; this root loads them into the kernel on Linux. `attached` loads a compiled program onto one of the `hooks`, runs a function while it is there, and takes it away whatever the function does. Each attach kind also has its word: `attach` for XDP, tcx and what names a descriptor, `attach_cgroup`, `attach_netfilter`, `attach_uprobes`, `attach_kprobes`, `attach_kprobe`, `attach_tracepoint`, `attach_raw_tracepoint`, `attach_sampling`, `install_hook` for fentry, fexit, fmod_ret, LSM and iterators, `install_struct_ops`. Off Linux each call raises :unsupported. A kernel refusal raises :kernel_refused with data {errno:, name:, log:}, the verifier's log included.

The words need the `kernel_bpf` capability, which holds the kernel: grant it to what would otherwise run as root. The pure words here (the layouts, `kind_id`, `errno_name`, `struct_fields`) need nothing.

    errno_name(13) #=> "EACCES"
    kind_id(:prog, :xdp) #=> 6
    width(prog_load_layout) #=> 152
"""

use("baito", %i[bytes_int field_of int_bytes layout offset unpack width])

use(
  "kaaneru/bpf",
  %i[alu assemble bind_fields encode_insn exit_program map_kinds]
)

use("kaaneru/btf")
use("retsu", %i[first flat_map index_of last repeat size take_while])

legacy_names("0.1.0", [%w[map_kinds kaaneru::bpf::map_kinds]])

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
  if at < 0
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
sleepable: `BPF_F_SLEEPABLE`, which a :syscall program must load with.

    sleepable #=> 16
"""
def sleepable()
  16
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
      [:name, [:text, 16]],
      %i[ifindex u32],
      %i[gpl_compatible u32],
      %i[netns_dev u64],
      %i[netns_ino u64],
      %i[nr_jited_ksyms u32],
      %i[nr_jited_func_lens u32],
      %i[jited_ksyms u64],
      %i[jited_func_lens u64],
      %i[btf_id u32],
      %i[func_info_rec_size u32],
      %i[func_info u64],
      %i[nr_func_info u32],
      %i[nr_line_info u32],
      %i[line_info u64],
      %i[jited_line_info u64],
      %i[nr_jited_line_info u32],
      %i[line_info_rec_size u32],
      %i[jited_line_info_rec_size u32]
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
btf_load_layout: `union bpf_attr` as BPF_BTF_LOAD reads it.

    width(btf_load_layout) #=> 40
    offset(btf_load_layout, :btf_size) #=> 16
"""
def btf_load_layout()
  layout(
    [
      %i[btf u64],
      %i[btf_log_buf u64],
      %i[btf_size u32],
      %i[btf_log_size u32],
      %i[btf_log_level u32],
      %i[btf_log_true_size u32],
      %i[btf_flags u32],
      %i[btf_token_fd i32]
    ]
  )
end

@doc """
load_btf: a BTF blob into the kernel: {fd:}, what `create_map` names as `{btf_object:}`. Its checker runs here; a refusal names why, the checker's log in its data.

    (load_btf([1, 2, 3], 0) rescue :other) != nil #=> true
"""
def load_btf(bytes, log?)
  size_of_log = log or 262_144
  logging = if size_of_log == 0
    []
  else
    [
      [:btf_log_buf, {out: size_of_log}],
      [:btf_log_size, size_of_log],
      [:btf_log_level, 1]
    ]
  end
  a = call_bpf(
    :btf_load,
    btf_load_layout,
    append([[:btf, {in: bytes}], [:btf_size, length(bytes)]], logging),
    true
  )
  {fd: checked(a, "load_btf", log_text(a))[:fd]}
end

@doc """
create_map: a kernel map from a `kaaneru::bpf::declare_map` shape: the shape plus {fd:}. `{flags:}` in the shape sets `map_flags`, and `{value_type_id:, btf_object:}` name the kernel's type a :struct_ops map holds and the BTF object `load_btf` made for it.

    (create_map(kaaneru::bpf::declare_map(:m, :nope, 4, 8, 1)) rescue :refused) #=> :refused
"""
def create_map(spec)
  a = call_bpf(
    :map_create,
    map_create_layout,
    append(
      [
        [:map_type, kind_id(:map, spec[:kind])],
        [:key_size, spec[:key_size]],
        [:value_size, spec[:value_size]],
        [:max_entries, spec[:max_entries]],
        [:map_flags, spec[:flags] or 0],
        [:map_name, pack_name(spec[:name])],
        [:btf_vmlinux_value_type_id, spec[:value_type_id] or 0]
      ],
      map_btf_fields(spec)
    ),
    true
  )
  assoc(spec, :fd, checked(a, "create_map #{to_s(spec[:name])}")[:fd])
end

@doc """
map_btf_fields: the fields that tie a map to its types: `{btf_fd:, btf_key:, btf_value:}` in the shape, or the BTF object a struct_ops map names.

    map_btf_fields({}) #=> [[:btf_fd, 0]]
    map_btf_fields({btf_object: 7}) #=> [[:btf_fd, 7]]
    size(map_btf_fields({btf_fd: 3, btf_key: 1, btf_value: 2})) #=> 3
"""
def map_btf_fields(spec)
  if spec[:btf_fd].nil?
    [[:btf_fd, spec[:btf_object] or 0]]
  else
    [
      [:btf_fd, {fd: spec[:btf_fd]}],
      [:btf_key_type_id, spec[:btf_key]],
      [:btf_value_type_id, spec[:btf_value]]
    ]
  end
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
        "this program reads kernel fields: give install {btf: kaaneru::btf::open(kaaneru::btf::vmlinux_path)}"
      )
    end
    bind_fields(program, (s, path) -> kaaneru::btf::field(table, s, path))
  end
end

@doc """
patched: a program's instructions with each map reference holding its descriptor's number.

    size(patched({relocs: [], insns: [exit_program]}, [])) #=> 1
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
    last(load_fields(:syscall, [], {}, 0)) #=> [:prog_flags, 16]
    last(load_fields(:struct_ops, [], {attach: 3}, 0)) #=> [:expected_attach_type, 3]
"""
def load_fields(kind, encoded, opts, log)
  base = [
    [:prog_type, kind_id(:prog, kind)],
    [:insn_cnt, floor(length(encoded) / 8)],
    [:insns, {in: encoded}],
    [:license, {in: append(text_bytes(opts[:license] or "GPL"), [0])}],
    [:prog_name, pack_name(opts[:name] or "blue")]
  ]
  wanted = opts[:attach] or only_attach(kind)
  attach = if wanted.nil?
    []
  else
    [[:expected_attach_type, attach_number(wanted)]]
  end
  btf = if opts[:attach_btf_id].nil?
    []
  else
    [[:attach_btf_id, opts[:attach_btf_id]]]
  end
  types = if opts[:btf_fd].nil?
    []
  else
    append(
      func_info_fields(opts[:btf_fd], opts[:func_info] or []),
      line_info_fields(opts[:line_info] or [])
    )
  end
  logging = if log == 0
    []
  else
    [[:log_level, 1], [:log_size, log], [:log_buf, {out: log}]]
  end
  flags = if kind == :syscall
    [[:prog_flags, sleepable]]
  else
    []
  end
  append(*[base, btf, types, logging, attach, flags])
end

@doc """
only_attach: the attach type a program kind must name at load because the kernel allows it no other, nil for a kind that names none or several.

    only_attach(:netfilter) #=> :netfilter
    only_attach(:sk_lookup) #=> :sk_lookup
    only_attach(:xdp).nil? #=> true
"""
def only_attach(kind)
  if member?(kind, %i[netfilter sk_lookup])
    kind
  end
end

@doc """
attach_number: what `expected_attach_type` holds: an attach type's number, or a :struct_ops program's member index as given.

    attach_number(:xdp) #=> 37
    attach_number(3) #=> 3
"""
def attach_number(attach)
  if integer?(attach)
    attach
  else
    kind_id(:attach, attach)
  end
end

@doc """
func_info_fields: the fields that tie a program to its BTF: each function by its slot and type.

    size(func_info_fields(3, [{at: 0, type: 2}])) #=> 4
    func_info_fields(3, [{at: 0, type: 2}])[3] #=> [:func_info_cnt, 1]
"""
def func_info_fields(btf_fd, rows)
  [
    [:prog_btf_fd, {fd: btf_fd}],
    [:func_info_rec_size, 8],
    [
      :func_info,
      {
        in: flat_map(
          rows,
          (f) -> append(int_bytes(f[:at], 4), int_bytes(f[:type], 4))
        )
      }
    ],
    [:func_info_cnt, size(rows)]
  ]
end

@doc """
line_info_fields: the fields that give a loaded program its source lines: each row by its slot and its strings' offsets in the program's BTF. No rows, no fields.

    line_info_fields([]) #=> []
    line_info_fields([{at: 0, file: 1, text: 2, pos: 2051}])[2] #=> [:line_info_cnt, 1]
"""
def line_info_fields(rows)
  if rows == []
    []
  else
    [
      [:line_info_rec_size, 16],
      [
        :line_info,
        {
          in: flat_map(
            rows,
            fn(r)
              append(
                *[
                  int_bytes(r[:at], 4),
                  int_bytes(r[:file], 4),
                  int_bytes(r[:text], 4),
                  int_bytes(r[:pos], 4)
                ]
              )
            end
          )
        }
      ],
      [:line_info_cnt, size(rows)]
    ]
  end
end

@doc """
insn_line?: whether a verifier log line is one instruction, `12: (bf) r1 = r2`.

    insn_line?("12: (bf) r1 = r2") #=> true
    insn_line?("12: R1=ctx()") #=> false
    insn_line?("; x = 1 @ f.b:3") #=> false
"""
def insn_line?(row)
  parts = split(row, ": (")
  size(parts) > 1 and to_int(first(parts)) != nil
end

@doc """
verifier_said: what a verifier log says of its refusal: {insn:, reason:}, `insn` the slot it last read, nil when it read none, and `reason` the lines after it, without the source lines and tallies around them. The kernel keeps only the failing path in the log, so the last instruction is the one refused.

    verifier_said("0: (b7) r0 = 0\n1: (95) exit\nR0 is bad\nprocessed 2 insns\n") #=> {insn: 1, reason: "R0 is bad"}
    verifier_said("") #=> {insn: nil, reason: ""}
    verifier_said("BPF program is too large.\n")[:reason] #=> "BPF program is too large."
"""
def verifier_said(log)
  rows = filter((r) -> trim(r) != "", split(log, line_break))
  at = reduce(
    fn(acc, pair)
      if insn_line?(pair[1])
        first(pair)
      else
        acc
      end
    end,
    nil,
    retsu::zip(range(0, size(rows)), rows)
  )
  told = if at.nil?
    rows
  else
    drop(at + 1, rows)
  end
  said = retsu::reject(
    fn(r)
      starts_with?(r, "processed ") or
        starts_with?(r, "; ") or
        starts_with?(r, "verification time")
    end,
    told
  )
  {
    insn: if at != nil
      to_int(first(split(rows[at], ":")))
    end,
    reason: join(said, "; ")
  }
end

@doc """
source_words: a refusal's place as a message reads it: `file:line:col`, or the slot when no source is known.

    source_words({file: "f.b", line: 3, col: 5}, 9) #=> "f.b:3:5"
    source_words(nil, 9) #=> "instruction 9"
    source_words(nil, nil) #=> "the program"
"""
def source_words(at, insn)
  if at != nil
    "#{at[:file]}:#{to_s(at[:line])}:#{to_s(at[:col])}"
  elsif insn != nil
    "instruction #{to_s(insn)}"
  else
    "the program"
  end
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
load: an assembled program into the kernel: {fd:, kind:, maps:, name:}. `opts` takes {kind:, maps:, name:, license:, attach:, attach_btf_id:, btf_fd:, func_info:, signed_division:}, `kind` a program type such as :xdp, `maps` what `create_map` made, `btf_fd` what `load_btf` made. The verifier runs here, and its log is in the refusal's data. Below 6.12 it first refuses a signed division that can reach the CPU's divide (`division_refusal`); `signed_division: :trust` turns that off for a program whose author has ruled out the lowest value by -1.

    (load(assemble([]), {kind: :nope}) rescue :refused) #=> :refused
"""
def load(program, opts)
  maps = opts[:maps] or []
  insns = patched(program, maps)
  refuse_division(insns, opts[:signed_division] or :refuse)
  encoded = flat_map(insns, encode_insn)
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
    if logged[:errno] != nil
      refused_load(logged, opts[:name], program)
    end
    {fd: logged[:fd], kind: opts[:kind], maps:, name: opts[:name]}
  end
end

@doc """
refused_load: the refusal for a load the verifier turned down: the blue line and the reason in its message, and {insn:, reason:, at:} with the log in its data. `at` is {file:, line:, col:, text:}, nil for a program that knows no lines.

    (refused_load({errno: 13, out: []}, "p", {lines: [], funcs: []}) rescue :refused) #=> :refused
"""
def refused_load(answer, name, program)
  log = log_text(answer)
  said = verifier_said(log)
  at = if said[:insn] != nil
    kaaneru::bpf::source_at(program, said[:insn])
  end
  raise(
    :kernel_refused,
    "load #{to_s(name)}: #{errno_name(answer[:errno])} at #{source_words(at, said[:insn])}: #{said[:reason]}",
    {
      data: assoc(
        assoc(
          assoc(refused_data(answer, log), :insn, said[:insn]),
          :reason,
          said[:reason]
        ),
        :at,
        at
      )
    }
  )
end

@doc """
install: a compiled program into the kernel: its maps created, then the program loaded against them. {prog:, maps:}, each map by its place in `compile`'s list and findable by `map_named`. `opts` adds {attach:, attach_btf_id:} for the hooks that name their target at load.

    (install({maps: [kaaneru::bpf::declare_map(:m, :nope, 4, 8, 1)]}) rescue :refused) #=> :refused
"""
def install(compiled, opts?)
  shape = if kaaneru::bpf::needs_btf?(compiled)
    kaaneru::bpf::program_btf(compiled)
  end
  program_btf = if shape != nil
    load_btf(shape[:bytes])
  end
  maps = map(
    (m) -> create_map(map_with_types(m, program_btf, shape)),
    compiled[:maps] or []
  )
  given = opts or {}
  held = fields_bound(compiled, given[:btf])
  plain = {
    signed_division: :trust,
    kind: compiled[:kind],
    maps:,
    name: compiled[:name],
    attach: given[:attach],
    attach_btf_id: given[:attach_btf_id],
    license: compiled[:license]
  }
  prog = begin
    load(
      held,
      if shape != nil
        with_program_btf(plain, program_btf, shape)
      else
        plain
      end
    )
  rescue :kernel_refused as e
    if shape.nil? and (compiled[:lines] or []) != []
      load_with_lines(held, plain, compiled)
    else
      raise(e)
    end
  end
  {prog:, maps:, btf: program_btf}
end

@doc """
with_program_btf: load options with a program's BTF, its functions and its source lines.

    with_program_btf({}, {fd: 3}, {func_info: [], line_info: []})[:btf_fd] #=> 3
"""
def with_program_btf(opts, program_btf, shape)
  reduce(
    (acc, pair) -> assoc(acc, first(pair), pair[1]),
    opts,
    [
      [:btf_fd, program_btf[:fd]],
      [:func_info, shape[:func_info]],
      [:line_info, shape[:line_info]]
    ]
  )
end

@doc """
load_with_lines: a refused plain program loaded again with its BTF and source lines, so the verifier's own log names blue's lines. A plain program that loads carries no BTF; this is the one path that gives it some. The answer stays the kernel's: a second refusal raises with the richer log, and an acceptance is the program.

    (load_with_lines({insns: []}, {kind: :nope}, {kind: :xdp, funcs: [], maps: [], lines: []}) rescue :refused) #=> :refused
"""
def load_with_lines(program, opts, compiled)
  shape = kaaneru::bpf::program_btf(compiled)
  load(program, with_program_btf(opts, load_btf(shape[:bytes]), shape))
end

@doc """
map_with_types: a map's shape with its BTF ids, when its program has BTF and names both for it. A plain map of such a program stays plain.

    map_with_types({name: :m}, nil, nil) #=> {name: :m}
    map_with_types({name: :m}, {fd: 3}, {map_types: {"m" => {key: 1, value: 2}}}).btf_value #=> 2
    map_with_types({name: :m}, {fd: 3}, {map_types: {"m" => {}}}) #=> {name: :m}
"""
def map_with_types(m, program_btf, shape)
  types = if shape != nil
    get(shape[:map_types], to_s(m[:name]))
  end
  if types.nil? or types[:value].nil?
    m
  else
    assoc(
      assoc(assoc(m, :btf_fd, program_btf[:fd]), :btf_key, types[:key]),
      :btf_value,
      types[:value]
    )
  end
end

@doc """
hook_of: the attach type and BTF id a hook's spec names: {fentry:}, {fexit:} or {fmod_ret:} a kernel function, {lsm:} a hook, {iter:} an iterator such as "task".

    hook_of(kaaneru::btf::read(kaaneru::btf::sample), {fentry: "run"}).id #=> 5
    hook_of(kaaneru::btf::read(kaaneru::btf::sample), {fexit: "run"}).kind #=> :trace_fexit
    hook_of(kaaneru::btf::read(kaaneru::btf::sample), {fmod_ret: "run"}).kind #=> :modify_return
    (hook_of(kaaneru::btf::read(kaaneru::btf::sample), {}) rescue :refused) #=> :refused
"""
def hook_of(table, spec)
  if spec[:fentry] != nil
    {kind: :trace_fentry, id: kaaneru::btf::function_id(table, spec[:fentry])}
  elsif spec[:fexit] != nil
    {kind: :trace_fexit, id: kaaneru::btf::function_id(table, spec[:fexit])}
  elsif spec[:fmod_ret] != nil
    {
      kind: :modify_return,
      id: kaaneru::btf::function_id(table, spec[:fmod_ret])
    }
  elsif spec[:lsm] != nil
    {
      kind: :lsm_mac,
      id: kaaneru::btf::function_id(table, "bpf_lsm_#{spec[:lsm]}")
    }
  elsif spec[:iter] != nil
    {
      kind: :trace_iter,
      id: kaaneru::btf::function_id(table, "bpf_iter_#{spec[:iter]}")
    }
  else
    raise(
      :bad_option,
      "a hook is {fentry:}, {fexit:}, {fmod_ret:}, {lsm:} or {iter:}"
    )
  end
end

@doc """
install_hook: a compiled :tracing or :lsm program loaded onto a kernel function and attached: `spec` {fentry: name}, {fexit: name}, {fmod_ret: name}, {lsm: hook} or {iter: name}, the target found in `table`, this kernel's BTF. {prog:, maps:, link:}. The attachment needs no netlink and no perf event.

    hook_of(kaaneru::btf::read(kaaneru::btf::sample), {fentry: "run"}).id #=> 5
    hook_of(kaaneru::btf::read(kaaneru::btf::sample), {fentry: "run"}).kind #=> :trace_fentry
    (install_hook({}, kaaneru::btf::read(kaaneru::btf::sample), {}) rescue :refused) #=> :refused
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
context_fields: BPF_PROG_RUN's context fields for a program kind. A :raw_tracepoint takes its arguments in and answers none, a :syscall program's context comes back in place, and the rest name a second buffer for the answer.

    size(context_fields(:xdp, [1])) #=> 4
    size(context_fields(:raw_tracepoint, [1])) #=> 2
    context_fields(:syscall, [1])[1] #=> [:ctx_in, {inout: [1]}]
    context_fields(:xdp, []) #=> []
"""
def context_fields(kind, ctx)
  count = length(ctx)
  if ctx == []
    []
  elsif kind == :syscall
    [[:ctx_size_in, count], [:ctx_in, {inout: ctx}]]
  elsif kind == :raw_tracepoint
    [[:ctx_size_in, count], [:ctx_in, {in: ctx}]]
  else
    [
      [:ctx_size_in, count],
      [:ctx_size_out, count],
      [:ctx_in, {in: ctx}],
      [:ctx_out, {out: count}]
    ]
  end
end

@doc """
run: a loaded program once through BPF_PROG_RUN, attached to nothing: {ret:, packet:, ctx:, duration_ns:}. `input` takes {packet:, ctx:, repeat:}, each packet at least 14 bytes. A kernel gives no such run to an :lsm program, and runs a :tracing one by calling its own test functions.

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
      context_fields(p[:kind], ctx),
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
    ctx: if ctx == [] or p[:kind] == :raw_tracepoint
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
  prog_info(p)[:id]
end

@doc """
prog_info: what the kernel holds of a loaded program: its id, name, `btf_id` and `nr_func_info` among them.

    (prog_info({fd: nil}) rescue :refused) #=> :refused
"""
def prog_info(p)
  count = width(prog_info_layout)
  a = checked(
    call_bpf(
      :obj_get_info_by_fd,
      info_layout,
      [[:bpf_fd, {fd: p[:fd]}], [:info_len, count], [:info, {out: count}]],
      false
    ),
    "prog_info"
  )
  unpack(prog_info_layout, first(a[:out]))
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
map_int: the integer a map of an installed program holds for an integer key, nil when it holds none. Each width comes from the map's shape. `kaaneru::bpf::map_int` is the same read on the machine.

    (map_int({maps: []}, :m, 0) rescue :refused) #=> :refused
"""
def map_int(live, name, key)
  m = map_named(live, name)
  if m.nil?
    raise(:bad_option, "no map #{to_s(name)}")
  end
  value = map_get(m, int_bytes(key, m[:key_size]))
  if value != nil
    bytes_int(value, 0, m[:value_size])
  end
end

@doc """
kernel_absence: why a program cannot load here, nil when one can: it loads the smallest XDP program and closes it. A test passes the answer to `tesuto::skip_for`.

    (kernel_absence.nil? or string?(kernel_absence)) #=> true
"""
def kernel_absence()
  close_object(
    load(
      assemble([alu(:mov, 0, 2), exit_program]),
      {kind: :xdp, name: "blue_probe"}
    )
  )
  nil
rescue :unsupported
  "no kernel here: this host is not Linux"
rescue :kernel_refused as e
  "the kernel refused a program with #{e.data.name}: run as root, or with CAP_BPF and CAP_NET_ADMIN"
end

@doc """
hooks: every hook `attached` takes, with the program kind it needs and what names its target.

    size(hooks) #=> 16
    first(hooks).kind #=> :xdp
"""
def hooks()
  [
    {hook: :xdp, kind: :xdp, target: "an interface index"},
    {hook: :tcx_ingress, kind: :sched_cls, target: "an interface index"},
    {hook: :tcx_egress, kind: :sched_cls, target: "an interface index"},
    {
      hook: :cgroup_inet_ingress,
      kind: :cgroup_skb,
      target: "a cgroup directory"
    },
    {
      hook: :cgroup_inet_egress,
      kind: :cgroup_skb,
      target: "a cgroup directory"
    },
    {
      hook: :cgroup_inet_sock_create,
      kind: :cgroup_sock,
      target: "a cgroup directory"
    },
    {hook: :cgroup_device, kind: :cgroup_device, target: "a cgroup directory"},
    {hook: :netfilter, kind: :netfilter, target: "{family:, hook:, priority:}"},
    {hook: :tracepoint, kind: :tracepoint, target: "[category, name]"},
    {
      hook: :raw_tracepoint,
      kind: :raw_tracepoint,
      target: "a tracepoint's name"
    },
    {hook: :kprobe, kind: :kprobe, target: "a kernel function's name"},
    {hook: :fentry, kind: :tracing, target: "a kernel function's name"},
    {hook: :fexit, kind: :tracing, target: "a kernel function's name"},
    {hook: :fmod_ret, kind: :tracing, target: "a kernel function's name"},
    {hook: :lsm, kind: :lsm, target: "an LSM hook's name"},
    {hook: :iter, kind: :tracing, target: "an iterator's name"}
  ]
end

@doc """
hook_row: the row of `hooks` that one hook spec names for a compiled program. A spec that names no hook or two, and a program of another kind, each raise :bad_option naming what fits.

    hook_row({kind: :xdp}, {xdp: 3}).hook #=> :xdp
    (hook_row({kind: :xdp}, {lsm: "file_open"}) rescue :refused) #=> :refused
    (hook_row({kind: :xdp}, {}) rescue :refused) #=> :refused
"""
def hook_row(compiled, spec)
  named = filter((row) -> get(spec, row[:hook]) != nil, hooks)
  if size(named) != 1
    legal = join(map((row) -> to_s(row[:hook]), hooks), ", ")
    raise(:bad_option, "a hook spec names one of #{legal}")
  end
  row = first(named)
  if compiled[:kind] != row[:kind]
    raise(
      :bad_option,
      "the #{to_s(row[:hook])} hook takes a #{to_s(row[:kind])} program, and this one is #{to_s(compiled[:kind])}"
    )
  end
  row
end

@doc """
linked: a loaded program's link to the hook of `row`, for every hook that does not load onto a kernel function.

    (linked({}, {hook: :kprobe}, nil) rescue :refused) #=> :refused
"""
def linked(prog, row, target)
  hook = row[:hook]
  if row[:target] == "a cgroup directory"
    attach_cgroup(prog, hook, target)
  elsif hook == :netfilter
    attach_netfilter(prog, target)
  elsif hook == :tracepoint
    attach_tracepoint(prog, first(target), target[1])
  elsif hook == :raw_tracepoint
    attach_raw_tracepoint(prog, target)
  elsif hook == :kprobe
    attach_kprobe(prog, target)
  else
    attach(prog, hook, target)
  end
end

@doc """
released: an installed program's link, maps, program and BTF closed, each at most once.

    released({maps: []}) #=> nil
"""
def released(live)
  held = append(*[[live[:link], live[:prog], live[:btf]], live[:maps]])
  map(close_object, filter((object) -> object != nil, held))
  nil
end

@doc """
attached: `compiled` loaded onto one hook while `body` runs on its live record, {prog:, maps:, link:}; the answer is what `body` answers. Whatever `body` does, the link, the maps and the program close. `spec` is one row of `hooks`: {xdp: 3}, {tracepoint: ["sched", "sched_process_exec"]}, {lsm: "file_open"}.

    (attached({kind: :xdp}, {lsm: "file_open"}, (live) -> live) rescue :refused) #=> :refused
"""
def attached(compiled, spec, body)
  row = hook_row(compiled, spec)
  hook = row[:hook]
  target = get(spec, hook)
  live = if member?(hook, %i[fentry fexit fmod_ret lsm iter])
    install_hook(compiled, kaaneru::btf::open(kaaneru::btf::vmlinux_path), spec)
  elsif row[:target] == "a cgroup directory"
    install(compiled, {attach: hook})
  elsif (compiled[:fields] or []) != []
    install(compiled, {btf: kaaneru::btf::open(kaaneru::btf::vmlinux_path)})
  else
    install(compiled)
  end
  held = live
  begin
    if live[:link].nil?
      set!(held, assoc(live, :link, linked(live[:prog], row, target)))
    end
    body(held)
  ensure
    released(held)
  end
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
open_cgroup: a descriptor on a cgroup v2 directory, what a cgroup program attaches to. A path with no `cgroup.controllers` raises :cgroup_absent: cgroup v2 is not mounted there, or no such cgroup exists.

    (open_cgroup("/no/such/cgroup") rescue :absent) #=> :absent
"""
def open_cgroup(path)
  if not path_exists(path_join(path, "cgroup.controllers"))
    raise(:cgroup_absent, "#{path} is no cgroup v2 directory")
  end
  {fd: fd_open(path), path:}
end

@doc """
attach_cgroup: a loaded program to the cgroup at `path` through BPF_LINK_CREATE: `kind` an attach type such as :cgroup_inet_egress, :cgroup_inet_sock_create or :cgroup_device. The link holds the cgroup, so its descriptor closes here.

    (attach_cgroup({}, :cgroup_device, "/no/such/cgroup") rescue :absent) #=> :absent
"""
def attach_cgroup(p, kind, path)
  cgroup = open_cgroup(path)
  begin
    attach(p, kind, cgroup)
  ensure
    close_object(cgroup)
  end
end

@doc """
netfilter_layout: `union bpf_attr` as BPF_LINK_CREATE reads it for a netfilter hook.

    width(netfilter_layout) #=> 32
    offset(netfilter_layout, :priority) #=> 24
"""
def netfilter_layout()
  layout(
    [
      %i[prog_fd u32],
      %i[target_fd u32],
      %i[attach_type u32],
      %i[flags u32],
      %i[pf u32],
      %i[hooknum u32],
      %i[priority i32],
      %i[nf_flags u32]
    ]
  )
end

@doc """
netfilter_family: the kernel's number for a netfilter family, :ipv4 or :ipv6.

    netfilter_family(:ipv4) #=> 2
    netfilter_family(:ipv6) #=> 10
    (netfilter_family(:nope) rescue :refused) #=> :refused
"""
def netfilter_family(family)
  case family
  when :ipv4
    2
  when :ipv6
    10
  else
    raise(:bad_option, "a netfilter family is :ipv4 or :ipv6")
  end
end

@doc """
netfilter_hook: the kernel's number for a netfilter hook.

    netfilter_hook(:prerouting) #=> 0
    netfilter_hook(:local_in) #=> 1
    (netfilter_hook(:nope) rescue :refused) #=> :refused
"""
def netfilter_hook(hook)
  at = index_of(%i[prerouting local_in forward local_out postrouting], hook)
  if at < 0
    raise(:bad_option, "no netfilter hook #{to_s(hook)}")
  end
  at
end

@doc """
attach_netfilter: a :netfilter program to a hook of the current network namespace: `spec` {family:, hook:, priority:}. The program answers 1 to accept a packet and 0 to drop it.

    (attach_netfilter({}, {family: :nope}) rescue :refused) #=> :refused
"""
def attach_netfilter(p, spec)
  a = call_bpf(
    :link_create,
    netfilter_layout,
    [
      [:prog_fd, {fd: p[:fd]}],
      [:attach_type, kind_id(:attach, :netfilter)],
      [:pf, netfilter_family(spec[:family])],
      [:hooknum, netfilter_hook(spec[:hook])],
      [:priority, spec[:priority]]
    ],
    true
  )
  {fd: checked(a, "attach_netfilter")[:fd], kind: :netfilter}
end

@doc """
uprobe_multi_layout: `union bpf_attr` as BPF_LINK_CREATE reads it for uprobe_multi.

    width(uprobe_multi_layout) #=> 64
    offset(uprobe_multi_layout, :pid) #=> 56
"""
def uprobe_multi_layout()
  layout(
    [
      %i[prog_fd u32],
      %i[target_fd u32],
      %i[attach_type u32],
      %i[flags u32],
      %i[path u64],
      %i[offsets u64],
      %i[ref_ctr_offsets u64],
      %i[cookies u64],
      %i[cnt u32],
      %i[uprobe_flags u32],
      %i[pid u32]
    ]
  )
end

@doc """
attach_uprobes: a kprobe program to file offsets in an executable through one uprobe_multi link, as `install` made it with {attach: :trace_uprobe_multi}. `opts` {retprobe: true} fires on return, and {pid:} holds it to one process. `entry_offset_of` finds an executable's first instruction.

    (attach_uprobes({}, "/no/such/file", []) rescue :refused) #=> :refused
"""
def attach_uprobes(p, path, offsets, opts?)
  o = opts or {}
  flags = if o[:retprobe] == true
    1
  else
    0
  end
  a = call_bpf(
    :link_create,
    uprobe_multi_layout,
    [
      [:prog_fd, {fd: p[:fd]}],
      [:attach_type, kind_id(:attach, :trace_uprobe_multi)],
      [:path, {in: append(text_bytes(path), [0])}],
      [:offsets, {in: flat_map(offsets, (at) -> int_bytes(at, 8))}],
      [:cnt, size(offsets)],
      [:uprobe_flags, flags],
      [:pid, o[:pid] or 0]
    ],
    true
  )
  {fd: checked(a, "attach_uprobes")[:fd], kind: :trace_uprobe_multi}
end

@doc """
entry_offset: the file offset of a 64-bit ELF's first instruction, from its 64-byte header and its program headers: the `PT_LOAD` segment that holds the entry address places it. An entry no segment holds raises.

    head = append(repeat(0, 24), int_bytes(4096, 8), repeat(0, 32))
    table = append(int_bytes(1, 8), int_bytes(512, 8), int_bytes(4000, 8), repeat(0, 8), int_bytes(200, 8), repeat(0, 16))
    entry_offset(head, table, 56, 1) #=> 608
"""
def entry_offset(head, table, entry_size, count)
  entry = bytes_int(head, 24, 8)
  holding = find(
    map((i) -> i * entry_size, range(0, count)),
    fn(at)
      from = bytes_int(table, at + 16, 8)
      bytes_int(table, at, 4) == 1 and
        entry >= from and
        entry < from + bytes_int(table, at + 32, 8)
    end
  )
  if holding.nil?
    raise(
      :bad_option,
      "no loaded segment holds the entry address #{to_s(entry)}"
    )
  end
  entry - bytes_int(table, holding + 16, 8) + bytes_int(table, holding + 8, 8)
end

@doc """
entry_offset_of: the file offset of an executable's first instruction, what `attach_uprobes` takes. A file that is no 64-bit ELF raises.

    (entry_offset_of("/no/such/file") rescue :refused) #=> :refused
"""
def entry_offset_of(path)
  head = read_bytes(path, 0, 64)
  if take(5, head) != [127, 69, 76, 70, 2]
    raise(:bad_option, "#{path} is no 64-bit ELF")
  end
  entry_size = bytes_int(head, 54, 2)
  count = bytes_int(head, 56, 2)
  entry_offset(
    head,
    read_bytes(path, bytes_int(head, 32, 8), entry_size * count),
    entry_size,
    count
  )
end

@doc """
iterate: what an iterator program writes for one run: the link pinned at `path` under a bpffs, read to its end, and unpinned. `install_hook` with {iter: name} makes the link.

    (iterate({}, "/no/such/pin") rescue :refused) #=> :refused
"""
def iterate(link, path)
  pin(link, path)
  begin
    read_bytes(path)
  ensure
    rm(path)
  end
end

@doc """
attach_sampling: a :perf_event program run on CPU 0 every `period_ns` of its clock, through one software perf event and a link on it. `detach` ends both.

    (attach_sampling({}, 1000000) rescue :refused) #=> :refused
"""
def attach_sampling(p, period_ns)
  attach_event(
    p,
    [
      [:type, 1],
      [:size, width(perf_attr_layout)],
      [:config, 0],
      [:sample_period, period_ns]
    ]
  )
end

@doc """
struct_ops_flag_link: `BPF_F_LINK`: a :struct_ops map whose registration a link holds, so closing the link ends it.

    struct_ops_flag_link #=> 8192
"""
def struct_ops_flag_link()
  8192
end

@doc """
placed_at: bytes with a run of them written at an offset.

    placed_at([0, 0, 0, 0], 1, [7, 8]) #=> [0, 7, 8, 0]
"""
def placed_at(bytes, at, part)
  append(*[take(at, bytes), part, drop(at + size(part), bytes)])
end

@doc """
struct_ops_value: the bytes of a `bpf_struct_ops_<ops>` map value: each program's descriptor number at its member's offset, and each given value at its own, a text as its bytes and an integer as four.

    t = kaaneru::btf::read(kaaneru::btf::sample)
    size(struct_ops_value(t, {size: 8, data: 0}, "task", [["state", 7]])) #=> 8
    first(struct_ops_value(t, {size: 8, data: 0}, "task", [["state", 7]])) #=> 7
"""
def struct_ops_value(table, shape, ops, members)
  reduce(
    fn(bytes, member)
      at = shape[:data] +
        kaaneru::btf::field(table, ops, [first(member)])[:offset]
      value = member[1]
      part = if string?(value)
        text_bytes(value)
      else
        int_bytes(value, 4)
      end
      placed_at(bytes, at, part)
    end,
    map((_i) -> 0, range(0, shape[:size])),
    members
  )
end

@doc """
install_struct_ops: a kernel operations table implemented in blue, registered through one link, its map naming a one-type BTF object since the kernel asks for one: `spec` {ops:, name:, programs:, values:}. `ops` names the kernel's struct such as "tcp_congestion_ops", `programs` pairs each member with what `compile` made for kind :struct_ops, and `values` pairs each other member with its text or integer. The maps the programs name are made once and shared. {maps:, programs:, table:, link:}; `detach` of the link unregisters it. A program needs no BTF of its own: a member's types come from the kernel's.

    (install_struct_ops(kaaneru::btf::read(kaaneru::btf::sample), {ops: "nothing"}) rescue :refused) #=> :refused
"""
def install_struct_ops(table, spec)
  ops = spec[:ops]
  ops_id = kaaneru::btf::need(table, ops, :struct)
  value_name = "bpf_struct_ops_#{ops}"
  value_id = kaaneru::btf::need(table, value_name, :struct)
  given = flat_map(spec[:programs], (p) -> p[1][:maps] or [])
  maps = map(create_map, unique_by_name(given))
  programs = map(
    fn(p)
      [
        first(p),
        load(
          fields_bound(p[1], table),
          {
            kind: :struct_ops,
            maps:,
            name: first(p),
            attach: kaaneru::btf::member_index(table, ops, first(p)),
            attach_btf_id: ops_id
          }
        )
      ]
    end,
    spec[:programs]
  )
  value_size = kaaneru::btf::size_of(table, value_id)
  btf_object = load_btf(kaaneru::btf::smallest)
  holder = begin
    create_map(
      assoc(
        assoc(
          assoc(
            kaaneru::bpf::declare_map(
              spec[:name],
              :struct_ops,
              4,
              value_size,
              1
            ),
            :flags,
            struct_ops_flag_link
          ),
          :value_type_id,
          value_id
        ),
        :btf_object,
        {fd: btf_object[:fd]}
      )
    )
  ensure
    close_object(btf_object)
  end
  map_put(
    holder,
    int_bytes(0, 4),
    struct_ops_value(
      table,
      {
        size: value_size,
        data: kaaneru::btf::field(table, value_name, ["data"])[:offset]
      },
      ops,
      append(
        spec[:values] or [],
        map((p) -> [first(p), fd_number(last(p)[:fd])], programs)
      )
    )
  )
  {maps:, programs:, table: holder, link: attach(holder, :struct_ops)}
end

@doc """
unique_by_name: map shapes with each name once, the first of each kept.

    size(unique_by_name([{name: :a}, {name: :a}, {name: :b}])) #=> 2
    unique_by_name([]) #=> []
"""
def unique_by_name(specs)
  reduce(
    fn(kept, m)
      if find(kept, (x) -> x[:name] == m[:name]).nil?
        append(kept, [m])
      else
        kept
      end
    end,
    [],
    specs
  )
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

@doc """
division_traps?: whether a kernel of this release lets `sdiv` or `smod` of the lowest value by -1 reach the CPU's divide, which traps and panics the kernel. Measured: 6.6.142 does, in a machine, and 6.12.93 does not, on plo. Every line between is out of support and counts as trapping. The fix is 7dd34d7b, "bpf: Fix a sdiv overflow issue", in 6.12.

    division_traps?("6.6.142") #=> true
    division_traps?("6.12.93") #=> false
    division_traps?("7.0.11") #=> false
"""
def division_traps?(release)
  parts = map(
    fn(p)
      to_int(join(take_while((c) -> contains?("0123456789", c), chars(p)), ""))
    end,
    take(2, split(release, "."))
  )
  parts[0] < 6 or parts[0] == 6 and parts[1] < 12
end

@doc """
division_site?: whether an instruction is a signed division or remainder whose divisor can be -1: a register, or the immediate -1.

    division_site?(alu(:sdiv, 0, kaaneru::bpf::r(1))) #=> true
    division_site?(kaaneru::bpf::alu32(:smod, 0, -1)) #=> true
    division_site?(alu(:sdiv, 0, 3)) #=> false
    division_site?(alu(:div, 0, kaaneru::bpf::r(1))) #=> false
"""
def division_site?(i)
  class = bit_and(i[:code], 7)
  op = bit_and(i[:code], 240)
  if not member?(class, [4, 7]) or not member?(op, [48, 144]) or i[:off] != 1
    false
  else
    bit_and(i[:code], 8) == 8 or member?(i[:imm], [-1, 4_294_967_295])
  end
end

@doc """
division_refusal: why this kernel must not load these instructions, or nil. A signed division with a divisor that can be -1 traps the CPU on a kernel below the fix, and the kernel panics. Pure: `mode` is `load`'s `signed_division`, and :trust turns the refusal off.

    division_refusal([alu(:sdiv, 0, kaaneru::bpf::r(1))], "6.12.93", :refuse) #=> nil
    division_refusal([alu(:sdiv, 0, kaaneru::bpf::r(1))], "6.6.142", :trust) #=> nil
    division_refusal([alu(:sdiv, 0, 3)], "6.6.142", :refuse) #=> nil
"""
def division_refusal(insns, release, mode)
  if mode != :trust and any?(division_site?, insns) and division_traps?(release)
    "this program can divide the lowest value by -1, which panics Linux #{release}: the fix, 7dd34d7b, is in 6.12. Compile it (the compiler proves its divisor positive), guard the divisor, or load with signed_division: :trust"
  end
end

@doc """
refuse_division: raise :division_trap when `division_refusal` has a reason. The release is read only for a program that holds such a division.

    refuse_division([exit_program], :refuse) #=> nil
"""
def refuse_division(insns, mode)
  if mode != :trust and any?(division_site?, insns)
    release = kernel_release
    why = division_refusal(insns, release, mode)
    if why != nil
      raise(:division_trap, why, {data: {release:, fixed_in: "6.12"}})
    end
  end
  nil
end

test "a division that can panic this kernel is refused by name, and every other form loads on"
  by_reg = alu(:sdiv, 0, kaaneru::bpf::r(1))
  floor = "6.6.142"
  assert contains?(division_refusal([by_reg], floor, :refuse), "Linux 6.6.142")
  assert contains?(division_refusal([by_reg], floor, :refuse), "6.12")
  assert division_refusal(
    [kaaneru::bpf::alu32(:smod, 0, kaaneru::bpf::r(1))],
    floor,
    :refuse
  ) != nil
  assert division_refusal([alu(:smod, 0, -1)], floor, :refuse) != nil
  assert division_refusal([by_reg], "6.12.93", :refuse).nil?
  assert division_refusal([by_reg], floor, :trust).nil?
  assert division_refusal([alu(:sdiv, 0, 3)], floor, :refuse).nil?
  assert division_refusal(
    [alu(:div, 0, kaaneru::bpf::r(1))],
    floor,
    :refuse
  ).nil?
  assert division_refusal(
    [kaaneru::bpf::jump(:eq, 0, 0, 0)],
    floor,
    :refuse
  ).nil?
  assert division_refusal([], floor, :refuse).nil?
end

test "a program with no such division never asks the release"
  assert refuse_division([alu(:mov, 0, 2)], :refuse).nil?
  assert refuse_division([alu(:sdiv, 0, kaaneru::bpf::r(1))], :trust).nil?
end

test "division traps below 6.12, and a suffix on the release changes nothing"
  assert division_traps?("5.15.0")
  assert division_traps?("6.11.9")
  assert division_traps?("6.6.142")
  assert not division_traps?("6.12-rc1")
  assert not division_traps?("6.18.34")
  assert not division_traps?("10.0.1")
end

test "a refusal's message names the blue line and the reason the log gave, and its data holds both"
  text = unlines(
    [
      "0: (b7) r0 = 0",
      "1: (61) r0 = *(u32 *)(r6 +1000)",
      "invalid bpf_context access off=1000 size=4",
      "processed 2 insns (limit 1000000)"
    ]
  )
  program = {
    lines: [{at: 0, line: 3, col: 3}, {at: 1, line: 7, col: 5}],
    funcs: [],
    source: {file: "f.b", text: ["", "", "", "", "", "", "  far = 1"]}
  }
  answer = {errno: 13, out: [text_bytes(text)]}
  caught = begin
    refused_load(answer, "p", program)
    nil
  rescue :kernel_refused as e
    e
  end
  assert caught.message ==
    "load p: EACCES at f.b:7:5: invalid bpf_context access off=1000 size=4"
  assert caught.data.insn == 1
  assert caught.data.at.text == "  far = 1"
  bare = begin
    refused_load(answer, "p", {lines: [], funcs: []})
    nil
  rescue :kernel_refused as e
    e
  end
  assert contains?(bare.message, "at instruction 1:")
  assert bare.data.at.nil?
end

test "a verifier log with a register line after its instruction keeps the last instruction and drops source lines"
  log = unlines(
    [
      "0: R1=ctx() R10=fp0",
      "; x @ f.b:2",
      "0: (bf) r6 = r1",
      "1: (61) r0 = *(u8 *)(r6 +0)",
      "R6 bad",
      "R0 worse",
      "; y @ f.b:3",
      "processed 2 insns"
    ]
  )
  got = verifier_said(log)
  assert got[:insn] == 1
  assert got[:reason] == "R6 bad; R0 worse"
end

test "line info for BPF_PROG_LOAD is 16 bytes a row, in the order the kernel reads"
  fields = line_info_fields([{at: 2, file: 1, text: 3, pos: 2051}])
  assert first(fields) == [:line_info_rec_size, 16]
  assert fields[1][1][:in] ==
    append(
      *[int_bytes(2, 4), int_bytes(1, 4), int_bytes(3, 4), int_bytes(2051, 4)]
    )
  assert size(
    load_fields(
      :xdp,
      [],
      {btf_fd: 3, line_info: [{at: 0, file: 1, text: 2, pos: 3}]},
      0
    )
  ) > 3
  assert filter(
    (f) -> first(f) == :line_info_cnt,
    load_fields(:xdp, [], {}, 0)
  ) == []
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

test "the attach layouts place every field where the UAPI header does"
  assert offset(netfilter_layout, :pf) == 16
  assert offset(netfilter_layout, :hooknum) == 20
  assert offset(netfilter_layout, :priority) == 24
  assert offset(uprobe_multi_layout, :path) == 16
  assert offset(uprobe_multi_layout, :offsets) == 24
  assert offset(uprobe_multi_layout, :cnt) == 48
  assert offset(uprobe_multi_layout, :uprobe_flags) == 52
  assert offset(uprobe_multi_layout, :pid) == 56
end

test "a path that is no cgroup is a named absence, before any call to the kernel"
  got = begin
    open_cgroup("/no/such/cgroup")
  rescue :cgroup_absent as e
    e.message
  end
  assert contains?(got, "/no/such/cgroup")
  assert (attach_cgroup({}, :cgroup_device, "/") rescue :refused) == :refused
end

test "a netfilter spec names a known family and hook, and refuses any other"
  assert netfilter_family(:ipv6) == 10
  assert netfilter_hook(:postrouting) == 4
  assert (netfilter_family(:ipx) rescue :refused) == :refused
  assert (netfilter_hook(:later) rescue :refused) == :refused
end

test "a kind the kernel ties to one attach type names it at load unasked, and a named one wins"
  assert member?(
    [:expected_attach_type, 45],
    load_fields(:netfilter, [], {}, 0)
  )
  assert member?(
    [:expected_attach_type, 36],
    load_fields(:sk_lookup, [], {}, 0)
  )
  assert member?(
    [:expected_attach_type, 37],
    load_fields(:netfilter, [], {attach: :xdp}, 0)
  )
  assert map(first, load_fields(:xdp, [], {}, 0)) ==
    %i[prog_type insn_cnt insns license prog_name]
end

test "BPF_BTF_LOAD's layout places every field where the UAPI header does"
  assert offset(btf_load_layout, :btf_log_buf) == 8
  assert offset(btf_load_layout, :btf_log_size) == 20
  assert offset(btf_load_layout, :btf_token_fd) == 36
end

test "a :syscall program loads sleepable, and no other kind does"
  assert member?([:prog_flags, 16], load_fields(:syscall, [], {}, 0))
  assert not member?([:prog_flags, 16], load_fields(:xdp, [], {}, 0))
end

test "BPF_PROG_RUN's context follows what each kernel kind allows"
  assert context_fields(:sk_lookup, []) == []
  out = (name, kind) -> member?(name, map(first, context_fields(kind, [1])))
  assert out(:ctx_out, :sk_lookup)
  assert not out(:ctx_out, :syscall)
  assert not out(:ctx_out, :raw_tracepoint)
  assert context_fields(:raw_tracepoint, [1])[1] == [:ctx_in, {in: [1]}]
end

test "an executable's entry is placed by the segment that holds it, and none holding it refuses"
  head = append(repeat(0, 24), int_bytes(4096, 8), repeat(0, 32))
  row = fn(kind, offs, addr, sz)
    append(
      *[
        int_bytes(kind, 8),
        int_bytes(offs, 8),
        int_bytes(addr, 8),
        repeat(0, 8),
        int_bytes(sz, 8),
        repeat(0, 16)
      ]
    )
  end
  skipped = row(6, 900, 0, 9000)
  low = row(1, 0, 0, 4096)
  held = row(1, 512, 4000, 200)
  assert entry_offset(head, append(*[skipped, low, held]), 56, 3) == 608
  assert (entry_offset(head, low, 56, 1) rescue :refused) == :refused
  assert (entry_offset(head, [], 56, 0) rescue :refused) == :refused
end

test "an executable's entry comes from its own file, and a file that is no ELF refuses"
  dir = path_join(temp_dir("kaaneru-elf"), "kaaneru-elf")
  mkdir_p(dir)
  elf = path_join(dir, "program")
  plain = path_join(dir, "plain")
  low = append(
    *[
      int_bytes(1, 8),
      int_bytes(0, 8),
      int_bytes(0, 8),
      repeat(0, 8),
      int_bytes(8192, 8),
      repeat(0, 16)
    ]
  )
  head = append(
    *[
      [127, 69, 76, 70, 2],
      repeat(0, 19),
      int_bytes(4096, 8),
      int_bytes(64, 8),
      repeat(0, 14),
      int_bytes(56, 2),
      int_bytes(1, 2),
      repeat(0, 6)
    ]
  )
  write_bytes(elf, append(head, low))
  write_bytes(plain, append(append([127, 69, 76, 70, 1], drop(5, head)), low))
  found = entry_offset_of(elf)
  refused = entry_offset_of(plain) rescue :refused
  rm_rf(dir)
  assert found == 4096
  assert refused == :refused
end

test "attached refuses a spec and a kind that do not fit before it reaches the kernel"
  xdp = {kind: :xdp}
  assert hook_row(xdp, {xdp: 3}).target == "an interface index"
  e = begin
    attached(xdp, {lsm: "file_open"}, (_live) -> :ran)
  rescue :bad_option as refused
    refused
  end
  assert contains?(e.message, "takes a lsm program")
  assert contains?(e.message, "this one is xdp")
  none = begin
    hook_row(xdp, {nope: 1})
  rescue :bad_option as refused
    refused
  end
  assert contains?(none.message, "fentry")
  assert (hook_row(xdp, {xdp: 1, lsm: "x"}) rescue :refused) == :refused
end

test "every hook names a program kind the kernel has"
  assert filter((row) -> kind_id(:prog, row[:kind]) < 0, hooks) == []
end

test "released closes nothing it was not given"
  assert released({maps: []}).nil?
end

test "attached answers a named absence or refusal when nothing can load, and never runs its body"
  program = assemble([alu(:mov, 0, 2), exit_program])
  ran = attached(
    assoc(program, :kind, :xdp),
    {xdp: 2_147_483_647},
    (_live) -> :ran
  ) rescue
    :absent
  assert ran == :absent
end

test "a hook's spec names its attach type, and an empty one refuses"
  t = kaaneru::btf::read(kaaneru::btf::sample)
  assert (hook_of(t, {lsm: "run"}) rescue :refused) == :refused
  assert hook_of(t, {fexit: "run"}).id == 5
  assert (hook_of(t, {iter: "run"}) rescue :refused) == :refused
  assert (hook_of(t, {}) rescue :refused) == :refused
end

test "a struct_ops value holds each program and value at its member, and the rest zero"
  t = kaaneru::btf::read(kaaneru::btf::sample)
  bytes = struct_ops_value(
    t,
    {size: 16, data: 4},
    "task",
    [%w[pid ab], ["state", 9]]
  )
  assert size(bytes) == 16
  assert bytes == [0, 0, 0, 0, 9, 0, 0, 0, 97, 98, 0, 0, 0, 0, 0, 0]
  assert placed_at([1, 2], 0, []) == [1, 2]
end

test "maps shared by a table's programs are made once"
  assert map(
    (m) -> m[:name],
    unique_by_name([{name: :a, n: 1}, {name: :b}, {name: :a, n: 2}])
  ) == %i[a b]
  assert first(unique_by_name([{name: :a, n: 1}, {name: :a, n: 2}]))[:n] == 1
end
