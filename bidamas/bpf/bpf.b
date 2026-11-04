@moduledoc """
bpf — the eBPF instruction set in blue: instructions as values, an assembler that resolves labels and map references, their encoding, their text, and a pure machine that runs them.

The encoding is RFC 9669. The kernel, `llvm-mc` and this machine are checked against each other instruction by instruction, so a program can be assembled and tested on any host and loaded on Linux through `kaaneru`.

    p = assemble([alu(:mov, 0, 2), exit_program])
    size(p[:insns]) #=> 2
    encode(p) #=> [183, 0, 0, 0, 2, 0, 0, 0, 149, 0, 0, 0, 0, 0, 0, 0]
    run(p).ret #=> 2
"""

use("baito", %i[bytes_int int_bytes])
use("jisho", [:update])
use("retsu", %i[first flat_map index_of last repeat rest size zip])
use("shisutemu", [:blue_exe])

@doc """
op_table: the number a name has in a table of rows, raising on a name the table lacks.

    op_table([[:a, 1]], :a, "x") #=> 1
"""
def op_table(rows, name, what)
  row = find(rows, (r) -> first(r) == name)
  if row.nil?
    raise(:bad_option, "no #{what} #{to_s(name)}")
  end
  row[1]
end

@doc """
sizes: the access sizes and the bits each sets in an opcode.

    size(sizes) #=> 4
"""
def sizes()
  [[:w, 0], [:h, 8], [:b, 16], [:dw, 24]]
end

@doc """
alu_ops: the ALU operations and the bits each sets in an opcode.

    first(alu_ops) #=> [:add, 0]
"""
def alu_ops()
  [
    [:add, 0],
    [:sub, 16],
    [:mul, 32],
    [:div, 48],
    [:or, 64],
    [:and, 80],
    [:lsh, 96],
    [:rsh, 112],
    [:mod, 144],
    [:xor, 160],
    [:mov, 176],
    [:arsh, 192],
    [:sdiv, 48],
    [:smod, 144],
    [:movsx8, 176],
    [:movsx16, 176],
    [:movsx32, 176]
  ]
end

@doc """
regular_ops: the ALU operations that take a register or an immediate in either width: every operation but the sign extending moves.

    size(regular_ops) #=> 14
    first(regular_ops) #=> :add
"""
def regular_ops()
  %i[add sub mul div or and lsh rsh mod xor mov arsh sdiv smod]
end

@doc """
alu_offsets: the ALU operations the offset field tells apart from their plain forms.

    first(alu_offsets) #=> [:sdiv, 1]
"""
def alu_offsets()
  [[:sdiv, 1], [:smod, 1], [:movsx8, 8], [:movsx16, 16], [:movsx32, 32]]
end

@doc """
jump_ops: the jump conditions and the bits each sets in an opcode.

    first(jump_ops) #=> [:eq, 16]
"""
def jump_ops()
  [
    [:eq, 16],
    [:gt, 32],
    [:ge, 48],
    [:set, 64],
    [:ne, 80],
    [:sgt, 96],
    [:sge, 112],
    [:lt, 160],
    [:le, 176],
    [:slt, 192],
    [:sle, 208]
  ]
end

@doc """
atomic_ops: the atomic operations and the immediate each is.

    first(atomic_ops) #=> [:add, 0]
"""
def atomic_ops()
  [
    [:add, 0],
    [:or, 64],
    [:and, 80],
    [:xor, 160],
    [:fetch_add, 1],
    [:fetch_or, 65],
    [:fetch_and, 81],
    [:fetch_xor, 161],
    [:xchg, 225],
    [:cmpxchg, 241]
  ]
end

@doc """
helper_names: the kernel's helper functions in the order of their numbers, from `__BPF_FUNC_MAPPER` in `include/uapi/linux/bpf.h` at 6.16.

    nth(1, helper_names) #=> :map_lookup_elem
    size(helper_names) #=> 212
"""
def helper_names()
  %i[
    unspec
    map_lookup_elem
    map_update_elem
    map_delete_elem
    probe_read
    ktime_get_ns
    trace_printk
    get_prandom_u32
    get_smp_processor_id
    skb_store_bytes
    l3_csum_replace
    l4_csum_replace
    tail_call
    clone_redirect
    get_current_pid_tgid
    get_current_uid_gid
    get_current_comm
    get_cgroup_classid
    skb_vlan_push
    skb_vlan_pop
    skb_get_tunnel_key
    skb_set_tunnel_key
    perf_event_read
    redirect
    get_route_realm
    perf_event_output
    skb_load_bytes
    get_stackid
    csum_diff
    skb_get_tunnel_opt
    skb_set_tunnel_opt
    skb_change_proto
    skb_change_type
    skb_under_cgroup
    get_hash_recalc
    get_current_task
    probe_write_user
    current_task_under_cgroup
    skb_change_tail
    skb_pull_data
    csum_update
    set_hash_invalid
    get_numa_node_id
    skb_change_head
    xdp_adjust_head
    probe_read_str
    get_socket_cookie
    get_socket_uid
    set_hash
    setsockopt
    skb_adjust_room
    redirect_map
    sk_redirect_map
    sock_map_update
    xdp_adjust_meta
    perf_event_read_value
    perf_prog_read_value
    getsockopt
    override_return
    sock_ops_cb_flags_set
    msg_redirect_map
    msg_apply_bytes
    msg_cork_bytes
    msg_pull_data
    bind
    xdp_adjust_tail
    skb_get_xfrm_state
    get_stack
    skb_load_bytes_relative
    fib_lookup
    sock_hash_update
    msg_redirect_hash
    sk_redirect_hash
    lwt_push_encap
    lwt_seg6_store_bytes
    lwt_seg6_adjust_srh
    lwt_seg6_action
    rc_repeat
    rc_keydown
    skb_cgroup_id
    get_current_cgroup_id
    get_local_storage
    sk_select_reuseport
    skb_ancestor_cgroup_id
    sk_lookup_tcp
    sk_lookup_udp
    sk_release
    map_push_elem
    map_pop_elem
    map_peek_elem
    msg_push_data
    msg_pop_data
    rc_pointer_rel
    spin_lock
    spin_unlock
    sk_fullsock
    tcp_sock
    skb_ecn_set_ce
    get_listener_sock
    skc_lookup_tcp
    tcp_check_syncookie
    sysctl_get_name
    sysctl_get_current_value
    sysctl_get_new_value
    sysctl_set_new_value
    strtol
    strtoul
    sk_storage_get
    sk_storage_delete
    send_signal
    tcp_gen_syncookie
    skb_output
    probe_read_user
    probe_read_kernel
    probe_read_user_str
    probe_read_kernel_str
    tcp_send_ack
    send_signal_thread
    jiffies64
    read_branch_records
    get_ns_current_pid_tgid
    xdp_output
    get_netns_cookie
    get_current_ancestor_cgroup_id
    sk_assign
    ktime_get_boot_ns
    seq_printf
    seq_write
    sk_cgroup_id
    sk_ancestor_cgroup_id
    ringbuf_output
    ringbuf_reserve
    ringbuf_submit
    ringbuf_discard
    ringbuf_query
    csum_level
    skc_to_tcp6_sock
    skc_to_tcp_sock
    skc_to_tcp_timewait_sock
    skc_to_tcp_request_sock
    skc_to_udp6_sock
    get_task_stack
    load_hdr_opt
    store_hdr_opt
    reserve_hdr_opt
    inode_storage_get
    inode_storage_delete
    d_path
    copy_from_user
    snprintf_btf
    seq_printf_btf
    skb_cgroup_classid
    redirect_neigh
    per_cpu_ptr
    this_cpu_ptr
    redirect_peer
    task_storage_get
    task_storage_delete
    get_current_task_btf
    bprm_opts_set
    ktime_get_coarse_ns
    ima_inode_hash
    sock_from_file
    check_mtu
    for_each_map_elem
    snprintf
    sys_bpf
    btf_find_by_name_kind
    sys_close
    timer_init
    timer_set_callback
    timer_start
    timer_cancel
    get_func_ip
    get_attach_cookie
    task_pt_regs
    get_branch_snapshot
    trace_vprintk
    skc_to_unix_sock
    kallsyms_lookup_name
    find_vma
    loop
    strncmp
    get_func_arg
    get_func_ret
    get_func_arg_cnt
    get_retval
    set_retval
    xdp_get_buff_len
    xdp_load_bytes
    xdp_store_bytes
    copy_from_user_task
    skb_set_tstamp
    ima_file_hash
    kptr_xchg
    map_lookup_percpu_elem
    skc_to_mptcp_sock
    dynptr_from_mem
    ringbuf_reserve_dynptr
    ringbuf_submit_dynptr
    ringbuf_discard_dynptr
    dynptr_read
    dynptr_write
    dynptr_data
    tcp_raw_gen_syncookie_ipv4
    tcp_raw_gen_syncookie_ipv6
    tcp_raw_check_syncookie_ipv4
    tcp_raw_check_syncookie_ipv6
    ktime_get_tai_ns
    user_ringbuf_drain
    cgrp_storage_get
    cgrp_storage_delete
  ]
end

@doc """
helper_id: the number of a kernel helper, raising on a name the kernel does not have.

    helper_id(:ktime_get_ns) #=> 5
    helper_id(:ringbuf_output) #=> 130
"""
def helper_id(name)
  at = index_of(helper_names, name)
  if at < 0
    raise(:bad_option, "no BPF helper #{to_s(name)}")
  end
  at
end

@doc """
r: register n as an operand, where a bare integer is an immediate.

    r(3) #=> {reg: 3}
"""
def r(n)
  if not integer?(n) or n < 0 or n > 10
    raise(:bad_option, "a register is 0 to 10, got #{to_s(n)}")
  end
  {reg: n}
end

@doc """
reg_of: a register's number from `r(n)` or a bare number.

    reg_of(r(3)) #=> 3
    reg_of(3) #=> 3
"""
def reg_of(x)
  if map?(x)
    x[:reg]
  else
    r(x)[:reg]
  end
end

@doc """
reg?: whether an operand is a register rather than an immediate.

    reg?(r(3)) #=> true
    reg?(3) #=> false
"""
def reg?(x)
  not integer?(x)
end

@doc """
imm32_of: an immediate, raising on one that takes more than 32 bits.

    imm32_of(5) #=> 5
"""
def imm32_of(v)
  if not integer?(v) or v < -2_147_483_648 or v > 4_294_967_295
    raise(:bad_option, "an immediate takes 32 bits, got #{to_s(v)}")
  end
  v
end

@doc """
insn: one instruction from its five fields.

    insn(149, 0, 0, 0, 0).code #=> 149
"""
def insn(code, dst, src, off, imm)
  {code:, dst:, src:, off:, imm:}
end

@doc """
alu_at: an ALU instruction in a class, 7 for 64-bit and 4 for 32-bit.

    alu_at(7, :mov, 0, 1).code #=> 183
"""
def alu_at(class, op, dst, operand)
  base = op_table(alu_ops, op, "ALU operation")
  extra = find(alu_offsets, (x) -> first(x) == op)
  off = if extra.nil?
    0
  else
    extra[1]
  end
  if reg?(operand)
    insn(base + 8 + class, reg_of(dst), reg_of(operand), off, 0)
  elsif off >= 8
    raise(:bad_option, "#{to_s(op)} takes a register")
  else
    insn(base + class, reg_of(dst), 0, off, imm32_of(operand))
  end
end

@doc """
alu: a 64-bit arithmetic or logic instruction: add sub mul div or and lsh rsh mod xor mov arsh sdiv smod movsx8 movsx16 movsx32. The operand is `r(n)` or an immediate.

    alu(:add, 1, r(2)).code #=> 15
    alu(:mov, 0, 7).code #=> 183
    alu(:sdiv, 1, 3).off #=> 1
"""
def alu(op, dst, operand)
  alu_at(7, op, dst, operand)
end

@doc """
alu32: the 32-bit form of `alu`, whose result clears the register's upper half.

    alu32(:add, 1, r(2)).code #=> 12
"""
def alu32(op, dst, operand)
  if op == :movsx32
    raise(
      :bad_option,
      "a 32-bit move sign extends from 8 or 16 bits; movsx32 is 64-bit only"
    )
  end
  alu_at(4, op, dst, operand)
end

@doc """
neg: the arithmetic negation of a register, over 64 bits, or over 32 when `bits` says so.

    neg(1).code #=> 135
    neg(1, 32).code #=> 132
"""
def neg(dst, bits?)
  code = if bits == 32
    132
  else
    135
  end
  insn(code, reg_of(dst), 0, 0, 0)
end

@doc """
swap_bits: a byte swap's width, raising on one that is not 16, 32 or 64.

    swap_bits(16) #=> 16
"""
def swap_bits(bits)
  if not member?(bits, [16, 32, 64])
    raise(:bad_option, "a byte swap is 16, 32 or 64 bits, got #{to_s(bits)}")
  end
  bits
end

@doc """
swap: a register's byte order changed at 16, 32 or 64 bits: `:be` to big-endian, `:le` to little-endian, `:any` reversed whatever the host's order, the last from cpu v4.

    swap(:be, 1, 16).code #=> 220
    swap(:le, 1, 32).code #=> 212
    swap(:any, 1, 64).code #=> 215
"""
def swap(order, dst, bits)
  code = case order
  when :be
    220
  when :le
    212
  when :any
    215
  else
    raise(:bad_option, "a byte swap is :be, :le or :any, got #{to_s(order)}")
  end
  insn(code, reg_of(dst), 0, 0, swap_bits(bits))
end

@doc """
jump_at: a jump instruction in a class, 5 for 64-bit and 6 for 32-bit.

    jump_at(5, :eq, 1, 0, :out).code #=> 21
"""
def jump_at(class, op, dst, operand, target)
  base = op_table(jump_ops, op, "jump condition")
  if reg?(operand)
    assoc(
      insn(base + 8 + class, reg_of(dst), reg_of(operand), 0, 0),
      :target,
      target
    )
  else
    assoc(
      insn(base + class, reg_of(dst), 0, 0, imm32_of(operand)),
      :target,
      target
    )
  end
end

@doc """
jump: go to `target`, a label or an offset, when a 64-bit condition holds: eq gt ge set ne sgt sge lt le slt sle.

    jump(:eq, 1, 0, :out).code #=> 21
    jump(:eq, 1, r(2), :out).code #=> 29
"""
def jump(op, dst, operand, target)
  jump_at(5, op, dst, operand, target)
end

@doc """
jump32: the form of `jump` that compares the low 32 bits.

    jump32(:lt, 1, 0, :out).code #=> 166
"""
def jump32(op, dst, operand, target)
  jump_at(6, op, dst, operand, target)
end

@doc """
ja: go to `target` always; `wide` true gives the 32-bit offset of cpu v4.

    ja(:out).code #=> 5
    ja(:out, true).code #=> 6
"""
def ja(target, wide?)
  if wide == true
    assoc(insn(6, 0, 0, 0, 0), :wide_target, target)
  else
    assoc(insn(5, 0, 0, 0, 0), :target, target)
  end
end

@doc """
call: a kernel helper by name or number.

    call(:ktime_get_ns).imm #=> 5
    call(5).imm #=> 5
"""
def call(helper)
  id = if integer?(helper)
    helper
  else
    helper_id(helper)
  end
  insn(133, 0, 0, 0, id)
end

@doc """
call_local: a subprogram of this program at a label.

    call_local(:f).src #=> 1
"""
def call_local(target)
  assoc(insn(133, 0, 1, 0, 0), :call_target, target)
end

@doc """
call_kfunc: a kernel function by its BTF id.

    call_kfunc(77).src #=> 2
"""
def call_kfunc(btf_id)
  insn(133, 0, 2, 0, btf_id)
end

@doc """
exit_program: return to the caller, with r0 the value.

    exit_program.code #=> 149
"""
def exit_program()
  insn(149, 0, 0, 0, 0)
end

@doc """
size_code: the bits an access size sets in an opcode.

    size_code(:b) #=> 16
"""
def size_code(size)
  op_table(sizes, size, "access size")
end

@doc """
load: a value of size w, h, b or dw from memory at a register plus an offset, zero extended.

    load(:b, 1, 2, 4).code #=> 113
"""
def load(size, dst, base, off)
  insn(97 + size_code(size), reg_of(dst), reg_of(base), off, 0)
end

@doc """
load_signed: a value of size w, h or b from memory, sign extended, an instruction from cpu v4.

    load_signed(:b, 1, 2, 4).code #=> 145
"""
def load_signed(size, dst, base, off)
  if size == :dw
    raise(:bad_option, "a signed load is w, h or b")
  end
  insn(129 + size_code(size), reg_of(dst), reg_of(base), off, 0)
end

@doc """
store: a register or an immediate to memory at a register plus an offset.

    store(:w, 10, -4, r(1)).code #=> 99
    store(:w, 10, -4, 7).code #=> 98
"""
def store(size, base, off, value)
  if reg?(value)
    insn(99 + size_code(size), reg_of(base), reg_of(value), off, 0)
  else
    insn(98 + size_code(size), reg_of(base), 0, off, imm32_of(value))
  end
end

@doc """
atomic: an atomic read-modify-write of size w or dw: add or and xor fetch_add fetch_or fetch_and fetch_xor xchg cmpxchg.

    atomic(:add, :dw, 1, 0, 2).code #=> 219
    atomic(:xchg, :w, 1, 0, 2).imm #=> 225
"""
def atomic(op, size, base, off, src)
  if not member?(size, %i[w dw])
    raise(:bad_option, "an atomic is w or dw, got #{to_s(size)}")
  end
  insn(
    195 + size_code(size),
    reg_of(base),
    reg_of(src),
    off,
    op_table(atomic_ops, op, "atomic operation")
  )
end

@doc """
imm64: a whole 64-bit value into a register, the one instruction that takes two slots.

    imm64(1, 5).code #=> 24
    imm64(1, 5).imm2 #=> 0
"""
def imm64(dst, value)
  assoc(
    insn(24, reg_of(dst), 0, 0, bit_and(value, 4_294_967_295)),
    :imm2,
    bit_and(shift_right(value, 32), 4_294_967_295)
  )
end

@doc """
map_ref: the map named `name` into a register, resolved when the program is loaded.

    map_ref(1, :counts).src #=> 1
"""
def map_ref(dst, name)
  assoc(assoc(insn(24, reg_of(dst), 1, 0, 0), :imm2, 0), :map, name)
end

@doc """
map_value_ref: the address of a place in the value of an array map named `name`, resolved when the program is loaded.

    map_value_ref(1, :globals, 8).imm2 #=> 8
"""
def map_value_ref(dst, name, off)
  assoc(assoc(insn(24, reg_of(dst), 2, 0, 0), :imm2, off), :map, name)
end

@doc """
load_abs: the legacy read of a packet at an absolute offset into r0, for socket filters.

    load_abs(:b, 14).code #=> 48
"""
def load_abs(size, off)
  insn(32 + size_code(size), 0, 0, 0, off)
end

@doc """
load_ind: the legacy read of a packet at a register plus an offset into r0, for socket filters.

    load_ind(:b, 7, 14).code #=> 80
"""
def load_ind(size, base, off)
  insn(64 + size_code(size), 0, reg_of(base), 0, off)
end

@doc """
label: a position other instructions name. It takes no slot.

    label(:out) #=> {label: :out}
"""
def label(name)
  {label: name}
end

@doc """
wide?: whether an instruction takes two slots.

    wide?(imm64(1, 5)) #=> true
    wide?(exit_program) #=> false
"""
def wide?(i)
  i[:imm2] != nil
end

@doc """
slots_of: the slots an item takes: two for `imm64`, none for a label.

    slots_of(imm64(1, 5)) #=> 2
    slots_of(label(:a)) #=> 0
"""
def slots_of(i)
  if i[:label] != nil
    0
  elsif wide?(i)
    2
  else
    1
  end
end

@doc """
flat_items: nested lists of items as one list.

    flat_items([[1], [[2]]]) #=> [1, 2]
"""
def flat_items(items)
  flat_map(
    items,
    fn(x)
      if list?(x)
        flat_items(x)
      else
        [x]
      end
    end
  )
end

@doc """
label_table: each label's slot, and the slot past the last item.

    label_table([exit_program, label(:a)])[:at] #=> 1
"""
def label_table(items)
  reduce(
    fn(acc, i)
      if i[:label] != nil
        if get(acc[:labels], i[:label]) != nil
          raise(:bad_option, "the label #{to_s(i[:label])} is placed twice")
        end
        {at: acc[:at], labels: assoc(acc[:labels], i[:label], acc[:at])}
      else
        {at: acc[:at] + slots_of(i), labels: acc[:labels]}
      end
    end,
    {at: 0, labels: {}},
    items
  )
end

@doc """
target_offset: a jump's offset from its target, a label or already an offset.

    target_offset({}, 3, 0) #=> 3
"""
def target_offset(labels, target, pc)
  if integer?(target)
    target
  else
    at = get(labels, target)
    if at.nil?
      raise(:bad_option, "no label #{to_s(target)}")
    end
    at - pc - 1
  end
end

@doc """
offset16: an offset, raising on one past the 16 bits a jump holds.

    offset16(7) #=> 7
"""
def offset16(n)
  if n < -32768 or n > 32767
    raise(:bad_option, "a jump of #{to_s(n)} does not fit 16 bits; use gotol")
  end
  n
end

@doc """
resolved: an instruction with its target written into its offset.

    resolved(ja(2), {}, 0).off #=> 2
"""
def resolved(i, labels, pc)
  if i[:target] != nil
    dissoc(
      assoc(i, :off, offset16(target_offset(labels, i[:target], pc))),
      :target
    )
  elsif i[:wide_target] != nil
    dissoc(
      assoc(i, :imm, target_offset(labels, i[:wide_target], pc)),
      :wide_target
    )
  elsif i[:call_target] != nil
    dissoc(
      assoc(i, :imm, target_offset(labels, i[:call_target], pc)),
      :call_target
    )
  else
    i
  end
end

@doc """
assemble: instructions and labels, nested lists flattened, to a program: labels resolved to offsets and each map reference recorded as a relocation {at:, map:}, `at` counted in slots.

    assemble([ja(:out), label(:out), exit_program])[:insns][0][:off] #=> 0
    assemble([map_ref(1, :m), exit_program])[:relocs] #=> [{at: 0, map: :m}]
    (assemble([ja(:nowhere)]) rescue :refused) #=> :refused
"""
def assemble(items)
  flat = flat_items(items)
  labels = label_table(flat)[:labels]
  placed = reduce(
    fn(acc, i)
      if i[:label] != nil
        acc
      else
        fixed = resolved(i, labels, acc[:at])
        relocs = if i[:map] != nil
          append(acc[:relocs], [{at: acc[:at], map: i[:map]}])
        else
          acc[:relocs]
        end
        fields = if i[:field] != nil
          append(acc[:fields], [assoc(i[:field], :at, acc[:at])])
        else
          acc[:fields]
        end
        {
          at: acc[:at] + slots_of(i),
          insns: append(acc[:insns], [dissoc(dissoc(fixed, :map), :field)]),
          relocs:,
          fields:
        }
      end
    end,
    {at: 0, insns: [], relocs: [], fields: []},
    flat
  )
  {
    insns: placed[:insns],
    relocs: placed[:relocs],
    fields: placed[:fields],
    slots: placed[:at]
  }
end

@doc """
slot_bytes: one 8-byte slot from its five fields.

    slot_bytes(149, 0, 0, 0, 0) #=> [149, 0, 0, 0, 0, 0, 0, 0]
"""
def slot_bytes(code, dst, src, off, imm)
  append(
    [code, bit_or(bit_and(dst, 15), shift_left(bit_and(src, 15), 4))],
    int_bytes(off, 2),
    int_bytes(imm, 4)
  )
end

@doc """
encode_insn: one instruction's bytes: 8, or 16 for `imm64`.

    encode_insn(alu(:mov, 1, 2)) #=> [183, 1, 0, 0, 2, 0, 0, 0]
    size(encode_insn(imm64(1, 5))) #=> 16
"""
def encode_insn(i)
  first_slot = slot_bytes(i[:code], i[:dst], i[:src], i[:off], i[:imm])
  if wide?(i)
    append(first_slot, slot_bytes(0, 0, 0, 0, i[:imm2]))
  else
    first_slot
  end
end

@doc """
encode: an assembled program's bytes, as the kernel takes them.

    encode(assemble([])) #=> []
    size(encode(assemble([exit_program]))) #=> 8
"""
def encode(program)
  flat_map(program[:insns], encode_insn)
end

@doc """
slot_at: the slot at a byte position, as an instruction.

    slot_at([149, 0, 0, 0, 0, 0, 0, 0], 0).code #=> 149
"""
def slot_at(bytes, at)
  regs = bytes[at + 1]
  insn(
    bytes[at],
    bit_and(regs, 15),
    shift_right(regs, 4),
    bytes_int(bytes, at + 2, 2, :little, true),
    bytes_int(bytes, at + 4, 4, :little, true)
  )
end

@doc """
decode: instructions from their bytes, `imm64`'s two slots read as one. A length that is no whole number of slots raises :decode_error.

    decode([]) #=> []
    decode([149, 0, 0, 0, 0, 0, 0, 0])[0][:code] #=> 149
    (decode([149]) rescue :refused) #=> :refused
"""
def decode(bytes)
  if length(bytes) % 8 != 0
    raise(
      :decode_error,
      "#{to_s(length(bytes))} bytes are not whole 8-byte slots"
    )
  end
  count = floor(length(bytes) / 8)
  acc = {at: 0, out: []}
  while(acc[:at] < count, set!(acc, decode_slot(bytes, count, acc)))
  acc[:out]
end

@doc """
decode_slot: one step of `decode`: the next instruction, and where the one after starts.

    decode_slot([149, 0, 0, 0, 0, 0, 0, 0], 1, {at: 0, out: []}).at #=> 1
"""
def decode_slot(bytes, count, acc)
  at = acc[:at]
  i = slot_at(bytes, at * 8)
  if i[:code] == 24
    if at + 1 >= count
      raise(:decode_error, "an imm64 at slot #{to_s(at)} has no second slot")
    end
    high = slot_at(bytes, (at + 1) * 8)
    wide = assoc(
      assoc(i, :imm, bit_and(i[:imm], 4_294_967_295)),
      :imm2,
      bit_and(high[:imm], 4_294_967_295)
    )
    {at: at + 2, out: append(acc[:out], [wide])}
  else
    {at: at + 1, out: append(acc[:out], [i])}
  end
end

@doc """
class_of: an opcode's class.

    class_of(183) #=> 7
"""
def class_of(code)
  bit_and(code, 7)
end

@doc """
source_reg?: whether an opcode takes a register as its source.

    source_reg?(191) #=> true
    source_reg?(183) #=> false
"""
def source_reg?(code)
  bit_and(code, 8) != 0
end

@doc """
named_of: the name a table gives a number.

    named_of([[:a, 1]], 1) #=> :a
"""
def named_of(rows, value)
  row = find(rows, (x) -> x[1] == value)
  if row.nil?
    nil
  else
    first(row)
  end
end

@doc """
alu_op_of: the operation an ALU instruction performs, its offset field read.

    alu_op_of(alu(:sdiv, 1, 2)) #=> :sdiv
"""
def alu_op_of(i)
  base = bit_and(i[:code], 240)
  if base == 48 and i[:off] == 1
    :sdiv
  elsif base == 144 and i[:off] == 1
    :smod
  elsif base == 176 and i[:off] == 8
    :movsx8
  elsif base == 176 and i[:off] == 16
    :movsx16
  elsif base == 176 and i[:off] == 32
    :movsx32
  else
    named_of(alu_ops, base)
  end
end

@doc """
alu_sign: the assignment operator LLVM writes for an ALU operation.

    alu_sign(:add) #=> "+="
"""
def alu_sign(op)
  get(
    {
      add: "+=",
      sub: "-=",
      mul: "*=",
      div: "/=",
      or: "|=",
      and: "&=",
      lsh: "<<=",
      rsh: ">>=",
      mod: "%=",
      xor: "^=",
      arsh: "s>>=",
      sdiv: "s/=",
      smod: "s%="
    },
    op
  )
end

@doc """
jump_sign: the comparison LLVM writes for a jump condition.

    jump_sign(:ne) #=> "!="
"""
def jump_sign(op)
  get(
    {
      eq: "==",
      gt: ">",
      ge: ">=",
      set: "&",
      ne: "!=",
      sgt: "s>",
      sge: "s>=",
      lt: "<",
      le: "<=",
      slt: "s<",
      sle: "s<="
    },
    op
  )
end

@doc """
signed_text: an offset as LLVM writes it inside a memory operand.

    signed_text(-4) #=> "- 4"
    signed_text(4) #=> "+ 4"
"""
def signed_text(n)
  if n < 0
    "- #{to_s(-n)}"
  else
    "+ #{to_s(n)}"
  end
end

@doc """
relative_text: a jump's offset as LLVM writes it.

    relative_text(3) #=> "+3"
    relative_text(-3) #=> "-3"
"""
def relative_text(n)
  if n < 0
    to_s(n)
  else
    "+#{to_s(n)}"
  end
end

@doc """
access_name: the C type LLVM writes for an opcode's access size.

    access_name(16) #=> "u8"
"""
def access_name(code)
  case bit_and(code, 24)
  when 0
    "u32"
  when 8
    "u16"
  when 16
    "u8"
  else
    "u64"
  end
end

@doc """
access_bytes: the bytes an opcode's access size takes.

    access_bytes(16) #=> 1
"""
def access_bytes(code)
  case bit_and(code, 24)
  when 0
    4
  when 8
    2
  when 16
    1
  else
    8
  end
end

@doc """
alu_text: an ALU instruction as LLVM writes it.

    alu_text(alu(:mov, 0, 1)) #=> "r0 = 1"
"""
def alu_text(i)
  wide = class_of(i[:code]) == 7
  letter = if wide
    "r"
  else
    "w"
  end
  dst = "#{letter}#{to_s(i[:dst])}"
  operand = if source_reg?(i[:code])
    "#{letter}#{to_s(i[:src])}"
  else
    to_s(i[:imm])
  end
  op = alu_op_of(i)
  base = bit_and(i[:code], 240)
  if base == 128
    "#{dst} = -#{dst}"
  elsif base == 208
    if wide
      "#{dst} = bswap#{to_s(i[:imm])} #{dst}"
    elsif source_reg?(i[:code])
      "r#{to_s(i[:dst])} = be#{to_s(i[:imm])} r#{to_s(i[:dst])}"
    else
      "r#{to_s(i[:dst])} = le#{to_s(i[:imm])} r#{to_s(i[:dst])}"
    end
  elsif op == :mov
    "#{dst} = #{operand}"
  elsif member?(op, %i[movsx8 movsx16 movsx32])
    "#{dst} = (s#{to_s(i[:off])})#{operand}"
  else
    "#{dst} #{alu_sign(op)} #{operand}"
  end
end

@doc """
jump_text: a jump, call or exit as LLVM writes it.

    jump_text(exit_program) #=> "exit"
"""
def jump_text(i)
  wide = class_of(i[:code]) == 5
  letter = if wide
    "r"
  else
    "w"
  end
  base = bit_and(i[:code], 240)
  if base == 0 and wide
    "goto #{relative_text(i[:off])}"
  elsif base == 0
    "gotol #{relative_text(i[:imm])}"
  elsif base == 128
    "call #{to_s(i[:imm])}"
  elsif base == 144
    "exit"
  else
    operand = if source_reg?(i[:code])
      "#{letter}#{to_s(i[:src])}"
    else
      to_s(i[:imm])
    end
    "if #{letter}#{to_s(i[:dst])} #{jump_sign(named_of(jump_ops, base))} #{operand} goto #{relative_text(i[:off])}"
  end
end

@doc """
atomic_text: an atomic instruction as LLVM writes it.

    atomic_text(atomic(:add, :dw, 1, 0, 2)) #=> "lock *(u64 *)(r1 + 0) += r2"
"""
def atomic_text(i)
  wide = bit_and(i[:code], 24) == 24
  letter = if wide
    "r"
  else
    "w"
  end
  place = "(r#{to_s(i[:dst])} #{signed_text(i[:off])})"
  kind = access_name(i[:code])
  value = "#{letter}#{to_s(i[:src])}"
  op = named_of(atomic_ops, i[:imm])
  if member?(op, %i[add or and xor])
    sign = get({add: "+=", or: "|=", and: "&=", xor: "^="}, op)
    "lock *(#{kind} *)#{place} #{sign} #{value}"
  elsif member?(op, %i[fetch_add fetch_or fetch_and fetch_xor])
    "#{value} = atomic_#{to_s(op)}((#{kind} *)#{place}, #{value})"
  elsif op == :xchg and wide
    "#{value} = xchg_64(r#{to_s(i[:dst])} #{signed_text(i[:off])}, #{value})"
  elsif op == :xchg
    "#{value} = xchg32_32(r#{to_s(i[:dst])} #{signed_text(i[:off])}, #{value})"
  elsif wide
    "r0 = cmpxchg_64(r#{to_s(i[:dst])} #{signed_text(i[:off])}, r0, #{value})"
  else
    "w0 = cmpxchg32_32(r#{to_s(i[:dst])} #{signed_text(i[:off])}, w0, #{value})"
  end
end

@doc """
text: an instruction as `llvm-mc` writes BPF assembly, which is how the encoder is checked against LLVM.

    text(alu(:add, 1, r(2))) #=> "r1 += r2"
    text(alu32(:mov, 1, 5)) #=> "w1 = 5"
    text(load(:b, 1, 2, 4)) #=> "r1 = *(u8 *)(r2 + 4)"
    text(store(:w, 10, -4, r(1))) #=> "*(u32 *)(r10 - 4) = r1"
    text(exit_program) #=> "exit"
"""
def text(given)
  i = resolved(given, {}, 0)
  cls = class_of(i[:code])
  place = "(r#{to_s(i[:src])} #{signed_text(i[:off])})"
  target = "(r#{to_s(i[:dst])} #{signed_text(i[:off])})"
  if member?(cls, [4, 7])
    alu_text(i)
  elsif member?(cls, [5, 6])
    jump_text(i)
  elsif i[:code] == 24
    "r#{to_s(i[:dst])} = #{to_s(bit_or(i[:imm], shift_left(i[:imm2], 32)))} ll"
  elsif cls == 1 and bit_and(i[:code], 224) == 128
    signed = replace(access_name(i[:code]), "u", "s")
    "r#{to_s(i[:dst])} = *(#{signed} *)#{place}"
  elsif cls == 1
    "r#{to_s(i[:dst])} = *(#{access_name(i[:code])} *)#{place}"
  elsif cls == 3 and bit_and(i[:code], 224) == 192
    atomic_text(i)
  elsif cls == 3
    "*(#{access_name(i[:code])} *)#{target} = r#{to_s(i[:src])}"
  elsif cls == 2
    "*(#{access_name(i[:code])} *)#{target} = #{to_s(i[:imm])}"
  elsif bit_and(i[:code], 224) == 32
    "r0 = #{sized_word(i[:code])} skb[#{to_s(i[:imm])}]"
  elsif bit_and(i[:code], 224) == 64
    "r0 = #{sized_word(i[:code])} skb[r#{to_s(i[:src])} + #{to_s(i[:imm])}]"
  else
    raise(:decode_error, "no text for opcode #{to_s(i[:code])}")
  end
end

@doc """
sized_word: the cast LLVM writes for a legacy packet read.

    sized_word(16) #=> "*(u8 *)"
"""
def sized_word(code)
  "*(#{access_name(code)} *)"
end

@doc """
disassemble: a program's bytes as lines of `text`.

    disassemble(encode(assemble([alu(:mov, 0, 1), exit_program]))) #=> ["r0 = 1", "exit"]
"""
def disassemble(bytes)
  map(text, decode(bytes))
end

# ── the machine ───────────────────────────────────────────────────────────

@doc """
mask32: the low 32 bits set.

    mask32 #=> 4294967295
"""
def mask32()
  4_294_967_295
end

@doc """
low32: a value's low 32 bits, as an unsigned number.

    low32(-1) #=> 4294967295
"""
def low32(v)
  bit_and(v, mask32)
end

@doc """
sign32: a value's low 32 bits, read as signed.

    sign32(4294967295) #=> -1
"""
def sign32(v)
  shift_right(shift_left(v, 32), 32)
end

@doc """
sign_from: a value's low bits, read as signed.

    sign_from(255, 8) #=> -1
"""
def sign_from(v, bits)
  shift_right(shift_left(v, 64 - bits), 64 - bits)
end

@doc """
signed_div: the quotient RFC 9669 states for `sdiv`, truncating, zero for a zero divisor.

    signed_div(-7, 2) #=> -3
    signed_div(7, 0) #=> 0
"""
def signed_div(a, b)
  if b == 0
    0
  elsif b == -1
    wrapping_sub(0, a)
  else
    q = unsigned_div(magnitude(a), magnitude(b))
    if a < 0 != (b < 0)
      wrapping_sub(0, q)
    else
      q
    end
  end
end

@doc """
magnitude: a value's distance from zero, the most negative value itself.

    magnitude(-7) #=> 7
"""
def magnitude(a)
  wrapping_sub(bit_xor(a, shift_right(a, 63)), shift_right(a, 63))
end

@doc """
signed_mod: the remainder RFC 9669 states for `smod`, taking the dividend's sign.

    signed_mod(-7, 3) #=> -1
    signed_mod(7, 0) #=> 7
"""
def signed_mod(a, b)
  if b == 0
    a
  elsif b == -1
    0
  else
    m = unsigned_mod(magnitude(a), magnitude(b))
    if a < 0
      wrapping_sub(0, m)
    else
      m
    end
  end
end

@doc """
alu64_value: what a 64-bit ALU operation answers.

    alu64_value(:add, 1, 2) #=> 3
"""
def alu64_value(op, a, b)
  case op
  when :add
    wrapping_add(a, b)
  when :sub
    wrapping_sub(a, b)
  when :mul
    wrapping_mul(a, b)
  when :div
    if b == 0
      0
    else
      unsigned_div(a, b)
    end
  when :or
    bit_or(a, b)
  when :and
    bit_and(a, b)
  when :lsh
    shift_left(a, bit_and(b, 63))
  when :rsh
    shift_right_logical(a, bit_and(b, 63))
  when :mod
    if b == 0
      a
    else
      unsigned_mod(a, b)
    end
  when :xor
    bit_xor(a, b)
  when :mov
    b
  when :arsh
    shift_right(a, bit_and(b, 63))
  when :sdiv
    signed_div(a, b)
  when :smod
    signed_mod(a, b)
  when :movsx8
    sign_from(b, 8)
  when :movsx16
    sign_from(b, 16)
  when :movsx32
    sign_from(b, 32)
  else
    raise(:bpf_fault, "no ALU operation #{to_s(op)}")
  end
end

@doc """
alu32_value: what a 32-bit ALU operation answers, its upper half clear.

    alu32_value(:add, 4294967295, 1) #=> 0
"""
def alu32_value(op, a, b)
  x = low32(a)
  y = low32(b)
  case op
  when :lsh
    low32(shift_left(x, bit_and(y, 31)))
  when :rsh
    shift_right_logical(x, bit_and(y, 31))
  when :arsh
    low32(shift_right(sign32(x), bit_and(y, 31)))
  when :sdiv
    low32(signed_div(sign32(x), sign32(y)))
  when :smod
    low32(signed_mod(sign32(x), sign32(y)))
  when :movsx8
    low32(sign_from(y, 8))
  when :movsx16
    low32(sign_from(y, 16))
  when :movsx32
    y
  else
    low32(alu64_value(op, x, y))
  end
end

@doc """
byte_swapped: a value's low bytes in reverse order.

    byte_swapped(258, 16) #=> 513
"""
def byte_swapped(v, bits)
  count = floor(bits / 8)
  reduce(
    fn(acc, i)
      bit_or(shift_left(acc, 8), bit_and(shift_right_logical(v, i * 8), 255))
    end,
    0,
    range(0, count)
  )
end

@doc """
truncated: a value's low bits.

    truncated(65537, 16) #=> 1
"""
def truncated(v, bits)
  if bits == 64
    v
  else
    bit_and(v, shift_left(1, bits) - 1)
  end
end

@doc """
jump_taken?: whether a jump condition holds.

    jump_taken?(:eq, 1, 1) #=> true
    jump_taken?(:lt, -1, 1) #=> false
"""
def jump_taken?(op, a, b)
  case op
  when :eq
    a == b
  when :ne
    a != b
  when :gt
    unsigned_less?(b, a)
  when :ge
    not unsigned_less?(a, b)
  when :lt
    unsigned_less?(a, b)
  when :le
    not unsigned_less?(b, a)
  when :sgt
    a > b
  when :sge
    a >= b
  when :slt
    a < b
  when :sle
    a <= b
  when :set
    bit_and(a, b) != 0
  else
    raise(:bpf_fault, "no jump condition #{to_s(op)}")
  end
end

@doc """
stack_top: the address the machine's frame pointer starts at.

    stack_top #=> 1879048192
"""
def stack_top()
  1_879_048_192
end

@doc """
ctx_base: the address the machine holds a program's context at.

    ctx_base #=> 268435456
"""
def ctx_base()
  268_435_456
end

@doc """
packet_base: the address the machine's packet region starts at.

    packet_base #=> 536870912
"""
def packet_base()
  536_870_912
end

@doc """
map_base: the address the machine's map values start at.

    map_base #=> 1073741824
"""
def map_base()
  1_073_741_824
end

@doc """
in_region?: whether a machine's memory holds these bytes.

    in_region?(machine(assemble([])), stack_top - 1, 1) #=> true
    in_region?(machine(assemble([])), 4, 1) #=> false
"""
def in_region?(st, addr, count)
  any?(
    (region) -> addr >= region[:from] and addr + count <= region[:to],
    st[:regions]
  )
end

@doc """
read_mem: an integer from a machine's memory, a fault outside every region.

    read_mem(write_mem(machine(assemble([])), stack_top - 8, 4, 7), stack_top - 8, 4) #=> 7
"""
def read_mem(st, addr, count)
  if not in_region?(st, addr, count)
    raise(
      :bpf_fault,
      "a read of #{to_s(count)} bytes at #{to_s(addr)} is outside every region"
    )
  end
  reduce(
    fn(acc, i)
      bit_or(shift_left(acc, 8), get(st[:mem], addr + count - 1 - i) or 0)
    end,
    0,
    range(0, count)
  )
end

@doc """
write_mem: an integer into a machine's memory, a fault outside every region.

    read_mem(write_mem(machine(assemble([])), stack_top - 1, 1, 9), stack_top - 1, 1) #=> 9
"""
def write_mem(st, addr, count, value)
  if not in_region?(st, addr, count)
    raise(
      :bpf_fault,
      "a write of #{to_s(count)} bytes at #{to_s(addr)} is outside every region"
    )
  end
  written = reduce(
    fn(mem, i)
      assoc(mem, addr + i, bit_and(shift_right_logical(value, i * 8), 255))
    end,
    st[:mem],
    range(0, count)
  )
  assoc(st, :mem, written)
end

@doc """
write_bytes_at: bytes into a machine's memory.

    read_bytes_at(write_bytes_at(machine(assemble([])), stack_top - 2, [1, 2]), stack_top - 2, 2) #=> [1, 2]
"""
def write_bytes_at(st, addr, bytes)
  reduce(
    (acc, pair) -> write_mem(acc, addr + first(pair), 1, pair[1]),
    st,
    zip(range(0, length(bytes)), bytes)
  )
end

@doc """
read_bytes_at: bytes from a machine's memory.

    read_bytes_at(machine(assemble([])), stack_top - 1, 1) #=> [0]
"""
def read_bytes_at(st, addr, count)
  map((i) -> read_mem(st, addr + i, 1), range(0, count))
end

@doc """
add_region: a machine with one more range of addresses it may touch.

    in_region?(add_region(machine(assemble([])), 4096, 8), 4096, 8) #=> true
"""
def add_region(st, from, count)
  assoc(st, :regions, append(st[:regions], [{from:, to: from + count}]))
end

@doc """
reg_value: a register's value in a machine.

    reg_value(machine(assemble([])), 10) #=> 1879048192
"""
def reg_value(st, n)
  get(st, n) or 0
end

@doc """
operand_of: an instruction's source: a register's value or its immediate.

    operand_of(machine(assemble([])), alu(:mov, 0, 5)) #=> 5
"""
def operand_of(st, i)
  if source_reg?(i[:code])
    reg_value(st, i[:src])
  else
    i[:imm]
  end
end

@doc """
advance: a machine with its program counter moved on.

    advance(machine(assemble([])), 2)[:pc] #=> 2
"""
def advance(st, n)
  assoc(st, :pc, st[:pc] + n)
end

@doc """
exec_alu: a machine after one ALU instruction.

    reg_value(exec_alu(machine(assemble([])), alu(:mov, 0, 5)), 0) #=> 5
"""
def exec_alu(st, i)
  base = bit_and(i[:code], 240)
  wide = class_of(i[:code]) == 7
  dst = reg_value(st, i[:dst])
  value = if base == 128
    if wide
      wrapping_sub(0, dst)
    else
      low32(wrapping_sub(0, low32(dst)))
    end
  elsif base == 208
    bits = i[:imm]
    if wide or source_reg?(i[:code])
      byte_swapped(dst, bits)
    else
      truncated(dst, bits)
    end
  elsif wide
    alu64_value(alu_op_of(i), dst, operand_of(st, i))
  else
    alu32_value(alu_op_of(i), dst, operand_of(st, i))
  end
  advance(assoc(st, i[:dst], value), 1)
end

@doc """
exec_jump: a machine after one jump, call or exit.

    exec_jump(machine(assemble([])), insn(5, 0, 0, 2, 0))[:pc] #=> 3
"""
def exec_jump(st, i)
  base = bit_and(i[:code], 240)
  wide = class_of(i[:code]) == 5
  if base == 0 and wide
    advance(st, 1 + i[:off])
  elsif base == 0
    advance(st, 1 + i[:imm])
  elsif base == 128
    exec_call(st, i)
  elsif base == 144
    exec_exit(st)
  else
    a = reg_value(st, i[:dst])
    b = operand_of(st, i)
    op = named_of(jump_ops, base)
    taken = if wide
      jump_taken?(op, a, b)
    else
      jump_taken?(op, low32_for(op, a), low32_for(op, b))
    end
    if taken
      advance(st, 1 + i[:off])
    else
      advance(st, 1)
    end
  end
end

@doc """
low32_for: a 32-bit jump's operand, signed when its condition is.

    low32_for(:slt, 4294967295) #=> -1
    low32_for(:lt, -1) #=> 4294967295
"""
def low32_for(op, v)
  if member?(op, %i[sgt sge slt sle])
    sign32(v)
  else
    low32(v)
  end
end

@doc """
exec_load: a machine after one load.

    reg_value(exec_load(write_mem(machine(assemble([])), stack_top - 8, 8, 9), load(:dw, 0, 10, -8)), 0) #=> 9
"""
def exec_load(st, i)
  count = access_bytes(i[:code])
  addr = wrapping_add(reg_value(st, i[:src]), i[:off])
  raw = read_mem(st, addr, count)
  value = if bit_and(i[:code], 224) == 128
    sign_from(raw, count * 8)
  else
    raw
  end
  advance(assoc(st, i[:dst], value), 1)
end

@doc """
exec_store: a machine after one store.

    read_mem(exec_store(machine(assemble([])), store(:dw, 10, -8, 9)), stack_top - 8, 8) #=> 9
"""
def exec_store(st, i)
  count = access_bytes(i[:code])
  addr = wrapping_add(reg_value(st, i[:dst]), i[:off])
  value = if class_of(i[:code]) == 2
    i[:imm]
  else
    reg_value(st, i[:src])
  end
  advance(write_mem(st, addr, count, value), 1)
end

@doc """
exec_atomic: a machine after one atomic instruction.

    read_mem(exec_atomic(write_mem(assoc(machine(assemble([])), 1, 4), stack_top - 8, 8, 9), atomic(:add, :dw, 10, -8, 1)), stack_top - 8, 8) #=> 13
"""
def exec_atomic(st, i)
  count = access_bytes(i[:code])
  addr = wrapping_add(reg_value(st, i[:dst]), i[:off])
  old = read_mem(st, addr, count)
  src = reg_value(st, i[:src])
  small = count == 4
  op = named_of(atomic_ops, i[:imm])
  combine = fn(kind)
    v = alu64_value(kind, old, src)
    if small
      low32(v)
    else
      v
    end
  end
  case op
  when :cmpxchg
    expected = if small
      low32(reg_value(st, 0))
    else
      reg_value(st, 0)
    end
    stored = if old == expected
      write_mem(st, addr, count, src)
    else
      st
    end
    advance(assoc(stored, 0, old), 1)
  when :xchg
    advance(assoc(write_mem(st, addr, count, src), i[:src], old), 1)
  else
    fetch = member?(op, %i[fetch_add fetch_or fetch_and fetch_xor])
    kind = get(
      {
        add: :add,
        or: :or,
        and: :and,
        xor: :xor,
        fetch_add: :add,
        fetch_or: :or,
        fetch_and: :and,
        fetch_xor: :xor
      },
      op
    )
    written = write_mem(st, addr, count, combine(kind))
    if fetch
      advance(assoc(written, i[:src], old), 1)
    else
      advance(written, 1)
    end
  end
end

@doc """
exec_exit: a machine after an exit: done at the top frame, back in its caller otherwise.

    exec_exit(machine(assemble([])))[:done] #=> true
"""
def exec_exit(st)
  if st[:frames] == []
    assoc(st, :done, true)
  else
    frame = first(st[:frames])
    restored = reduce(
      (acc, n) -> assoc(acc, n, get(frame[:saved], n)),
      st,
      [6, 7, 8, 9, 10]
    )
    assoc(assoc(restored, :frames, rest(st[:frames])), :pc, frame[:back])
  end
end

@doc """
exec_call: a machine after one call: a subprogram entered, or a helper answered and r1 to r5 cleared.

    reg_value(exec_call(machine(assemble([])), call(:get_smp_processor_id)), 0) #=> 0
"""
def exec_call(st, i)
  if i[:src] == 1
    if size(st[:frames]) >= 8
      raise(:bpf_fault, "calls nest past eight frames")
    end
    depth = size(st[:frames]) + 1
    top = stack_top - depth * 512
    saved = reduce(
      (acc, n) -> assoc(acc, n, reg_value(st, n)),
      {},
      [6, 7, 8, 9, 10]
    )
    entered = assoc(add_region(st, top - 512, 512), 10, top)
    framed = assoc(
      entered,
      :frames,
      append([{back: st[:pc] + 1, saved:}], st[:frames])
    )
    assoc(framed, :pc, st[:pc] + 1 + i[:imm])
  elsif i[:src] == 2
    raise(:bpf_fault, "the model has no kernel function #{to_s(i[:imm])}")
  else
    after = model_helper(st, helper_names[i[:imm]])
    clobbered = reduce((acc, n) -> assoc(acc, n, 0), after, [1, 2, 3, 4, 5])
    advance(clobbered, 1)
  end
end

@doc """
arg: a helper's argument, by its register.

    arg(machine(assemble([])), 10) #=> 1879048192
"""
def arg(st, n)
  reg_value(st, n)
end

@doc """
map_of: the map a machine holds under a handle, a fault when it holds none.

    map_of(run(assemble([alu(:mov, 0, 0), exit_program]), {maps: [declare_map(:m, :array, 4, 8, 1)]}), 1)[:name] #=> :m
"""
def map_of(st, handle)
  found = find(st[:map_list], (m) -> m[:handle] == handle)
  if found.nil?
    raise(:bpf_fault, "no map with handle #{to_s(handle)}")
  end
  found
end

@doc """
key_text: a map key's bytes as the text the machine indexes by.

    key_text([1, 2]) #=> "1,2"
"""
def key_text(bytes)
  join(map(to_s, bytes), ",")
end

@doc """
array_kind?: whether a map holds a slot for every index.

    array_kind?({kind: :array}) #=> true
    array_kind?({kind: :hash}) #=> false
"""
def array_kind?(m)
  member?(m[:kind], %i[array percpu_array])
end

@doc """
value_of: the address of a key's value in a machine's map, 0 when it holds none.

    value_of(machine(assemble([])), {handle: 1, kind: :hash}, [1]) #=> 0
"""
def value_of(st, m, key)
  if array_kind?(m)
    index = bytes_int(key, 0, 4)
    if index < m[:max_entries]
      m[:base] + index * m[:value_size]
    else
      0
    end
  else
    get(get(st[:map_entries], m[:handle]) or {}, key_text(key)) or 0
  end
end

@doc """
helper_lookup: the machine's `map_lookup_elem`.

    with_map("(or (bpf/map_get %root/M 1) 5)") #=> 5
"""
def helper_lookup(st)
  m = map_of(st, arg(st, 1))
  key = read_bytes_at(st, arg(st, 2), m[:key_size])
  assoc(st, 0, value_of(st, m, key))
end

@doc """
fresh_value: a new place for a map value, and the machine that holds it.

    fresh_value(machine(assemble([])), {value_size: 8})[:at] #=> 1073741824
"""
def fresh_value(st, m)
  at = st[:next_value]
  ready = assoc(
    add_region(st, at, m[:value_size]),
    :next_value,
    at + m[:value_size] + 8
  )
  {at:, st: ready}
end

@doc """
helper_update: the machine's `map_update_elem`.

    with_map("(begin (bpf/map_put %root/M 1 41) (or (bpf/map_get %root/M 1) 0))") #=> 41
"""
def helper_update(st)
  m = map_of(st, arg(st, 1))
  key = read_bytes_at(st, arg(st, 2), m[:key_size])
  value = read_bytes_at(st, arg(st, 3), m[:value_size])
  found = value_of(st, m, key)
  if array_kind?(m) and found == 0
    assoc(st, 0, -7)
  elsif found != 0
    assoc(write_bytes_at(st, found, value), 0, 0)
  else
    entries = get(st[:map_entries], m[:handle]) or {}
    if size_of_keys(st, m) >= m[:max_entries]
      assoc(st, 0, -7)
    else
      placed = fresh_value(st, m)
      with_value = write_bytes_at(placed[:st], placed[:at], value)
      kept = assoc(
        with_value,
        :map_entries,
        assoc(
          with_value[:map_entries],
          m[:handle],
          assoc(entries, key_text(key), placed[:at])
        )
      )
      assoc(
        assoc(
          kept,
          :map_counts,
          assoc(kept[:map_counts], m[:handle], size_of_keys(kept, m) + 1)
        ),
        0,
        0
      )
    end
  end
end

@doc """
size_of_keys: how many keys a machine's map holds.

    size_of_keys(machine(assemble([])), {handle: 1}) #=> 0
"""
def size_of_keys(st, m)
  get(st[:map_counts], m[:handle]) or 0
end

@doc """
helper_delete: the machine's `map_delete_elem`.

    with_map("(if (bpf/map_delete %root/M 1) 1 0)") #=> 0
"""
def helper_delete(st)
  m = map_of(st, arg(st, 1))
  key = read_bytes_at(st, arg(st, 2), m[:key_size])
  if array_kind?(m)
    assoc(st, 0, -22)
  elsif value_of(st, m, key) == 0
    assoc(st, 0, -2)
  else
    entries = get(st[:map_entries], m[:handle])
    gone = assoc(
      st,
      :map_entries,
      assoc(st[:map_entries], m[:handle], dissoc(entries, key_text(key)))
    )
    assoc(
      assoc(
        gone,
        :map_counts,
        assoc(gone[:map_counts], m[:handle], size_of_keys(gone, m) - 1)
      ),
      0,
      0
    )
  end
end

@doc """
next_random: the machine's `get_prandom_u32`, drawn from its seed so a run repeats.

    reg_value(next_random(machine(assemble([]), {seed: 1})), 0) #=> 1103527590
"""
def next_random(st)
  value = bit_and(
    wrapping_add(wrapping_mul(st[:seed], 1_103_515_245), 12345),
    mask32
  )
  assoc(assoc(st, :seed, value), 0, value)
end

@doc """
adjust_head: the machine's `xdp_adjust_head`.

    packet_of(adjust_head(assoc(machine(assemble([]), {packet: [1, 2]}), 2, 1))) #=> [2]
"""
def adjust_head(st)
  delta = sign32(arg(st, 2))
  data = read_mem(st, ctx_base, 4) + delta
  if data < packet_base or data >= read_mem(st, ctx_base + 4, 4)
    assoc(st, 0, -22)
  else
    assoc(
      write_mem(write_mem(st, ctx_base, 4, data), ctx_base + 8, 4, data),
      0,
      0
    )
  end
end

@doc """
ring_output: the machine's `ringbuf_output`.

    st = write_mem(machine(assemble([])), stack_top - 1, 1, 7)
    ring_output(assoc(assoc(st, 2, stack_top - 1), 3, 1))[:events] #=> [[7]]
"""
def ring_output(st)
  bytes = read_bytes_at(st, arg(st, 2), arg(st, 3))
  assoc(assoc(st, :events, append(st[:events], [bytes])), 0, 0)
end

@doc """
ring_reserve: the machine's `ringbuf_reserve`.

    reg_value(ring_reserve(assoc(machine(assemble([])), 2, 8)), 0) #=> 1073741824
"""
def ring_reserve(st)
  count = arg(st, 2)
  at = st[:next_value]
  ready = assoc(add_region(st, at, count), :next_value, at + count + 8)
  reserved = assoc(ready, :reserved, assoc(ready[:reserved], at, count))
  assoc(reserved, 0, at)
end

@doc """
ring_submit: the machine's `ringbuf_submit`.

    st = ring_reserve(assoc(machine(assemble([])), 2, 1))
    ring_submit(assoc(st, 1, reg_value(st, 0)))[:events] #=> [[0]]
"""
def ring_submit(st)
  at = arg(st, 1)
  count = get(st[:reserved], at)
  if count.nil?
    raise(:bpf_fault, "a submit of an address no reserve gave")
  end
  assoc(
    assoc(st, :events, append(st[:events], [read_bytes_at(st, at, count)])),
    0,
    0
  )
end

@doc """
read_kernel: the machine's `probe_read_kernel`, -14 for an address it does not hold.

    st = assoc(assoc(assoc(machine(assemble([])), 1, stack_top - 8), 2, 8), 3, 99)
    reg_value(read_kernel(st), 0) #=> -14
"""
def read_kernel(st)
  count = arg(st, 2)
  if in_region?(st, arg(st, 3), count)
    bytes = read_bytes_at(st, arg(st, 3), count)
    assoc(write_bytes_at(st, arg(st, 1), bytes), 0, 0)
  else
    assoc(
      write_bytes_at(st, arg(st, 1), map((_i) -> 0, range(0, count))),
      0,
      -14
    )
  end
end

@doc """
model_helper: the machine after one helper, a fault for a helper it does not model.

    reg_value(model_helper(machine(assemble([])), :get_smp_processor_id), 0) #=> 0
    (model_helper(machine(assemble([])), :loop) rescue :refused) #=> :refused
"""
def model_helper(st, name)
  case name
  when :map_lookup_elem
    helper_lookup(st)
  when :map_update_elem
    helper_update(st)
  when :map_delete_elem
    helper_delete(st)
  when :ktime_get_ns
    assoc(st, 0, st[:now_ns])
  when :trace_printk
    assoc(st, 0, 0)
  when :get_prandom_u32
    next_random(st)
  when :get_smp_processor_id
    assoc(st, 0, 0)
  when :get_current_pid_tgid
    assoc(st, 0, st[:pid_tgid])
  when :get_current_uid_gid
    assoc(st, 0, st[:uid_gid])
  when :xdp_adjust_head
    adjust_head(st)
  when :probe_read_kernel
    read_kernel(st)
  when :get_current_task
    assoc(st, 0, st[:current_task])
  when :ringbuf_output
    ring_output(st)
  when :ringbuf_reserve
    ring_reserve(st)
  when :ringbuf_submit
    ring_submit(st)
  when :ringbuf_discard
    assoc(st, 0, 0)
  else
    raise(:bpf_fault, "the model has no helper #{to_s(name)}")
  end
end

@doc """
step: a machine after its next instruction.

    step(machine(assemble([alu(:mov, 0, 1)])), slot_table([alu(:mov, 0, 1)]))[:pc] #=> 1
"""
def step(st, by_slot)
  i = get(by_slot, st[:pc])
  if i.nil?
    raise(:bpf_fault, "the program counter #{to_s(st[:pc])} left the program")
  end
  cls = class_of(i[:code])
  if cls == 7 or cls == 4
    exec_alu(st, i)
  elsif cls == 5 or cls == 6
    exec_jump(st, i)
  elsif cls == 1
    exec_load(st, i)
  elsif cls == 2
    exec_store(st, i)
  elsif cls == 3 and bit_and(i[:code], 224) == 192
    exec_atomic(st, i)
  elsif cls == 3
    exec_store(st, i)
  elsif i[:code] == 24
    advance(assoc(st, i[:dst], bit_or(i[:imm], shift_left(i[:imm2], 32))), 2)
  else
    raise(:bpf_fault, "the model does not run opcode #{to_s(i[:code])}")
  end
end

@doc """
slot_table: each instruction by the slot it starts at.

    get(slot_table([imm64(1, 5), exit_program]), 2)[:code] #=> 149
"""
def slot_table(insns)
  get(
    reduce(
      fn(acc, i)
        {at: acc[:at] + slots_of(i), table: assoc(acc[:table], acc[:at], i)}
      end,
      {at: 0, table: {}},
      insns
    ),
    :table
  )
end

@doc """
skb_kinds: the program types whose context is a `__sk_buff`.

    member?(:cgroup_skb, skb_kinds) #=> true
    member?(:xdp, skb_kinds) #=> false
"""
def skb_kinds()
  %i[socket_filter sched_cls sched_act cgroup_skb lwt_in lwt_out lwt_xmit]
end

@doc """
network_layer?: whether the kernel hands this program type a packet from its network header: its Ethernet header is pulled first, so a program sees 14 bytes less and an IPv4 header at offset 0.

    network_layer?(:cgroup_skb) #=> true
    network_layer?(:sched_cls) #=> false
    network_layer?(:xdp) #=> false
"""
def network_layer?(kind)
  member?(kind, skb_kinds) and not member?(kind, %i[sched_cls sched_act])
end

@doc """
packet_view: the bytes of a frame that a program of this type sees.

    packet_view(:xdp, [1, 2]) #=> [1, 2]
    size(packet_view(:lwt_in, repeat(0, 20))) #=> 6
    packet_view(:lwt_in, [1]) #=> []
"""
def packet_view(kind, frame)
  if network_layer?(kind)
    drop(14, frame)
  else
    frame
  end
end

@doc """
data_fields: where a machine holds a packet's `data` and `data_end` for this program type.

    data_fields(:xdp) #=> [0, 4]
    data_fields(:socket_filter) #=> [76, 80]
    data_fields(:flow_dissector) #=> [76, 80]
"""
def data_fields(kind)
  if member?(kind, skb_kinds) or kind == :flow_dissector
    [76, 80]
  else
    [0, 4]
  end
end

@doc """
packet_ready: a machine holding a packet behind the context its program type reads: `xdp_md` for XDP, a `__sk_buff` with its `len` and `protocol` for a socket buffer's.

    packet_of(packet_ready(machine(assemble([]), {ctx: []}), [1])) #=> [1]
    packet_of(packet_ready(machine(assemble([]), {ctx: []}), repeat(0, 15), :cgroup_skb)) #=> [0]
"""
def packet_ready(st, packet, kind?)
  held = kind or :xdp
  fields = data_fields(held)
  bytes = packet_view(held, packet or [])
  count = length(bytes)
  head = 256
  data = packet_base + head
  end_at = data + count
  placed = write_bytes_at(
    add_region(st, packet_base, head + count),
    data,
    bytes
  )
  framed = assoc(add_region(placed, ctx_base, 184), :fields, fields)
  ready = write_mem(
    write_mem(
      write_mem(framed, ctx_base + first(fields), 4, data),
      ctx_base + fields[1],
      4,
      end_at
    ),
    ctx_base + 8,
    4,
    data
  )
  assoc(skb_ready(ready, held, packet or [], count), 1, ctx_base)
end

@doc """
skb_ready: a machine whose `__sk_buff` holds the frame's length and protocol, as the kernel's test run fills them. Any other context is as it was.

    read_mem(skb_ready(add_region(machine(assemble([])), ctx_base, 184), :lwt_in, [], 7), ctx_base, 4) #=> 7
    skb_ready(machine(assemble([]))[:mem], :xdp, [], 7) == machine(assemble([]))[:mem] #=> true
"""
def skb_ready(st, kind, frame, count)
  if not member?(kind, skb_kinds)
    st
  elsif size(frame) < 14
    write_mem(st, ctx_base, 4, count)
  else
    write_bytes_at(
      write_mem(st, ctx_base, 4, count),
      ctx_base + 16,
      take(2, drop(12, frame))
    )
  end
end

@doc """
ctx_ready: a machine holding a program's context, with r1 at it.

    read_mem(ctx_ready(machine(assemble([])), [7]), ctx_base, 1) #=> 7
"""
def ctx_ready(st, ctx)
  count = length(ctx)
  placed = write_bytes_at(add_region(st, ctx_base, count), ctx_base, ctx)
  assoc(placed, 1, ctx_base)
end

@doc """
map_ready: a machine with one more map.

    first(map_ready(machine(assemble([])), declare_map(:m, :array, 4, 8, 1), 1)[:map_list])[:name] #=> :m
"""
def map_ready(st, spec, handle)
  base = st[:next_value]
  m = {
    handle:,
    name: spec[:name],
    kind: spec[:kind],
    key_size: spec[:key_size],
    value_size: spec[:value_size],
    max_entries: spec[:max_entries],
    base:
  }
  grown = if array_kind?(m)
    extent = m[:value_size] * m[:max_entries]
    assoc(add_region(st, base, extent), :next_value, base + extent + 8)
  else
    st
  end
  assoc(grown, :map_list, append(grown[:map_list], [m]))
end

@doc """
with_relocs: the slot table with each map reference holding its map's handle.

    get(with_relocs([map_ref(1, :m)], [{at: 0, map: :m}], [{name: :m}]), 0)[:imm] #=> 1
"""
def with_relocs(insns, relocs, maps)
  reduce(
    fn(acc, reloc)
      at = index_of(map((m) -> m[:name], maps), reloc[:map])
      if at < 0
        raise(
          :bad_option,
          "the program names the map #{to_s(reloc[:map])}, which is not declared"
        )
      end
      handle = at + 1
      assoc(acc, reloc[:at], assoc(get(acc, reloc[:at]), :imm, handle))
    end,
    slot_table(insns),
    relocs
  )
end

@doc """
machine: a machine ready to run a program: {packet:} gives a program the frame through the context its type reads (`{kind:}` or the program's own, XDP when neither says), {ctx:} gives any other program its context bytes, {maps:} the map specs `declare_map` makes, and {seed:, now_ns:, pid_tgid:, uid_gid:} what the helpers read.

    machine(assemble([exit_program]))[:pc] #=> 0
"""
def machine(program, input?)
  opts = input or {}
  bare = {
    pc: 0,
    mem: {},
    regions: [{from: stack_top - 512, to: stack_top}],
    frames: [],
    done: false,
    steps: 0,
    seed: opts[:seed] or 1,
    now_ns: opts[:now_ns] or 0,
    pid_tgid: opts[:pid_tgid] or 0,
    uid_gid: opts[:uid_gid] or 0,
    map_list: [],
    map_entries: {},
    map_counts: {},
    next_value: map_base,
    reserved: {},
    events: []
  }
  specs = opts[:maps] or []
  with_maps = reduce(
    (acc, pair) -> map_ready(acc, pair[1], first(pair) + 1),
    assoc(bare, 10, stack_top),
    zip(range(0, length(specs)), specs)
  )
  with_kernel = if opts[:kernel] != nil
    k = opts[:kernel]
    assoc(
      write_bytes_at(
        add_region(with_maps, k[:at], length(k[:bytes])),
        k[:at],
        k[:bytes]
      ),
      :current_task,
      k[:at]
    )
  else
    with_maps
  end
  entered = if opts[:ctx] != nil
    ctx_ready(with_kernel, opts[:ctx])
  else
    packet_ready(with_kernel, opts[:packet], opts[:kind] or program[:kind])
  end
  assoc(
    entered,
    :by_slot,
    with_relocs(program[:insns], program[:relocs], specs)
  )
end

@doc """
declare_map: a map's shape, as the machine and the kernel loader both read it.

    declare_map(:counts, :array, 4, 8, 16).value_size #=> 8
"""
def declare_map(name, kind, key_size, value_size, max_entries)
  {name:, kind:, key_size:, value_size:, max_entries:}
end

@doc """
packet_of: the packet as the machine holds it now, from its `data` pointer to its `data_end`.

    packet_of(machine(assemble([]), {packet: [1, 2]})) #=> [1, 2]
"""
def packet_of(st)
  fields = st[:fields] or [0, 4]
  from = read_mem(st, ctx_base + first(fields), 4)
  to = read_mem(st, ctx_base + fields[1], 4)
  read_bytes_at(st, from, to - from)
end

@doc """
map_value: the value bytes a machine's map holds for a key, nil when it holds none.

    map_value(run(assemble([alu(:mov, 0, 0), exit_program]), {maps: [declare_map(:m, :array, 4, 8, 1)]}), :m, [0, 0, 0, 0]) #=> [0, 0, 0, 0, 0, 0, 0, 0]
"""
def map_value(st, name, key)
  m = find(st[:map_list], (x) -> x[:name] == name)
  if m.nil?
    raise(:bad_option, "no map #{to_s(name)}")
  end
  at = value_of(st, m, key)
  if at == 0
    nil
  else
    read_bytes_at(st, at, m[:value_size])
  end
end

@doc """
run: a program to completion on a fresh machine: the machine at its end, with `ret` the value in r0. A step past `max_steps` (a million, or {max_steps:}) and a fault each raise :bpf_fault.

    run(assemble([alu(:mov, 0, 42), exit_program])).ret #=> 42
    (run(assemble([load(:b, 0, 1, 99999), exit_program])) rescue :refused) #=> :refused
"""
def run(program, input?)
  opts = input or {}
  limit = opts[:max_steps] or 1_000_000
  st = machine(program, opts)
  table = st[:by_slot]
  while(not st[:done], set!(st, tick(st, table, limit)))
  assoc(st, :ret, reg_value(st, 0))
end

@doc """
tick: one counted step of `run`, a fault past the limit.

    tick(machine(assemble([exit_program])), slot_table([exit_program]), 9)[:steps] #=> 1
"""
def tick(st, table, limit)
  if st[:steps] >= limit
    raise(:bpf_fault, "the program ran past #{to_s(limit)} steps")
  end
  assoc(step(st, table), :steps, st[:steps] + 1)
end

# ── the words a kernel program has ────────────────────────────────────────

@doc """
compiled_only: the refusal a kernel word answers when it is called in the interpreter.

    (compiled_only("w") rescue :refused) #=> :refused
"""
def compiled_only(word)
  raise(
    :bpf_fault,
    "#{word} runs inside the kernel: compile the program with bpf::compile and run it with bpf::run or kaaneru::run"
  )
end

@doc """
xdp_aborted: the XDP action that drops a packet and records a trace event.

    xdp_aborted #=> 0
"""
def xdp_aborted()
  0
end

@doc """
xdp_drop: the XDP action that drops a packet.

    xdp_drop #=> 1
"""
def xdp_drop()
  1
end

@doc """
xdp_pass: the XDP action that hands a packet to the network stack.

    xdp_pass #=> 2
"""
def xdp_pass()
  2
end

@doc """
xdp_tx: the XDP action that sends a packet back out of the interface it came in on.

    xdp_tx #=> 3
"""
def xdp_tx()
  3
end

@doc """
packet_len: inside a compiled program, the packet's length in bytes.

    (packet_len(nil) rescue :compiled) #=> :compiled
"""
def packet_len(_ctx)
  compiled_only("packet_len")
end

@doc """
packet_int: inside a compiled program, the `size`-byte integer (1, 2, 4 or 8) at an offset in the packet, in network order. An offset past the packet is a fault.

    (packet_int(nil, 0, 1) rescue :compiled) #=> :compiled
"""
def packet_int(_ctx, _off, _size)
  compiled_only("packet_int")
end

@doc """
packet_put: inside a compiled program, the `size`-byte integer written at an offset in the packet, in network order. An offset past the packet is a fault.

    (packet_put(nil, 0, 1, 7) rescue :compiled) #=> :compiled
"""
def packet_put(_ctx, _off, _size, _value)
  compiled_only("packet_put")
end

@doc """
ctx_int: inside a compiled program, the `size`-byte integer at a literal offset in the program's own context: a tracepoint's fields, a socket buffer's.

    (ctx_int(nil, 0, 4) rescue :compiled) #=> :compiled
"""
def ctx_int(_ctx, _off, _size)
  compiled_only("ctx_int")
end

@doc """
map_get: inside a compiled program, a key's value in a map, nil when the map holds none.

    (map_get(nil, 0) rescue :compiled) #=> :compiled
"""
def map_get(_m, _key)
  compiled_only("map_get")
end

@doc """
map_put: inside a compiled program, a key's value set in a map. A full map or an index past an array is a fault.

    (map_put(nil, 0, 1) rescue :compiled) #=> :compiled
"""
def map_put(_m, _key, _value)
  compiled_only("map_put")
end

@doc """
map_add: inside a compiled program, `n` added atomically to a key's value, an absent hash key starting from zero.

    (map_add(nil, 0, 1) rescue :compiled) #=> :compiled
"""
def map_add(_m, _key, _n)
  compiled_only("map_add")
end

@doc """
map_delete: inside a compiled program, a key taken out of a map: true when it was there.

    (map_delete(nil, 0) rescue :compiled) #=> :compiled
"""
def map_delete(_m, _key)
  compiled_only("map_delete")
end

@doc """
emit: inside a compiled program, a record of 64-bit values sent through a ring buffer map. A full buffer drops the record.

    (emit(nil, [1]) rescue :compiled) #=> :compiled
"""
def emit(_m, _values)
  compiled_only("emit")
end

@doc """
kernel_read: inside a compiled program, the `size`-byte field a kernel pointer's struct holds, its offset taken from the running kernel's BTF when the program loads. A failed read or a field of another size on this kernel is a fault or a refusal, never a wrong value.

    (kernel_read(0, "task_struct", ["pid"], 4) rescue :compiled) #=> :compiled
"""
def kernel_read(_pointer, _struct, _path, _size)
  compiled_only("kernel_read")
end

@doc """
helper: inside a compiled program, a kernel helper by name with integer arguments: its integer answer.

    (helper(:ktime_get_ns) rescue :compiled) #=> :compiled
"""
def helper(_name, _a?, _b?, _c?, _d?, _e?)
  compiled_only("helper")
end

# ── the compiler ──────────────────────────────────────────────────────────

@doc """
refuse: the compile error that names what this position has no lowering for.

    (refuse("no") rescue :refused) #=> :refused
"""
def refuse(what)
  raise(:bpf_compile, what)
end

@doc """
out: a compiler state with more code.

    size(out(start_state(:xdp), [exit_program])[:code]) #=> 2
"""
def out(st, items)
  update(st, :code, (code) -> append(code, items))
end

@doc """
typed: a compiler state with the type and range of the value in r0.

    typed(start_state(:xdp), :int, [1, 1])[:rng] #=> [1, 1]
"""
def typed(st, t, rng?)
  assoc(assoc(st, :t, t), :rng, rng)
end

@doc """
slot_offset: a stack slot's offset from the frame pointer.

    slot_offset(0) #=> -8
    slot_offset(1) #=> -16
"""
def slot_offset(slot)
  -(8 * (slot + 1))
end

@doc """
take_slot: a compiler state with one more stack slot, refused past the verifier's 64.

    take_slot(start_state(:xdp))[:top] #=> 1
"""
def take_slot(st)
  at = st[:top]
  if at >= 64
    refuse("the program needs more than 64 stack slots, the 512 bytes the verifier allows")
  end
  assoc(assoc(st, :top, at + 1), :high, blue::max(st[:high], at + 1))
end

@doc """
bump: a record with one count raised.

    bump({n: 1}, :n)[:n] #=> 2
"""
def bump(st, key)
  update(st, key, (n) -> n + 1)
end

@doc """
fresh: a compiler state with one more label.

    fresh(start_state(:xdp))[:labels] #=> 1
"""
def fresh(st)
  bump(st, :labels)
end

@doc """
label_name: the name of the newest label.

    label_name(start_state(:xdp)) #=> "L0"
"""
def label_name(st)
  "L#{to_s(st[:labels])}"
end

@doc """
faulting: a compiler state whose program needs its fault path.

    faulting(start_state(:xdp))[:faults] #=> true
"""
def faulting(st)
  assoc(st, :faults, true)
end

@doc """
name_of: a symbol's name.

    name_of(form_of("a")) #=> "a"
"""
def name_of(sym)
  to_s(sym)
end

@doc """
head_name: the name a form starts with, nil for anything else.

    head_name(form_of("(a 1)")) #=> "a"
    head_name(7).nil? #=> true
"""
def head_name(form)
  if list?(form) and form != [] and symbol?(first(form))
    name_of(first(form))
  end
end

@doc """
short_name: a resolved name without its package.

    short_name("%root/f") #=> "f"
"""
def short_name(qualified)
  last_part = split(qualified, "/")
  last(last_part)
end

@doc """
word_of: the word a resolved name is in this package, nil for another's.

    word_of("bpf/emit") #=> "emit"
    word_of("retsu/first").nil? #=> true
"""
def word_of(name)
  if starts_with?(name, "bpf/")
    short_name(name)
  end
end

@doc """
literal_of: the integer a form is known to be when it compiles, nil when it is not known.

    literal_of(start_state(:xdp), 7) #=> 7
    literal_of(start_state(:xdp), form_of("x")).nil? #=> true
"""
def literal_of(st, form)
  if integer?(form)
    form
  elsif symbol?(form)
    c = get(st[:consts], name_of(form))
    if integer?(c)
      c
    else
      constant_of(word_of(name_of(form)))
    end
  elsif list?(form) and size(form) == 1
    constant_of(word_of(or_empty(head_name(form))))
  elsif head_name(form) == "-" and size(form) == 2 and integer?(form[1])
    -form[1]
  end
end

@doc """
or_empty: a string, or an empty one for nil.

    or_empty(nil) #=> ""
"""
def or_empty(s)
  s or ""
end

@doc """
constant_of: the number of an action word.

    constant_of("xdp_pass") #=> 2
"""
def constant_of(word)
  case word
  when "xdp_aborted"
    0
  when "xdp_drop"
    1
  when "xdp_pass"
    2
  when "xdp_tx"
    3
  end
end

@doc """
load_constant: the instruction that puts an integer in a register.

    load_constant(0, 5).imm #=> 5
    load_constant(0, shift_left(1, 40)).code #=> 24
"""
def load_constant(reg, value)
  if value >= -2_147_483_648 and value <= 2_147_483_647
    alu(:mov, reg, value)
  else
    imm64(reg, value)
  end
end

@doc """
local_of: what the compiler holds for a local.

    local_of(env_with(start_state(:xdp), "x", {t: :int}), "x")[:t] #=> :int
"""
def local_of(st, name)
  get(st[:env], name)
end

@doc """
env_with: a compiler state with one local bound.

    local_of(env_with(start_state(:xdp), "x", {t: :bool}), "x")[:t] #=> :bool
"""
def env_with(st, name, place)
  update(st, :env, (env) -> assoc(env, name, place))
end

@doc """
value_type: the type of a local.

    value_type({t: :int}) #=> :int
"""
def value_type(place)
  place[:t]
end

@doc """
load_local: a compiler state with a local read into r0.

    load_local(start_state(:xdp), {t: :int, slot: 0}, "x")[:t] #=> :int
"""
def load_local(st, place, _name)
  case place[:t]
  when :ctx
    typed(out(st, [alu(:mov, 0, r(6))]), :ctx)
  when :maybe
    if place[:narrowed]
      typed(
        out(st, [load(:dw, 0, 10, slot_offset(place[:slot]))]),
        :int,
        place[:rng]
      )
    else
      typed(
        out(
          st,
          [
            load(:dw, 0, 10, slot_offset(place[:slot])),
            load(:dw, 1, 10, slot_offset(place[:slot] + 1))
          ]
        ),
        :maybe
      )
    end
  else
    typed(
      out(st, [load(:dw, 0, 10, slot_offset(place[:slot]))]),
      place[:t],
      place[:rng]
    )
  end
end

@doc """
gen_symbol: a name lowered to its local, constant or truth value.

    gen_symbol(start_state(:xdp), form_of("true"))[:t] #=> :bool
"""
def gen_symbol(st, form)
  name = name_of(form)
  place = local_of(st, name)
  literal = literal_of(st, form)
  if place != nil
    load_local(st, place, name)
  elsif name == "true"
    typed(out(st, [alu(:mov, 0, 1)]), :bool)
  elsif name == "false"
    typed(out(st, [alu(:mov, 0, 0)]), :bool)
  elsif literal != nil
    typed(out(st, [load_constant(0, literal)]), :int, [literal, literal])
  else
    refuse("`#{name}` is not a local, a constant or a word this position has")
  end
end

@doc """
need_int: a compiler state whose value is an integer, refused for one that may be absent.

    need_int(typed(start_state(:xdp), :int), "x")[:t] #=> :int
    (need_int(typed(start_state(:xdp), :maybe), "x") rescue :refused) #=> :refused
"""
def need_int(st, what)
  if st[:t] == :maybe
    refuse(
      "#{what} may be absent here: test it with .nil? first, or write it `or` a default"
    )
  elsif st[:t] != :int
    refuse("#{what} takes an integer here, got #{to_s(st[:t])}")
  end
  st
end

@doc """
simple?: whether a form loads into a register with no other register touched.

    simple?(start_state(:xdp), 7) #=> true
    simple?(start_state(:xdp), form_of("(f)")) #=> false
"""
def simple?(st, form)
  literal_of(st, form) != nil or
    symbol?(form) and
      local_of(st, name_of(form)) != nil and
      value_type(local_of(st, name_of(form))) != :maybe
end

@doc """
load_simple: a simple form loaded into a named register.

    load_simple(start_state(:xdp), 7, 1)[:rng] #=> [7, 7]
"""
def load_simple(st, form, reg)
  literal = literal_of(st, form)
  if literal != nil
    typed(out(st, [load_constant(reg, literal)]), :int, [literal, literal])
  else
    place = local_of(st, name_of(form))
    if place[:t] == :ctx
      refuse("the context is not a number")
    end
    typed(
      out(st, [load(:dw, reg, 10, slot_offset(place[:slot]))]),
      place[:t],
      place[:rng]
    )
  end
end

@doc """
two_operands: two integer forms lowered, the first into r0 and the second into r1, with their ranges.

    two_operands(start_state(:xdp), 1, 2, "+")[:rr] #=> [2, 2]
"""
def two_operands(st, a, b, what)
  left = need_int(gen(st, a, nil), what)
  left_rng = left[:rng]
  if simple?(left, b)
    done = need_int(load_simple(left, b, 1), what)
    assoc(assoc(done, :lr, left_rng), :rr, done[:rng])
  else
    saved = take_slot(left)
    at = saved[:top] - 1
    held = out(saved, [store(:dw, 10, slot_offset(at), r(0))])
    right = need_int(gen(held, b, nil), what)
    right_rng = right[:rng]
    back = out(right, [alu(:mov, 1, r(0)), load(:dw, 0, 10, slot_offset(at))])
    assoc(assoc(assoc(back, :top, at), :lr, left_rng), :rr, right_rng)
  end
end

@doc """
small_enough?: whether a range is known and small enough to add without care.

    small_enough?([0, 1]) #=> true
    small_enough?(nil) #=> false
"""
def small_enough?(rng)
  rng != nil and
    first(rng) > -1_152_921_504_606_846_976 and
    rng[1] < 1_152_921_504_606_846_976
end

@doc """
added_range: the range of a sum, nil when it is not known.

    added_range([0, 1], [2, 3]) #=> [2, 4]
"""
def added_range(a, b)
  if small_enough?(a) and small_enough?(b)
    [first(a) + first(b), a[1] + b[1]]
  end
end

@doc """
subtracted_range: the range of a difference, nil when it is not known.

    subtracted_range([0, 1], [2, 3]) #=> [-3, -1]
"""
def subtracted_range(a, b)
  if small_enough?(a) and small_enough?(b)
    [first(a) - b[1], a[1] - first(b)]
  end
end

@doc """
multiplied_range: the range of a product, nil when it is not known.

    multiplied_range([2, 3], [4, 5]) #=> [8, 15]
    multiplied_range(nil, [4, 5]).nil? #=> true
"""
def multiplied_range(a, b)
  small = 2_147_483_648
  if a != nil and
      b != nil and
      first(a) > -small and
      a[1] < small and
      first(b) > -small and
      b[1] < small
    products = [
      first(a) * first(b),
      first(a) * b[1],
      a[1] * first(b),
      a[1] * b[1]
    ]
    [apply(blue::min, products), apply(blue::max, products)]
  end
end

@doc """
proven: a compiler state that counts one check proven away.

    proven(start_state(:xdp))[:proven] #=> 1
"""
def proven(st)
  bump(st, :proven)
end

@doc """
checked_count: a compiler state that counts one check emitted.

    checked_count(start_state(:xdp))[:checks] #=> 1
"""
def checked_count(st)
  bump(st, :checks)
end

@doc """
overflow_check: a compiler state with an overflow test on r3 going to the fault path.

    overflow_check(start_state(:xdp), [])[:faults] #=> true
"""
def overflow_check(st, code)
  faulting(checked_count(out(st, append(code, [jump(:slt, 3, 0, "fault")]))))
end

@doc """
gen_add: `+`, its overflow check emitted unless both ranges prove it away.

    gen_add(start_state(:xdp), form_of("(+ 1 2)"))[:rng] #=> [3, 3]
"""
def gen_add(st, form)
  o = two_operands(st, form[1], form[2], "+")
  known = added_range(o[:lr], o[:rr])
  if known != nil
    typed(proven(out(o, [alu(:add, 0, r(1))])), :int, known)
  else
    typed(
      overflow_check(
        o,
        [
          alu(:mov, 2, r(0)),
          alu(:add, 0, r(1)),
          alu(:mov, 3, r(2)),
          alu(:xor, 3, r(0)),
          alu(:mov, 4, r(1)),
          alu(:xor, 4, r(0)),
          alu(:and, 3, r(4))
        ]
      ),
      :int
    )
  end
end

@doc """
gen_sub: `-`, its overflow check emitted unless both ranges prove it away.

    gen_sub(start_state(:xdp), form_of("(- 3 1)"))[:rng] #=> [2, 2]
"""
def gen_sub(st, form)
  if size(form) == 2
    gen_sub(st, ["-", 0, form[1]])
  else
    o = two_operands(st, form[1], form[2], "-")
    known = subtracted_range(o[:lr], o[:rr])
    if known != nil
      typed(proven(out(o, [alu(:sub, 0, r(1))])), :int, known)
    else
      typed(
        overflow_check(
          o,
          [
            alu(:mov, 2, r(0)),
            alu(:sub, 0, r(1)),
            alu(:mov, 3, r(2)),
            alu(:xor, 3, r(1)),
            alu(:mov, 4, r(2)),
            alu(:xor, 4, r(0)),
            alu(:and, 3, r(4))
          ]
        ),
        :int
      )
    end
  end
end

@doc """
gen_mul: `*` of operands whose ranges prove it fits, refused otherwise since a kernel program cannot check it.

    gen_mul(start_state(:xdp), form_of("(* 2 3)"))[:rng] #=> [6, 6]
"""
def gen_mul(st, form)
  o = two_operands(st, form[1], form[2], "*")
  known = multiplied_range(o[:lr], o[:rr])
  if known.nil?
    refuse("`*` of operands whose range is not known cannot be checked in a kernel program: bound them, or say wrapping_mul")
  end
  typed(proven(out(o, [alu(:mul, 0, r(1))])), :int, known)
end

@doc """
gen_mod: `%` by a divisor known to be positive, keeping blue's never-negative answer.

    gen_mod(start_state(:xdp), form_of("(mod 7 3)"))[:rng] #=> [0, 2]
"""
def gen_mod(st, form)
  o = two_operands(st, form[1], form[2], "%")
  divisor = o[:rr]
  if divisor.nil? or first(divisor) < 1
    refuse("`%` needs a divisor known to be positive here: a positive constant, or say unsigned_mod")
  end
  top = divisor[1] - 1
  if o[:lr] != nil and first(o[:lr]) >= 0
    typed(proven(out(o, [alu(:mod, 0, r(1))])), :int, [0, top])
  else
    fresh_st = fresh(o)
    done = label_name(fresh_st)
    typed(
      proven(
        out(
          fresh_st,
          [
            alu(:smod, 0, r(1)),
            jump(:sge, 0, 0, done),
            alu(:add, 0, r(1)),
            label(done)
          ]
        )
      ),
      :int,
      [0, top]
    )
  end
end

@doc """
gen_plain: a word that lowers to one ALU operation and needs no check.

    gen_plain(start_state(:xdp), form_of("(wrapping_add 1 2)"), :add)[:t] #=> :int
"""
def gen_plain(st, form, op)
  o = two_operands(st, form[1], form[2], op)
  typed(out(o, [alu(op, 0, r(1))]), :int)
end

@doc """
gen_bit_and: `bit_and`, a non-negative literal mask bounding the answer.

    gen_bit_and(start_state(:xdp), form_of("(bit_and 7 3)"))[:rng] #=> [0, 3]
"""
def gen_bit_and(st, form)
  o = two_operands(st, form[1], form[2], "bit_and")
  mask = literal_of(st, form[2])
  rng = if mask != nil and mask >= 0
    [0, mask]
  end
  typed(out(o, [alu(:and, 0, r(1))]), :int, rng)
end

@doc """
gen_shift: a shift, its distance checked unless its range proves it under 64.

    gen_shift(start_state(:xdp), form_of("(shift_left 1 2)"), :lsh, "shift_left")[:proven] #=> 1
"""
def gen_shift(st, form, op, word)
  o = two_operands(st, form[1], form[2], word)
  d = o[:rr]
  if d != nil and first(d) >= 0 and d[1] <= 63
    typed(proven(out(o, [alu(op, 0, r(1))])), :int)
  else
    typed(
      faulting(
        checked_count(out(o, [jump(:gt, 1, 63, "fault"), alu(op, 0, r(1))]))
      ),
      :int
    )
  end
end

@doc """
gen_unsigned_divide: an unsigned division, a zero divisor a fault as it is a raise in blue.

    gen_unsigned_divide(start_state(:xdp), form_of("(unsigned_div 4 2)"), :div, "unsigned_div")[:proven] #=> 1
"""
def gen_unsigned_divide(st, form, op, word)
  o = two_operands(st, form[1], form[2], word)
  d = o[:rr]
  if d != nil and first(d) > 0
    typed(proven(out(o, [alu(op, 0, r(1))])), :int)
  else
    typed(
      faulting(
        checked_count(out(o, [jump(:eq, 1, 0, "fault"), alu(op, 0, r(1))]))
      ),
      :int
    )
  end
end

@doc """
gen_compare: a comparison, true or false in r0.

    gen_compare(start_state(:xdp), form_of("(< 1 2)"), :slt)[:t] #=> :bool
"""
def gen_compare(st, form, cond)
  o = two_operands_any(st, form[1], form[2])
  marked = fresh(o)
  done = label_name(marked)
  typed(
    out(
      marked,
      [
        alu(:mov, 2, r(0)),
        alu(:mov, 0, 1),
        jump(cond, 2, r(1), done),
        alu(:mov, 0, 0),
        label(done)
      ]
    ),
    :bool
  )
end

@doc """
two_operands_any: two forms of one type lowered, the first into r0 and the second into r1.

    two_operands_any(start_state(:xdp), 1, 2)[:top] #=> 0
"""
def two_operands_any(st, a, b)
  left = gen(st, a, nil)
  if left[:t] == :bool or left[:t] == :int
    held = take_slot(left)
    at = held[:top] - 1
    saved = out(held, [store(:dw, 10, slot_offset(at), r(0))])
    right = gen(saved, b, nil)
    if right[:t] != left[:t]
      refuse("`==` between #{to_s(left[:t])} and #{to_s(right[:t])}")
    end
    assoc(
      out(right, [alu(:mov, 1, r(0)), load(:dw, 0, 10, slot_offset(at))]),
      :top,
      at
    )
  else
    refuse("a comparison takes integers here, got #{to_s(left[:t])}")
  end
end

@doc """
nil_test_of: what a form tests for absence, nil when it is no such test.

    name_of(nil_test_of(form_of("(nil? x)"))) #=> "x"
    nil_test_of(form_of("(a 1)")).nil? #=> true
"""
def nil_test_of(form)
  if head_name(form) == "blue-field" and size(form) == 3 and form[2] == :nil?
    form[1]
  elsif head_name(form) == "nil?" and size(form) == 2
    form[1]
  end
end

@doc """
gen_nil_test: `.nil?` on a local: its flag read, false for a value that is never absent.

    gen_nil_test(env_with(start_state(:xdp), "x", {t: :int, slot: 0}), form_of("x"))[:t] #=> :bool
"""
def gen_nil_test(st, target)
  if symbol?(target) and local_of(st, name_of(target)) != nil
    place = local_of(st, name_of(target))
    if place[:t] == :maybe and not place[:narrowed]
      typed(
        out(
          st,
          [load(:dw, 0, 10, slot_offset(place[:slot] + 1)), alu(:xor, 0, 1)]
        ),
        :bool
      )
    else
      typed(out(st, [alu(:mov, 0, 0)]), :bool)
    end
  else
    refuse(".nil? takes a local here: name the value first")
  end
end

@doc """
gen_and: `and`, short-circuiting over true and false.

    gen_and(start_state(:xdp), form_of("(and true false)"))[:t] #=> :bool
"""
def gen_and(st, form)
  left = gen(st, form[1], nil)
  if left[:t] != :bool
    refuse("`and` takes true or false here, got #{to_s(left[:t])}")
  end
  marked = fresh(left)
  done = label_name(marked)
  tested = out(marked, [jump(:eq, 0, 0, done)])
  right = gen(narrowing(tested, form[1], true), form[2], nil)
  if right[:t] != :bool
    refuse("`and` takes true or false here, got #{to_s(right[:t])}")
  end
  typed(assoc(out(right, [label(done)]), :env, left[:env]), :bool)
end

@doc """
gen_or: `or`: short-circuiting over true and false, or a default for a value that may be absent.

    gen_or(start_state(:xdp), form_of("(or true false)"))[:t] #=> :bool
"""
def gen_or(st, form)
  left = gen(st, form[1], nil)
  if left[:t] == :maybe
    marked = fresh(left)
    done = label_name(marked)
    tested = out(marked, [jump(:ne, 1, 0, done)])
    right = need_int(gen(tested, form[2], nil), "the default of `or`")
    typed(out(right, [label(done)]), :int)
  elsif left[:t] == :int
    typed(left, :int, left[:rng])
  elsif left[:t] == :bool
    marked = fresh(left)
    done = label_name(marked)
    tested = out(marked, [jump(:ne, 0, 0, done)])
    right = gen(narrowing(tested, form[1], false), form[2], nil)
    if right[:t] != :bool
      refuse(
        "`or` of true or false takes true or false, got #{to_s(right[:t])}"
      )
    end
    typed(assoc(out(right, [label(done)]), :env, left[:env]), :bool)
  else
    refuse("`or` takes a value here, got #{to_s(left[:t])}")
  end
end

@doc """
gen_not: `not` over true and false.

    gen_not(start_state(:xdp), form_of("(not true)"))[:t] #=> :bool
"""
def gen_not(st, form)
  inner = gen(st, form[1], nil)
  if inner[:t] != :bool
    refuse("`not` takes true or false here, got #{to_s(inner[:t])}")
  end
  typed(out(inner, [alu(:xor, 0, 1)]), :bool)
end

@doc """
narrowing: a compiler state where a condition proves its locals present.

    local_of(narrowing(env_with(start_state(:xdp), "x", {t: :maybe, slot: 0}), form_of("(nil? x)"), false), "x")[:narrowed] #=> true
"""
def narrowing(st, cond, truth)
  names = narrowed_names(cond, truth)
  reduce(
    fn(acc, name)
      place = local_of(acc, name)
      if place != nil and place[:t] == :maybe
        env_with(acc, name, assoc(place, :narrowed, true))
      else
        acc
      end
    end,
    st,
    names
  )
end

@doc """
narrowed_names: the locals a condition proves present when it has this truth.

    narrowed_names(form_of("(nil? x)"), false) #=> ["x"]
    narrowed_names(form_of("(nil? x)"), true) #=> []
"""
def narrowed_names(cond, truth)
  head = head_name(cond)
  tested = nil_test_of(cond)
  if tested != nil and not truth and symbol?(tested)
    [name_of(tested)]
  elsif head == "not" and size(cond) == 2
    narrowed_names(cond[1], not truth)
  elsif head == "or" and not truth
    append(narrowed_names(cond[1], false), narrowed_names(cond[2], false))
  elsif head == "and" and truth
    append(narrowed_names(cond[1], true), narrowed_names(cond[2], true))
  else
    []
  end
end

@doc """
join_types: the type of an `if` from its arms, a loop's jump taking the other's.

    join_types(:never, :int) #=> :int
    join_types(:int, :bool) #=> :unit
"""
def join_types(a, b)
  if a == :never
    b
  elsif b == :never
    a
  elsif a == b
    a
  else
    :unit
  end
end

@doc """
join_ranges: the range of an `if` from its arms.

    join_ranges([0, 1], [5, 6], :int, :int) #=> [0, 6]
"""
def join_ranges(a, b, ta, tb)
  if ta == :never
    b
  elsif tb == :never
    a
  elsif a != nil and b != nil
    [blue::min(first(a), first(b)), blue::max(a[1], b[1])]
  end
end

@doc """
gen_if: `if`, each arm narrowed by what its condition proves.

    gen_if(start_state(:xdp), form_of("(if true 1 2)"), nil)[:rng] #=> [1, 2]
"""
def gen_if(st, form, tail)
  cond = form[1]
  tested = gen(st, cond, nil)
  if tested[:t] != :bool
    refuse("`if` takes true or false here, and an integer is always truthy in blue: compare it")
  end
  outer_env = tested[:env]
  outer_top = tested[:top]
  marked = fresh(fresh(tested))
  otherwise = "L#{to_s(marked[:labels] - 1)}"
  done = label_name(marked)
  branched = out(marked, [jump(:eq, 0, 0, otherwise)])
  yes = gen(narrowing(branched, cond, true), form[2], tail)
  yes_t = yes[:t]
  yes_rng = yes[:rng]
  rejoined = out(
    assoc(assoc(yes, :env, outer_env), :top, outer_top),
    [ja(done), label(otherwise)]
  )
  no = if size(form) > 3
    gen(narrowing(rejoined, cond, false), form[3], tail)
  else
    typed(out(rejoined, [alu(:mov, 0, 0)]), :unit)
  end
  no_t = no[:t]
  typed(
    assoc(assoc(out(no, [label(done)]), :env, outer_env), :top, outer_top),
    join_types(yes_t, no_t),
    join_ranges(yes_rng, no[:rng], yes_t, no_t)
  )
end

@doc """
gen_begin: a sequence: the last form's value, and the tail position.

    gen_begin(start_state(:xdp), [1, 2], nil)[:rng] #=> [2, 2]
"""
def gen_begin(st, forms, tail)
  if forms == []
    typed(st, :unit)
  else
    reduce(
      fn(acc, pair)
        at_end = first(pair) == size(forms) - 1
        gen(
          acc,
          pair[1],
          if at_end
            tail
          end
        )
      end,
      st,
      zip(range(0, size(forms)), forms)
    )
  end
end

@doc """
gen_define: `define` of a local, rebinding in place when it exists.

    gen_define(start_state(:xdp), form_of("(define x 1)"))[:t] #=> :unit
"""
def gen_define(st, form)
  target = form[1]
  if not symbol?(target)
    refuse("a nested function has no place in a kernel program; move it to the top level")
  end
  name = name_of(target)
  value = gen(st, form[2], nil)
  bind(value, name)
end

@doc """
bind: the value in r0 bound to a name.

    bind(typed(start_state(:xdp), :int), "x")[:top] #=> 1
"""
def bind(st, name)
  t = st[:t]
  place = local_of(st, name)
  case t
  when :ctx
    typed(env_with(st, name, {t: :ctx}), :unit)
  when :maybe
    held = if place != nil and place[:t] == :maybe
      st
    else
      take_slot(take_slot(st))
    end
    at = if place != nil and place[:t] == :maybe
      place[:slot]
    else
      held[:top] - 2
    end
    typed(
      env_with(
        out(
          held,
          [
            store(:dw, 10, slot_offset(at), r(0)),
            store(:dw, 10, slot_offset(at + 1), r(1))
          ]
        ),
        name,
        {t: :maybe, slot: at}
      ),
      :unit
    )
  when :unit
    refuse("`#{name}` is bound to a value that has none")
  else
    if place != nil and place[:t] == t
      typed(
        env_with(
          out(st, [store(:dw, 10, slot_offset(place[:slot]), r(0))]),
          name,
          assoc(place, :rng, st[:rng])
        ),
        :unit
      )
    else
      held = take_slot(st)
      at = held[:top] - 1
      typed(
        env_with(
          out(held, [store(:dw, 10, slot_offset(at), r(0))]),
          name,
          {t:, slot: at, rng: st[:rng]}
        ),
        :unit
      )
    end
  end
end

@doc """
gen_call: a call to a definition: inlined, a loop in tail position, refused when it recurses otherwise.

    (gen_call(start_state(:xdp), "none", [], nil) rescue :refused) #=> :refused
"""
def gen_call(st, name, args, tail)
  f = get(st[:fns], name)
  if f.nil?
    refuse(
      "`#{name}` has no lowering at this position; a kernel program calls its own definitions and bpf's words"
    )
  end
  if tail == name
    gen_tail_call(st, f, args)
  elsif member?(name, st[:calling])
    refuse(
      "`#{name}` recurses and not in tail position; a kernel program has no such stack"
    )
  else
    gen_inline(st, name, f, args)
  end
end

@doc """
gen_inline: a definition's body in place, its parameters bound to the arguments.

    gen_inline(start_state(:xdp), "f", {name: "f", params: [], body: 7}, [])[:rng] #=> [7, 7]
"""
def gen_inline(st, name, f, args)
  params = f[:params]
  if size(params) != size(args)
    refuse(
      "`#{name}` takes #{to_s(size(params))} arguments, got #{to_s(size(args))}"
    )
  end
  caller_env = st[:env]
  caller_top = st[:top]
  caller_calling = st[:calling]
  bound = reduce(
    fn(acc, pair)
      value = gen(assoc(acc, :env, caller_env), pair[1], nil)
      kept = bind(assoc(value, :env, acc[:bound]), first(pair))
      assoc(assoc(kept, :bound, kept[:env]), :env, caller_env)
    end,
    assoc(st, :bound, {}),
    zip(params, args)
  )
  marked = fresh(bound)
  start = label_name(marked)
  entered = out(
    assoc(
      assoc(
        assoc(marked, :env, bound[:bound]),
        :calling,
        append(caller_calling, [name])
      ),
      :starts,
      assoc(marked[:starts], name, start)
    ),
    [label(start)]
  )
  body = gen(entered, f[:body], name)
  assoc(
    assoc(assoc(body, :env, caller_env), :top, caller_top),
    :calling,
    caller_calling
  )
end

@doc """
gen_tail_call: a call to itself in tail position: the parameters rebound and a jump back.

    answer("(define (%root/s i) (if (>= i 5) i (%root/s (+ i 1)))) (define (%root/e c) (%root/s 0))") #=> 5
"""
def gen_tail_call(st, f, args)
  name = f[:name]
  params = f[:params]
  if size(params) != size(args)
    refuse(
      "`#{name}` takes #{to_s(size(params))} arguments, got #{to_s(size(args))}"
    )
  end
  top = st[:top]
  values = reduce(
    fn(acc, arg)
      value = need_int(gen(acc, arg, nil), "a recursive argument")
      held = take_slot(value)
      at = held[:top] - 1
      out(
        assoc(held, :temps, append(held[:temps], [at])),
        [store(:dw, 10, slot_offset(at), r(0))]
      )
    end,
    assoc(st, :temps, []),
    args
  )
  moved = reduce(
    fn(acc, pair)
      place = local_of(acc, first(pair))
      out(
        acc,
        [
          load(:dw, 0, 10, slot_offset(pair[1])),
          store(:dw, 10, slot_offset(place[:slot]), r(0))
        ]
      )
    end,
    values,
    zip(params, values[:temps])
  )
  widened = reduce(
    fn(acc, param)
      place = local_of(acc, param)
      env_with(acc, param, dissoc(place, :rng))
    end,
    moved,
    params
  )
  typed(assoc(out(widened, [ja(get(st[:starts], name))]), :top, top), :never)
end

@doc """
map_named: the map a form names, refused for anything not declared at the top level.

    map_named(assoc(start_state(:xdp), :map_consts, {"M" => {name: :m}}), form_of("M"))[:name] #=> :m
"""
def map_named(st, form)
  name = if symbol?(form)
    name_of(form)
  end
  m = get(st[:map_consts], or_empty(name))
  if m.nil?
    refuse(
      "a map word takes a map declared at the top level with bpf::declare_map, got #{to_s(form)}"
    )
  end
  m
end

@doc """
scalar_size: the access size of a key or value this many bytes wide.

    scalar_size(4) #=> :w
    (scalar_size(3) rescue :refused) #=> :refused
"""
def scalar_size(count)
  case count
  when 1
    :b
  when 2
    :h
  when 4
    :w
  when 8
    :dw
  else
    refuse(
      "a map key or value here is 1, 2, 4 or 8 bytes, got #{to_s(count)}: a bigger record takes a layout"
    )
  end
end

@doc """
key_on_stack: a key lowered onto the stack, where a helper reads it.

    key_on_stack(start_state(:xdp), 1)[:key_at] #=> 0
"""
def key_on_stack(st, form)
  value = need_int(gen(st, form, nil), "a map key")
  held = take_slot(value)
  at = held[:top] - 1
  assoc(out(held, [store(:dw, 10, slot_offset(at), r(0))]), :key_at, at)
end

@doc """
fp_at: the instructions that point a register at a stack slot.

    size(fp_at(2, 0)) #=> 2
"""
def fp_at(reg, at)
  [alu(:mov, reg, r(10)), alu(:add, reg, slot_offset(at))]
end

@doc """
gen_map_get: `map_get`: the value in r0 and whether it is present in r1.

    with_map("(or (bpf/map_get %root/M 1) 9)") #=> 9
"""
def gen_map_get(st, args)
  m = map_named(st, first(args))
  keyed = key_on_stack(st, args[1])
  marked = fresh(keyed)
  done = label_name(marked)
  typed(
    assoc(
      out(
        marked,
        [
          map_ref(1, m[:name]),
          fp_at(2, keyed[:key_at]),
          call(:map_lookup_elem),
          alu(:mov, 1, 0),
          jump(:eq, 0, 0, done),
          load(scalar_size(m[:value_size]), 0, 0, 0),
          alu(:mov, 1, 1),
          label(done)
        ]
      ),
      :top,
      st[:top]
    ),
    :maybe
  )
end

@doc """
gen_map_put: `map_put`, a failed update a fault.

    with_map("(begin (bpf/map_put %root/M 1 2) (or (bpf/map_get %root/M 1) 0))") #=> 2
"""
def gen_map_put(st, args)
  m = map_named(st, first(args))
  keyed = key_on_stack(st, args[1])
  value = need_int(gen(keyed, args[2], nil), "a map value")
  held = take_slot(value)
  at = held[:top] - 1
  typed(
    assoc(
      faulting(
        out(
          held,
          [
            store(:dw, 10, slot_offset(at), r(0)),
            map_ref(1, m[:name]),
            fp_at(2, keyed[:key_at]),
            fp_at(3, at),
            alu(:mov, 4, 0),
            call(:map_update_elem),
            jump(:ne, 0, 0, "fault")
          ]
        )
      ),
      :top,
      st[:top]
    ),
    :unit
  )
end

@doc """
gen_map_add: `map_add`: an atomic add, an absent key inserted.

    with_map("(begin (bpf/map_add %root/M 1 2) (bpf/map_add %root/M 1 3) (or (bpf/map_get %root/M 1) 0))") #=> 5
"""
def gen_map_add(st, args)
  m = map_named(st, first(args))
  if m[:value_size] != 8 and m[:value_size] != 4
    refuse("map_add takes a map of 4 or 8 byte values")
  end
  width = scalar_size(m[:value_size])
  keyed = key_on_stack(st, args[1])
  amount = need_int(gen(keyed, args[2], nil), "the amount of map_add")
  held = take_slot(amount)
  at = held[:top] - 1
  marked = fresh(fresh(held))
  miss = "L#{to_s(marked[:labels] - 1)}"
  done = label_name(marked)
  typed(
    assoc(
      faulting(
        out(
          marked,
          [
            store(:dw, 10, slot_offset(at), r(0)),
            map_ref(1, m[:name]),
            fp_at(2, keyed[:key_at]),
            call(:map_lookup_elem),
            jump(:eq, 0, 0, miss),
            load(:dw, 1, 10, slot_offset(at)),
            atomic(:add, width, 0, 0, 1),
            ja(done),
            label(miss),
            map_ref(1, m[:name]),
            fp_at(2, keyed[:key_at]),
            fp_at(3, at),
            alu(:mov, 4, 0),
            call(:map_update_elem),
            jump(:ne, 0, 0, "fault"),
            label(done),
            alu(:mov, 0, 0)
          ]
        )
      ),
      :top,
      st[:top]
    ),
    :unit
  )
end

@doc """
gen_map_delete: `map_delete`: true when the key was there.

    with_map("(begin (bpf/map_put %root/M 1 2) (if (bpf/map_delete %root/M 1) 1 0))") #=> 1
"""
def gen_map_delete(st, args)
  m = map_named(st, first(args))
  keyed = key_on_stack(st, args[1])
  marked = fresh(keyed)
  done = label_name(marked)
  typed(
    assoc(
      out(
        marked,
        [
          map_ref(1, m[:name]),
          fp_at(2, keyed[:key_at]),
          call(:map_delete_elem),
          alu(:mov, 1, r(0)),
          alu(:mov, 0, 1),
          jump(:eq, 1, 0, done),
          alu(:mov, 0, 0),
          label(done)
        ]
      ),
      :top,
      st[:top]
    ),
    :bool
  )
end

@doc """
gen_emit: `emit`: a record of values on the stack, sent through the ring buffer.

    run(compiled_source("(define %root/E (bpf/declare_map :e :ringbuf 0 0 4096)) (define (%root/e c) (begin (bpf/emit %root/E (list 7)) 2))"), {maps: [declare_map(:e, :ringbuf, 0, 0, 4096)]}).ret #=> 2
"""
def gen_emit(st, args)
  m = map_named(st, first(args))
  values = args[1]
  if head_name(values) != "list"
    refuse("emit takes a literal list of values")
  end
  items = rest(values)
  count = size(items)
  if count == 0
    refuse("emit takes at least one value")
  end
  first_slot = st[:top]
  reserved = reduce((acc, _i) -> take_slot(acc), st, range(0, count))
  filled = reduce(
    fn(acc, pair)
      value = need_int(gen(acc, pair[1], nil), "an emitted value")
      out(
        value,
        [
          store(
            :dw,
            10,
            slot_offset(first_slot + count - 1 - first(pair)),
            r(0)
          )
        ]
      )
    end,
    reserved,
    zip(range(0, count), items)
  )
  typed(
    assoc(
      out(
        filled,
        [
          map_ref(1, m[:name]),
          fp_at(2, first_slot + count - 1),
          alu(:mov, 3, count * 8),
          alu(:mov, 4, 0),
          call(:ringbuf_output),
          alu(:mov, 0, 0)
        ]
      ),
      :top,
      first_slot
    ),
    :unit
  )
end

@doc """
gen_helper: `helper`: a kernel helper by name, its arguments loaded into r1 to r5.

    answer("(define (%root/e c) (bpf/helper :get_smp_processor_id))") #=> 0
"""
def gen_helper(st, args)
  name = first(args)
  if not keyword?(name)
    refuse("helper takes a helper's name as a keyword")
  end
  values = rest(args)
  if size(values) > 5
    refuse("a helper takes at most five arguments")
  end
  first_slot = st[:top]
  stored = reduce(
    fn(acc, form)
      value = need_int(gen(acc, form, nil), "a helper argument")
      held = take_slot(value)
      out(held, [store(:dw, 10, slot_offset(held[:top] - 1), r(0))])
    end,
    st,
    values
  )
  loaded = map(
    (i) -> load(:dw, i + 1, 10, slot_offset(first_slot + i)),
    range(0, size(values))
  )
  typed(
    assoc(out(stored, append(loaded, [call(name)])), :top, first_slot),
    :int
  )
end

@doc """
literal_text: a form that must be a literal string, refused otherwise.

    literal_text("a", "x") #=> "a"
    (literal_text(1, "x") rescue :refused) #=> :refused
"""
def literal_text(form, what)
  if not string?(form)
    refuse("#{what} is a literal string, known when the program compiles")
  end
  form
end

@doc """
literal_path: a field's path, a literal list of names.

    literal_path(form_of("(list \"a\")")) #=> ["a"]
"""
def literal_path(form)
  if head_name(form) != "list" or rest(form) == []
    refuse("a field's path is a literal list of names")
  end
  map((name) -> literal_text(name, "a field's name"), rest(form))
end

@doc """
gen_kernel_read: `kernel_read`: the field's offset left to be bound, then `probe_read_kernel`.

    first(compiled_source("(define (%root/e c) (bpf/kernel_read 0 \"s\" (list \"f\") 4))", :tracing)[:fields])[:struct] #=> "s"
"""
def gen_kernel_read(st, args)
  count = literal_of(st, args[3])
  if count.nil? or not member?(count, [1, 2, 4, 8])
    refuse("kernel_read takes a literal size of 1, 2, 4 or 8 bytes")
  end
  pointer = need_int(gen(st, first(args), nil), "a kernel pointer")
  held = take_slot(pointer)
  at = held[:top] - 1
  field_add = assoc(
    alu(:add, 3, 0),
    :field,
    {
      struct: literal_text(args[1], "a struct's name"),
      path: literal_path(args[2]),
      size: count
    }
  )
  typed(
    assoc(
      faulting(
        out(
          held,
          [
            alu(:mov, 3, r(0)),
            field_add,
            fp_at(1, at),
            alu(:mov, 2, count),
            call(:probe_read_kernel),
            jump(:ne, 0, 0, "fault"),
            load(scalar_size(count), 0, 10, slot_offset(at))
          ]
        )
      ),
      :top,
      st[:top]
    ),
    :int,
    unsigned_range(count)
  )
end

@doc """
gen_ctx_int: `ctx_int`, at a literal offset as the verifier requires.

    run(compile_forms(read_forms("(define (%root/e c) (bpf/ctx_int c 0 1))"), {entry: :e, kind: :tracepoint}), {ctx: [7]}).ret #=> 7
"""
def gen_ctx_int(st, args)
  off = literal_of(st, args[1])
  if off.nil?
    refuse("ctx_int takes a literal offset: the verifier knows each context field by its offset")
  end
  count = literal_of(st, args[2])
  typed(
    out(st, [load(scalar_size(count), 0, 6, off)]),
    :int,
    unsigned_range(count)
  )
end

@doc """
unsigned_range: the range an unsigned integer of this many bytes has, nil for 8.

    unsigned_range(1) #=> [0, 255]
    unsigned_range(8).nil? #=> true
"""
def unsigned_range(count)
  if count < 8
    [0, shift_left(1, count * 8) - 1]
  end
end

@doc """
packet_bounds: the bounds check a packet access needs, leaving its address in r2.

    packet_bounds(start_state(:xdp), 0, 1, :xdp)[:faults] #=> true
"""
def packet_bounds(st, off_form, count, kind)
  literal = literal_of(st, off_form)
  ctx_fields = packet_fields(kind)
  base = [load(:w, 2, 6, first(ctx_fields)), load(:w, 3, 6, ctx_fields[1])]
  if literal != nil and literal >= 0 and literal + count <= 65535
    assoc(
      faulting(
        proven(
          out(
            st,
            append(
              base,
              [
                alu(:mov, 4, r(2)),
                alu(:add, 4, literal + count),
                jump(:gt, 4, r(3), "fault"),
                alu(:add, 2, literal)
              ]
            )
          )
        )
      ),
      :off_form,
      nil
    )
  else
    value = need_int(gen(st, off_form, nil), "a packet offset")
    faulting(
      checked_count(
        out(
          value,
          append(
            base,
            [
              jump(:gt, 0, 65535, "fault"),
              alu(:add, 2, r(0)),
              alu(:mov, 4, r(2)),
              alu(:add, 4, count),
              jump(:gt, 4, r(3), "fault")
            ]
          )
        )
      )
    )
  end
end

@doc """
packet_fields: where a program type's context holds `data` and `data_end`.

    packet_fields(:xdp) #=> [0, 4]
    packet_fields(:sched_cls) #=> [76, 80]
    packet_fields(:lwt_xmit) #=> [76, 80]
    packet_fields(:flow_dissector) #=> [76, 80]
    (packet_fields(:socket_filter) rescue :refused) #=> :refused
"""
def packet_fields(kind)
  case kind
  when :xdp
    [0, 4]
  when :socket_filter
    refuse("a socket filter has no direct packet: read `len` and `protocol` with ctx_int")
  else
    if member?(kind, skb_kinds) or kind == :flow_dissector
      [76, 80]
    else
      refuse(
        "a #{to_s(kind)} program has no packet here; read it with a helper"
      )
    end
  end
end

@doc """
gen_packet_int: `packet_int`: a bounds check, a load, a swap from network order.

    answer("(define (%root/e c) (bpf/packet_int c 0 1))", [7]) #=> 7
"""
def gen_packet_int(st, args)
  count = literal_of(st, args[2])
  bounded = packet_bounds(st, args[1], count, st[:kind])
  swapped = if count == 1
    []
  else
    [swap(:be, 0, count * 8)]
  end
  typed(
    out(bounded, append([load(scalar_size(count), 0, 2, 0)], swapped)),
    :int,
    unsigned_range(count)
  )
end

@doc """
gen_packet_put: `packet_put`: a bounds check, a swap to network order, a store.

    packet_of(run(compiled_source("(define (%root/e c) (begin (bpf/packet_put c 0 1 9) 2))"), {packet: [0]})) #=> [9]
"""
def gen_packet_put(st, args)
  count = literal_of(st, args[2])
  value = need_int(gen(st, args[3], nil), "a packet value")
  held = take_slot(value)
  at = held[:top] - 1
  saved = out(held, [store(:dw, 10, slot_offset(at), r(0))])
  bounded = packet_bounds(saved, args[1], count, st[:kind])
  swapped = if count == 1
    []
  else
    [swap(:be, 1, count * 8)]
  end
  typed(
    assoc(
      out(
        bounded,
        append(
          *[
            [load(:dw, 1, 10, slot_offset(at))],
            swapped,
            [store(scalar_size(count), 2, 0, r(1)), alu(:mov, 0, 0)]
          ]
        )
      ),
      :top,
      st[:top]
    ),
    :unit
  )
end

@doc """
gen_packet_len: `packet_len`: `data_end` less `data`.

    answer("(define (%root/e c) (bpf/packet_len c))", [1, 2]) #=> 2
"""
def gen_packet_len(st)
  fields = packet_fields(st[:kind])
  typed(
    out(
      st,
      [
        load(:w, 0, 6, fields[1]),
        load(:w, 2, 6, first(fields)),
        alu(:sub, 0, r(2))
      ]
    ),
    :int,
    [0, 65535]
  )
end

@doc """
gen_word: one of this package's kernel words, refused for one with no lowering.

    (gen_word(start_state(:xdp), "nope", []) rescue :refused) #=> :refused
"""
def gen_word(st, word, args)
  case word
  when "packet_int"
    gen_packet_int(st, args)
  when "packet_put"
    gen_packet_put(st, args)
  when "packet_len"
    gen_packet_len(st)
  when "ctx_int"
    gen_ctx_int(st, args)
  when "kernel_read"
    gen_kernel_read(st, args)
  when "map_get"
    gen_map_get(st, args)
  when "map_put"
    gen_map_put(st, args)
  when "map_add"
    gen_map_add(st, args)
  when "map_delete"
    gen_map_delete(st, args)
  when "emit"
    gen_emit(st, args)
  when "helper"
    gen_helper(st, args)
  else
    refuse("bpf::#{word} has no lowering inside a kernel program")
  end
end

@doc """
gen_list: a call form, by its head.

    gen_list(start_state(:xdp), form_of("(+ 1 2)"), nil)[:t] #=> :int
"""
def gen_list(st, form, tail)
  name = head_name(form)
  args = rest(form)
  word = word_of(or_empty(name))
  case name
  when "if"
    gen_if(st, form, tail)
  when "begin"
    gen_begin(st, args, tail)
  when "define"
    gen_define(st, form)
  when "+"
    gen_add(st, form)
  when "-"
    gen_sub(st, form)
  when "*"
    gen_mul(st, form)
  when "mod"
    gen_mod(st, form)
  when "/"
    refuse("`/` can answer a fraction, which a kernel program has no way to hold: say unsigned_div")
  when "equal?"
    gen_compare(st, form, :eq)
  when "not="
    gen_compare(st, form, :ne)
  when "<"
    gen_compare(st, form, :slt)
  when "<="
    gen_compare(st, form, :sle)
  when ">"
    gen_compare(st, form, :sgt)
  when ">="
    gen_compare(st, form, :sge)
  when "unsigned_less?"
    gen_compare(st, form, :lt)
  when "and"
    gen_and(st, form)
  when "or"
    gen_or(st, form)
  when "not"
    gen_not(st, form)
  when "bit_and"
    gen_bit_and(st, form)
  when "bit_or"
    gen_plain(st, form, :or)
  when "bit_xor"
    gen_plain(st, form, :xor)
  when "bit_not"
    typed(
      out(need_int(gen(st, first(args), nil), "bit_not"), [alu(:xor, 0, -1)]),
      :int
    )
  when "wrapping_add"
    gen_plain(st, form, :add)
  when "wrapping_sub"
    gen_plain(st, form, :sub)
  when "wrapping_mul"
    gen_plain(st, form, :mul)
  when "shift_left"
    gen_shift(st, form, :lsh, name)
  when "shift_right"
    gen_shift(st, form, :arsh, name)
  when "shift_right_logical"
    gen_shift(st, form, :rsh, name)
  when "unsigned_div"
    gen_unsigned_divide(st, form, :div, name)
  when "unsigned_mod"
    gen_unsigned_divide(st, form, :mod, name)
  when "blue-field"
    if form[2] == :nil?
      gen_nil_test(st, form[1])
    else
      refuse("a field read has no lowering in a kernel program")
    end
  when "nil?"
    gen_nil_test(st, first(args))
  else
    if word != nil and constant_of(word).nil?
      gen_word(st, word, args)
    elsif literal_of(st, form) != nil
      gen_symbol(st, first(form))
    else
      gen_call(st, name, args, tail)
    end
  end
end

@doc """
gen: any form lowered, its value in r0 and its type in the state.

    gen(start_state(:xdp), 7, nil)[:rng] #=> [7, 7]
    (gen(start_state(:xdp), "text", nil) rescue :refused) #=> :refused
"""
def gen(st, form, tail)
  if integer?(form)
    typed(out(st, [load_constant(0, form)]), :int, [form, form])
  elsif form == true
    typed(out(st, [alu(:mov, 0, 1)]), :bool)
  elsif form == false
    typed(out(st, [alu(:mov, 0, 0)]), :bool)
  elsif symbol?(form)
    gen_symbol(st, form)
  elsif list?(form) and head_name(form) != nil
    gen_list(st, form, tail)
  else
    refuse("this form has no lowering in a kernel program: #{to_s(form)}")
  end
end

@doc """
declared_map_of: the map a top-level form declares, nil for any other form.

    declared_map_of(form_of("(bpf/declare_map :m :array 4 8 1)"))[:max_entries] #=> 1
    declared_map_of(form_of("(a 1)")).nil? #=> true
"""
def declared_map_of(form)
  if head_name(form) == "bpf/declare_map" and size(form) == 6
    {
      name: form[1],
      kind: form[2],
      key_size: form[3],
      value_size: form[4],
      max_entries: form[5]
    }
  end
end

@doc """
constant_value: the integer a top-level form is, nil when it is not one.

    constant_value({}, 7) #=> 7
    constant_value({"k" => 3}, form_of("k")) #=> 3
"""
def constant_value(consts, form)
  if integer?(form)
    form
  elsif symbol?(form)
    get(consts, name_of(form))
  elsif head_name(form) == "-" and size(form) == 2
    v = constant_value(consts, form[1])
    if v != nil
      -v
    end
  end
end

@doc """
plain_params: a definition's parameter names, a typed parameter by its name.

    plain_params(form_of("(f a b)")) #=> ["a", "b"]
"""
def plain_params(signature)
  map(
    fn(p)
      if symbol?(p)
        name_of(p)
      elsif list?(p) and symbol?(first(p))
        name_of(first(p))
      else
        refuse("this parameter has no lowering in a kernel program: #{to_s(p)}")
      end
    end,
    rest(signature)
  )
end

@doc """
collect_top: one top-level form added to what the compiler knows.

    get(collect_top({consts: {}, fns: {}, map_consts: {}, map_list: []}, form_of("(define k 3)"))[:consts], "k") #=> 3
"""
def collect_top(acc, form)
  head = head_name(form)
  if head == "define" and list?(form[1])
    name = name_of(first(form[1]))
    f = {name:, params: plain_params(form[1]), body: form[2]}
    assoc(acc, :fns, assoc(acc[:fns], name, f))
  elsif head == "define-typed" and list?(form[1])
    name = name_of(first(form[1]))
    f = {name:, params: plain_params(form[1]), body: form[3]}
    assoc(acc, :fns, assoc(acc[:fns], name, f))
  elsif head == "define"
    name = name_of(form[1])
    m = declared_map_of(form[2])
    if m != nil
      assoc(
        assoc(acc, :map_consts, assoc(acc[:map_consts], name, m)),
        :map_list,
        append(acc[:map_list], [m])
      )
    else
      value = constant_value(acc[:consts], form[2])
      if value != nil
        assoc(acc, :consts, assoc(acc[:consts], name, value))
      else
        acc
      end
    end
  else
    acc
  end
end

@doc """
entry_of: the definition to compile by its short name, refused when there is none.

    entry_of({fn_names: ["%root/f"], fns: {"%root/f" => {name: "f"}}}, :f)[:name] #=> "f"
"""
def entry_of(top, wanted)
  names = filter((n) -> short_name(n) == to_s(wanted), top[:fn_names])
  if names == []
    refuse("no definition named #{to_s(wanted)} to compile")
  end
  get(top[:fns], first(names))
end

@doc """
names_of: the name of each function a file's forms define.

    names_of(read_forms("(define (f) 1) (define k 2)")) #=> ["f"]
"""
def names_of(forms)
  filter(
    (n) -> not n.nil?,
    map(
      fn(form)
        if member?(head_name(form), %w[define define-typed]) and list?(form[1])
          name_of(first(form[1]))
        end
      end,
      forms
    )
  )
end

@doc """
start_state: a compiler state with nothing lowered yet, the program's first instruction keeping the context in r6.

    size(start_state(:xdp)[:code]) #=> 1
"""
def start_state(kind)
  {
    code: [alu(:mov, 6, r(1))],
    labels: 0,
    top: 0,
    high: 0,
    checks: 0,
    proven: 0,
    faults: false,
    env: {},
    calling: [],
    starts: {},
    fns: {},
    consts: {},
    map_consts: {},
    kind:
  }
end

@doc """
form_of: the first form in text, as the compiler reads it.

    head_name(form_of("(a 1)")) #=> "a"
"""
def form_of(text)
  first(read_forms(text))
end

@doc """
with_map: what a body of resolved text answers on the machine, with a hash map `%root/M` declared and bound.

    with_map("7") #=> 7
"""
def with_map(body)
  text = "(define %root/M (bpf/declare_map :m :hash 4 8 4)) (define (%root/e c) #{body})"
  run(compiled_source(text), {maps: [declare_map(:m, :hash, 4, 8, 4)]}).ret
end

@doc """
compile_forms: a resolved program's forms to a kernel program: its assembled instructions, its maps, and a `report` counting the safety checks proven away and the ones emitted. `opts` takes {entry:, kind:, on_fault:}: the definition to compile, the program type, and the value returned on a fault, which is what a raise is at this position. A construct the position has no lowering for raises :bpf_compile naming it.

    p = compile_forms(read_forms("(define (%root/f ctx) 2)"), {entry: :f, kind: :xdp, on_fault: 0})
    run(p).ret #=> 2
    p[:report][:checks] #=> 0
"""
def compile_forms(forms, opts)
  top = reduce(
    collect_top,
    {
      fns: {},
      consts: {},
      map_consts: {},
      map_list: [],
      fn_names: names_of(forms)
    },
    forms
  )
  f = entry_of(top, opts[:entry])
  if size(f[:params]) > 1
    refuse(
      "a program's entry takes the context alone, got #{to_s(size(f[:params]))} parameters"
    )
  end
  env = reduce((acc, param) -> assoc(acc, param, {t: :ctx}), {}, f[:params])
  st = reduce(
    (acc, pair) -> assoc(acc, first(pair), pair[1]),
    start_state(opts[:kind]),
    [
      [:env, env],
      [:calling, [f[:name]]],
      [:fns, top[:fns]],
      [:consts, top[:consts]],
      [:map_consts, top[:map_consts]]
    ]
  )
  body = gen(st, f[:body], nil)
  if body[:t] != :int and body[:t] != :never
    refuse("a program's entry answers an integer, got #{to_s(body[:t])}")
  end
  ending = if body[:faults]
    [
      exit_program,
      label("fault"),
      alu(:mov, 0, opts[:on_fault] or 0),
      exit_program
    ]
  else
    [exit_program]
  end
  program = assemble(append(body[:code], ending))
  apply_shape(
    program,
    {
      maps: top[:map_list],
      kind: opts[:kind],
      name: short_name(f[:name]),
      report: {
        checks: body[:checks],
        proven: body[:proven],
        slots: body[:high],
        slots_of: 64,
        insns: program[:slots]
      }
    }
  )
end

@doc """
apply_shape: an assembled program with what compiling it found.

    apply_shape({}, {maps: [], kind: :xdp, name: "n", report: {}})[:name] #=> "n"
"""
def apply_shape(program, extra)
  reduce(
    (acc, k) -> assoc(acc, k, get(extra, k)),
    program,
    %i[maps kind name report]
  )
end

@doc """
patched_at: instructions with one slot's immediate replaced.

    first(patched_at([exit_program], 0, 5))[:imm] #=> 5
"""
def patched_at(insns, wanted, imm)
  get(
    reduce(
      fn(acc, i)
        fixed = if acc[:at] == wanted
          assoc(i, :imm, imm)
        else
          i
        end
        {at: acc[:at] + slots_of(i), insns: append(acc[:insns], [fixed])}
      end,
      {at: 0, insns: []},
      insns
    ),
    :insns
  )
end

@doc """
bind_fields: a program with each `kernel_read` field's offset filled in, from `resolve`, a function of a struct's name and a path answering {offset:, size:}. A field whose size on this kernel is not the program's raises :kernel_mismatch, where a wrong read would have gone on silently. This is a CO-RE relocation done before load, so a signed program can carry it.

    p = bind_fields(assemble([assoc(alu(:add, 3, 0), :field, {struct: "s", path: ["f"], size: 4})]), (_s, _path) -> {offset: 8, size: 4})
    p[:insns][0][:imm] #=> 8
    p[:fields] #=> []
"""
def bind_fields(program, resolve)
  bound = reduce(
    fn(insns, f)
      got = resolve(f[:struct], f[:path])
      if got[:size] != f[:size]
        raise(
          :kernel_mismatch,
          "#{f[:struct]}.#{join(f[:path], ".")} is #{to_s(got[:size])} bytes on this kernel; the program reads #{to_s(f[:size])}"
        )
      end
      patched_at(insns, f[:at], got[:offset])
    end,
    program[:insns],
    program[:fields] or []
  )
  assoc(assoc(program, :insns, bound), :fields, [])
end

@doc """
compile: a blue file's definition to a kernel program, through the resolved tree `blue ast --resolved` prints, so what compiles has passed every rule the check stage holds. See `compile_forms`.

    (compile("/no/such/file.b", {}) rescue :refused) #=> :refused
"""
def compile(path, opts)
  checked_run = exec_capture(blue_exe, "check", path)
  if checked_run.status != 0
    raise(:bpf_compile, "#{path} does not check: #{checked_run.stderr}")
  end
  resolved_run = exec_capture(blue_exe, "ast", "--resolved", path)
  if resolved_run.status != 0
    raise(:bpf_compile, "#{path} does not resolve: #{resolved_run.stderr}")
  end
  compile_forms(read_forms(resolved_run.stdout), opts)
end

test "a frame reaches a program through the context its type reads"
  frame = append(repeat(0, 12), [8, 0, 69, 9])
  len_of = fn(kind)
    read_mem(machine(assemble([]), {packet: frame, kind:}), ctx_base, 4)
  end
  assert packet_of(machine(assemble([]), {packet: frame, kind: :sched_cls})) ==
    frame
  assert packet_of(
    machine(assemble([]), {packet: frame, kind: :flow_dissector})
  ) == frame
  assert packet_of(machine(assemble([]), {packet: frame, kind: :cgroup_skb})) ==
    [69, 9]
  assert packet_of(machine(assemble([]), {packet: frame})) == frame
  assert len_of(:lwt_in) == 2
  assert len_of(:sched_cls) == size(frame)
  st = machine(assemble([]), {packet: frame, kind: :socket_filter})
  assert read_mem(st, ctx_base + 16, 2) == 8
  assert read_mem(st, ctx_base + 17, 1) == 0
  assert packet_of(machine(assemble([]), {packet: [], kind: :lwt_out})) == []
  assert packet_of(
    machine(assemble([]), {packet: [1], kind: :socket_filter})
  ) == []
end

test "a compiled socket-buffer program reads its packet at the kernel's fields, and a socket filter is told to read its length"
  p = compile_forms(
    read_forms("(define (%root/e c) (bpf/packet_int c 0 1))"),
    {entry: :e, kind: :lwt_xmit, on_fault: 9}
  )
  assert run(p, {packet: append(repeat(0, 14), [7])}).ret == 7
  assert run(p, {packet: repeat(0, 14)}).ret == 9
  filter_program = compile_forms(
    read_forms("(define (%root/e c) (bpf/ctx_int c 0 4))"),
    {entry: :e, kind: :socket_filter, on_fault: 9}
  )
  assert run(filter_program, {packet: repeat(0, 20)}).ret == 6
  assert (compile_forms(
    read_forms("(define (%root/e c) (bpf/packet_int c 0 1))"),
    {entry: :e, kind: :socket_filter}
  ) rescue
    :refused) == :refused
end

test "an empty program assembles to nothing and encodes to nothing"
  p = assemble([])
  assert p[:insns] == []
  assert encode(p) == []
  assert decode([]) == []
end

test "encode and decode are inverse over one instruction of every shape"
  every = [
    alu(:add, 1, r(2)),
    alu(:add, 1, -5),
    alu32(:xor, 3, r(4)),
    alu(:sdiv, 1, r(2)),
    alu(:movsx16, 1, r(2)),
    neg(9),
    neg(9, 32),
    swap(:be, 1, 32),
    swap(:any, 1, 16),
    jump(:sle, 1, -1, 3),
    jump32(:set, 1, r(2), -3),
    ja(100_000, true),
    call(:map_lookup_elem),
    call_kfunc(991),
    load(:dw, 1, 10, -8),
    load_signed(:h, 1, 2, 3),
    store(:b, 10, -1, r(1)),
    store(:w, 10, -4, -9),
    atomic(:fetch_add, :dw, 1, 8, 2),
    atomic(:cmpxchg, :w, 1, 0, 2),
    imm64(1, -2),
    exit_program
  ]
  p = assemble(every)
  back = decode(encode(p))
  assert size(back) == size(every)
  assert encode({insns: back}) == encode(p)
end

test "a known program encodes to the bytes the ISA states, checked by hand"
  p = assemble([alu(:mov, 0, 1), exit_program])
  assert encode(p) == [183, 0, 0, 0, 1, 0, 0, 0, 149, 0, 0, 0, 0, 0, 0, 0]
  assert encode_insn(store(:dw, 10, -8, r(1))) ==
    [123, 26, 248, 255, 0, 0, 0, 0]
end

test "labels resolve across imm64's two slots and forward and back"
  p = assemble(
    [
      label(:top),
      jump(:eq, 1, 0, :out),
      imm64(2, 1),
      ja(:top),
      label(:out),
      exit_program
    ]
  )
  assert p[:insns][0][:off] == 3
  assert p[:insns][2][:off] == -4
end

test "the moves RFC 9669 does not define are refused where they are written"
  assert (alu32(:movsx32, 1, r(2)) rescue :refused) == :refused
  assert (alu(:movsx8, 1, 3) rescue :refused) == :refused
  assert (load_signed(:dw, 1, 2, 0) rescue :refused) == :refused
  assert (atomic(:add, :b, 1, 0, 2) rescue :refused) == :refused
end

test "a label placed twice, a missing one and a jump too far each refuse"
  assert (assemble([label(:a), label(:a)]) rescue :refused) == :refused
  assert (assemble([ja(:gone)]) rescue :refused) == :refused
  assert (assemble([ja(40000)]) rescue :refused) == :refused
end

test "the machine computes wrapping, division by zero and 32-bit clearing as the RFC states"
  wrap = assemble(
    [imm64(0, 9_223_372_036_854_775_807), alu(:add, 0, 1), exit_program]
  )
  assert run(wrap).ret == shift_left(1, 63)
  div0 = assemble([alu(:mov, 0, 7), alu(:div, 0, r(1)), exit_program])
  assert run(div0, {ctx: []}).ret != nil
  zero = assemble(
    [alu(:mov, 1, 0), alu(:mov, 0, 7), alu(:div, 0, r(1)), exit_program]
  )
  assert run(zero).ret == 0
  mod0 = assemble(
    [alu(:mov, 1, 0), alu(:mov, 0, 7), alu(:mod, 0, r(1)), exit_program]
  )
  assert run(mod0).ret == 7
  clear = assemble([imm64(0, -1), alu32(:add, 0, 1), exit_program])
  assert run(clear).ret == 0
  sx = assemble([alu(:mov, 1, 255), alu(:movsx8, 0, r(1)), exit_program])
  assert run(sx).ret == -1
  sdiv = assemble(
    [
      imm64(0, shift_left(1, 63)),
      alu(:mov, 1, -1),
      alu(:sdiv, 0, r(1)),
      exit_program
    ]
  )
  assert run(sdiv).ret == shift_left(1, 63)
end

test "the machine's 32-bit forms read their operands as 32 bits, signed where the operation is"
  low = imm64(1, -1)
  assert run(
    assemble(
      [
        low,
        alu32(:mov, 0, 3),
        jump32(:slt, 1, 0, 1),
        alu(:mov, 0, 4),
        exit_program
      ]
    )
  ).ret == 3
  assert run(
    assemble(
      [
        low,
        alu32(:mov, 0, 3),
        jump32(:lt, 1, 0, 1),
        alu(:mov, 0, 4),
        exit_program
      ]
    )
  ).ret == 4
  assert run(
    assemble([imm64(0, 4_294_967_280), alu32(:arsh, 0, 2), exit_program])
  ).ret == 4_294_967_292
  assert run(
    assemble([imm64(0, 4_294_967_289), alu32(:sdiv, 0, 2), exit_program])
  ).ret == 4_294_967_293
  assert run(
    assemble([imm64(0, 4_294_967_289), alu32(:smod, 0, 3), exit_program])
  ).ret == 4_294_967_295
  assert run(assemble([imm64(0, 511), swap(:le, 0, 16), exit_program])).ret ==
    511
  assert run(assemble([imm64(0, 65536), swap(:le, 0, 16), exit_program])).ret ==
    0
  assert run(assemble([imm64(0, 511), swap(:be, 0, 16), exit_program])).ret ==
    65281
end

test "the machine's helpers: a seeded random, the packet head moved, and a signed remainder"
  rolled = run(assemble([call(:get_prandom_u32), exit_program]), {seed: 1})
  assert rolled.ret == 1_103_527_590
  assert run(assemble([call(:get_prandom_u32), exit_program]), {seed: 2}).ret !=
    rolled.ret
  moved = assemble([alu(:mov, 2, 1), call(:xdp_adjust_head), exit_program])
  st = run(moved, {packet: [1, 2, 3]})
  assert st.ret == 0
  assert packet_of(st) == [2, 3]
  too_far = assemble([alu(:mov, 2, 9), call(:xdp_adjust_head), exit_program])
  assert run(too_far, {packet: [1, 2, 3]}).ret == -22
  assert run(
    assemble([alu(:mov, 0, -7), alu(:smod, 0, 3), exit_program])
  ).ret == -1
  assert run(
    assemble([alu(:mov, 0, -7), alu(:sdiv, 0, 2), exit_program])
  ).ret == -3
end

test "the legacy packet reads print as LLVM prints them"
  assert text(load_abs(:b, 14)) == "r0 = *(u8 *) skb[14]"
  assert text(load_ind(:h, 7, 14)) == "r0 = *(u16 *) skb[r7 + 14]"
end

test "an XDP program reads its packet through xdp_md and returns an action"
  p = assemble(
    [
      load(:w, 2, 1, 0),
      load(:w, 3, 1, 4),
      alu(:mov, 4, r(2)),
      alu(:add, 4, 1),
      alu(:mov, 0, 1),
      jump(:gt, 4, r(3), :out),
      load(:b, 0, 2, 0),
      label(:out),
      exit_program
    ]
  )
  assert run(p, {packet: [9, 8]}).ret == 9
  assert run(p, {packet: []}).ret == 1
end

test "a map lookup and update through helpers, read back from the machine"
  m = declare_map(:counts, :array, 4, 8, 4)
  p = assemble(
    [
      store(:w, 10, -4, 2),
      alu(:mov, 2, r(10)),
      alu(:add, 2, -4),
      map_ref(1, :counts),
      call(:map_lookup_elem),
      jump(:eq, 0, 0, :out),
      alu(:mov, 1, 5),
      atomic(:add, :dw, 0, 0, 1),
      label(:out),
      alu(:mov, 0, 0),
      exit_program
    ]
  )
  st = run(p, {maps: [m]})
  assert map_value(st, :counts, [2, 0, 0, 0]) == [5, 0, 0, 0, 0, 0, 0, 0]
  assert map_value(st, :counts, [1, 0, 0, 0]) == [0, 0, 0, 0, 0, 0, 0, 0]
  assert map_value(st, :counts, [9, 0, 0, 0]).nil?
end

test "a hash map holds what is put, misses what is not, and gives back after delete"
  m = declare_map(:h, :hash, 4, 8, 2)
  p = assemble(
    [
      store(:w, 10, -4, 7),
      store(:dw, 10, -16, 99),
      map_ref(1, :h),
      alu(:mov, 2, r(10)),
      alu(:add, 2, -4),
      alu(:mov, 3, r(10)),
      alu(:add, 3, -16),
      alu(:mov, 4, 0),
      call(:map_update_elem),
      exit_program
    ]
  )
  st = run(p, {maps: [m]})
  assert st[:ret] == 0
  assert map_value(st, :h, [7, 0, 0, 0]) == [99, 0, 0, 0, 0, 0, 0, 0]
  assert map_value(st, :h, [8, 0, 0, 0]).nil?
end

test "a subprogram call keeps r6 to r9 and returns in r0"
  p = assemble(
    [
      alu(:mov, 6, 40),
      alu(:mov, 1, 1),
      call_local(:f),
      alu(:add, 0, r(6)),
      exit_program,
      label(:f),
      alu(:mov, 6, 1000),
      alu(:mov, 0, r(1)),
      alu(:add, 0, 1),
      exit_program
    ]
  )
  assert run(p).ret == 42
end

test "a ring buffer event reaches the machine's events, and a discard does not"
  p = assemble(
    [
      map_ref(1, :e),
      alu(:mov, 2, 4),
      alu(:mov, 3, 0),
      call(:ringbuf_reserve),
      jump(:eq, 0, 0, :out),
      store(:w, 0, 0, 7),
      alu(:mov, 1, r(0)),
      alu(:mov, 2, 0),
      call(:ringbuf_submit),
      label(:out),
      alu(:mov, 0, 0),
      exit_program
    ]
  )
  st = run(p, {maps: [declare_map(:e, :ringbuf, 0, 0, 4096)]})
  assert st[:events] == [[7, 0, 0, 0]]
end

test "an uninitialised escape, a runaway and an unknown helper are faults, not answers"
  assert (run(assemble([load(:b, 0, 10, 5), exit_program])) rescue :refused) ==
    :refused
  assert (run(assemble([label(:top), ja(:top)]), {max_steps: 50}) rescue
    :refused) == :refused
  assert (run(assemble([call(:loop), exit_program])) rescue :refused) ==
    :refused
end

test "text matches the assembly LLVM takes, for a control over jumps and memory"
  assert text(jump(:ne, 1, r(2), 3)) == "if r1 != r2 goto +3"
  assert text(jump32(:slt, 1, 5, -3)) == "if w1 s< 5 goto -3"
  assert text(ja(0)) == "goto +0"
  assert text(call(5)) == "call 5"
  assert text(atomic(:add, :dw, 1, 0, 2)) == "lock *(u64 *)(r1 + 0) += r2"
  assert text(atomic(:fetch_add, :w, 1, 8, 2)) ==
    "w2 = atomic_fetch_add((u32 *)(r1 + 8), w2)"
  assert text(swap(:be, 1, 16)) == "r1 = be16 r1"
  assert text(alu(:movsx32, 1, r(2))) == "r1 = (s32)r2"
end

@doc """
compiled_source: a compiled program from resolved text, entry `e`, faulting to 9.

    compiled_source("(define (%root/e c) 1)")[:name] #=> "e"
"""
def compiled_source(text, kind?)
  compile_forms(read_forms(text), {entry: :e, kind: kind or :xdp, on_fault: 9})
end

@doc """
answer: what resolved text answers on the machine.

    answer("(define (%root/e c) 1)") #=> 1
"""
def answer(text, packet?)
  run(compiled_source(text), {packet: packet or []}).ret
end

@doc """
refusal_of: the compile error resolved text gets, nil when it compiles.

    refusal_of("(define (%root/e c) 1)").nil? #=> true
    contains?(refusal_of("(define (%root/e c) (/ 1 2))"), "fraction") #=> true
"""
def refusal_of(text)
  compiled_source(text)
  nil
rescue :bpf_compile as e
  e.message
end

test "compiled arithmetic answers as blue answers, and a literal's range proves its check away"
  assert answer("(define (%root/e c) (+ 40 2))") == 42
  assert answer("(define (%root/e c) (- 40 2))") == 38
  assert answer("(define (%root/e c) (- 5))") == -5
  assert answer("(define (%root/e c) (* 6 7))") == 42
  assert answer("(define (%root/e c) (mod 7 3))") == 1
  assert answer("(define (%root/e c) (mod (- 0 7) 3))") == 2
  assert answer("(define (%root/e c) (bit_and 12 10))") == 8
  assert answer("(define (%root/e c) (bit_or 12 10))") == 14
  assert answer("(define (%root/e c) (bit_xor 12 10))") == 6
  assert answer("(define (%root/e c) (bit_not 0))") == -1
  assert answer("(define (%root/e c) (shift_left 1 4))") == 16
  assert answer("(define (%root/e c) (shift_right (- 0 8) 1))") == -4
  assert answer("(define (%root/e c) (shift_right_logical (- 0 1) 60))") == 15
  assert answer("(define (%root/e c) (wrapping_add 1 2))") == 3
  assert answer("(define (%root/e c) (wrapping_sub 1 2))") == -1
  assert answer("(define (%root/e c) (wrapping_mul 3 4))") == 12
  assert answer("(define (%root/e c) (unsigned_div 9 2))") == 4
  assert answer("(define (%root/e c) (unsigned_mod 9 2))") == 1
  assert compiled_source("(define (%root/e c) (+ 40 2))")[:report][:checks] == 0
  assert compiled_source("(define (%root/e c) (+ 40 2))")[:report][:proven] == 1
end

test "an overflow, a zero divisor and a bad shift are the declared fault, where blue raises"
  input = [255, 255, 255, 255, 255, 255, 255, 127, 0, 0, 0, 0, 0, 0, 0, 1]
  read = "(bpf/packet_int c 0 8)"
  assert answer(
    "(define (%root/e c) (begin (define a #{read}) (+ a 0)))",
    repeat(0, 8)
  ) == 0
  assert answer(
    "(define (%root/e c) (+ (bpf/packet_int c 0 8) (bpf/packet_int c 8 8)))",
    input
  ) != nil
  big = append(
    [127, 255, 255, 255, 255, 255, 255, 255],
    [0, 0, 0, 0, 0, 0, 0, 1]
  )
  assert answer(
    "(define (%root/e c) (+ (bpf/packet_int c 0 8) (bpf/packet_int c 8 8)))",
    big
  ) == 9
  assert answer(
    "(define (%root/e c) (- (- 0 (bpf/packet_int c 0 8)) (bpf/packet_int c 0 8)))",
    append([127, 255, 255, 255, 255, 255, 255, 255], [])
  ) == 9
  assert answer(
    "(define (%root/e c) (unsigned_div 1 (bpf/packet_int c 0 1)))",
    [0]
  ) == 9
  assert answer(
    "(define (%root/e c) (shift_left 1 (bpf/packet_int c 0 1)))",
    [64]
  ) == 9
  assert answer("(define (%root/e c) (bpf/packet_int c 4 1))", [1, 2]) == 9
end

test "comparisons, and, or, not and if lower with blue's meaning of each"
  assert answer("(define (%root/e c) (if (< 1 2) 7 8))") == 7
  assert answer("(define (%root/e c) (if (<= 3 2) 7 8))") == 8
  assert answer("(define (%root/e c) (if (> 3 2) 7 8))") == 7
  assert answer("(define (%root/e c) (if (>= 2 2) 7 8))") == 7
  assert answer("(define (%root/e c) (if (equal? 2 2) 7 8))") == 7
  assert answer("(define (%root/e c) (if (not= 2 2) 7 8))") == 8
  assert answer("(define (%root/e c) (if (unsigned_less? 1 (- 0 1)) 7 8))") == 7
  assert answer("(define (%root/e c) (if (and (< 1 2) (< 2 3)) 7 8))") == 7
  assert answer("(define (%root/e c) (if (and (< 2 1) (< 2 3)) 7 8))") == 8
  assert answer("(define (%root/e c) (if (or (< 2 1) (< 2 3)) 7 8))") == 7
  assert answer("(define (%root/e c) (if (not (< 2 1)) 7 8))") == 7
  assert answer("(define (%root/e c) (if true 7 8))") == 7
  assert answer("(define (%root/e c) (if false 7 8))") == 8
end

test "locals rebind in place, calls inline, and a tail call is a loop"
  assert answer("(define (%root/e c) (begin (define x 1) (define x (+ x 1)) x))") ==
    2
  assert answer("(define (%root/e c) (begin (define x 1) (if (< x 2) (define x 5)) x))") ==
    5
  assert answer("(define (%root/g a b) (+ a b)) (define (%root/e c) (%root/g 40 2))") ==
    42
  assert answer("(define %root/K 40) (define (%root/e c) (+ %root/K 2))") == 42
  assert answer("(define %root/K (- 40)) (define (%root/e c) (+ %root/K 42))") ==
    2
  text = "(define (%root/s i acc) (if (>= i 5) acc (%root/s (+ i 1) (+ acc i)))) (define (%root/e c) (%root/s 0 0))"
  assert answer(text) == 10
end

test "a value that may be absent narrows on .nil? and takes a default with or"
  m = "(define %root/M (bpf/declare_map :m :hash 4 8 4))"
  absent = "#{m} (define (%root/e c) (begin (define x (bpf/map_get %root/M 1)) (if (blue-field x :nil?) 7 x)))"
  assert run(
    compiled_source(absent),
    {maps: [declare_map(:m, :hash, 4, 8, 4)]}
  ).ret == 7
  put = "#{m} (define (%root/e c) (begin (bpf/map_put %root/M 1 41) (define x (bpf/map_get %root/M 1)) (if (blue-field x :nil?) 7 (+ x 1))))"
  assert run(
    compiled_source(put),
    {maps: [declare_map(:m, :hash, 4, 8, 4)]}
  ).ret == 42
  fallback = "#{m} (define (%root/e c) (or (bpf/map_get %root/M 1) 5))"
  assert run(
    compiled_source(fallback),
    {maps: [declare_map(:m, :hash, 4, 8, 4)]}
  ).ret == 5
  bare = "#{m} (define (%root/e c) (begin (define x (bpf/map_get %root/M 1)) (+ x 1)))"
  assert contains?(refusal_of(bare), "may be absent")
end

test "the map words add, delete and put through the machine's maps"
  m = "(define %root/M (bpf/declare_map :m :hash 4 8 4))"
  spec = [declare_map(:m, :hash, 4, 8, 4)]
  added = "#{m} (define (%root/e c) (begin (bpf/map_add %root/M 3 2) (bpf/map_add %root/M 3 5) (or (bpf/map_get %root/M 3) 0)))"
  assert run(compiled_source(added), {maps: spec}).ret == 7
  gone = "#{m} (define (%root/e c) (begin (bpf/map_put %root/M 3 1) (if (bpf/map_delete %root/M 3) (if (bpf/map_delete %root/M 3) 1 2) 3)))"
  assert run(compiled_source(gone), {maps: spec}).ret == 2
end

test "emit sends a record of values, and helper reaches a kernel helper by name"
  e = "(define %root/E (bpf/declare_map :e :ringbuf 0 0 4096))"
  sent = "#{e} (define (%root/e c) (begin (bpf/emit %root/E (list 7 9)) 2))"
  st = run(
    compiled_source(sent),
    {maps: [declare_map(:e, :ringbuf, 0, 0, 4096)]}
  )
  assert st.events == [[7, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0]]
  asked = "(define (%root/e c) (bpf/helper :ktime_get_ns))"
  assert run(compiled_source(asked), {now_ns: 5}).ret == 5
end

test "the packet words read and write in network order, and packet_len counts"
  assert answer("(define (%root/e c) (bpf/packet_int c 0 2))", [1, 2]) == 258
  assert answer("(define (%root/e c) (bpf/packet_int c (+ 0 1) 1))", [1, 2]) ==
    2
  assert answer("(define (%root/e c) (bpf/packet_len c))", [1, 2, 3]) == 3
  assert answer("(define (%root/e c) (bpf/packet_int c 1 2))", [1, 2]) == 9
  assert answer("(define (%root/e c) (bpf/packet_int c 1 2))", [1, 2, 3]) == 515
  put = compiled_source("(define (%root/e c) (begin (bpf/packet_put c 1 2 258) 2))")
  assert packet_of(run(put, {packet: [0, 0, 0]})) == [0, 1, 2]
  ctx = compile_forms(
    read_forms("(define (%root/e c) (bpf/ctx_int c 0 4))"),
    {entry: :e, kind: :tracepoint}
  )
  assert run(ctx, {ctx: [7, 0, 0, 0]}).ret == 7
end

test "the XDP action words are the kernel's numbers, and each lowers to its number"
  assert answer("(define (%root/e c) (bpf/xdp_pass))") == xdp_pass
  assert answer("(define (%root/e c) bpf/xdp_drop)") == xdp_drop
  assert answer("(define (%root/e c) (bpf/xdp_tx))") == xdp_tx
  assert answer("(define (%root/e c) (bpf/xdp_aborted))") == xdp_aborted
end

test "what the position has no lowering for is refused by name, never compiled wrong"
  assert contains?(refusal_of("(define (%root/e c) (/ 7 2))"), "fraction")
  assert contains?(
    refusal_of("(define (%root/e c) (concat 1 2))"),
    "no lowering"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (if 1 2 3))"),
    "always truthy"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (* (bpf/packet_int c 0 8) (bpf/packet_int c 8 8)))"),
    "wrapping_mul"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (mod 7 (bpf/packet_int c 0 8)))"),
    "positive"
  )
  assert contains?(refusal_of("(define (%root/e c d) 1)"), "context alone")
  assert contains?(refusal_of("(define (%root/x c) 1)"), "no definition named")
  assert contains?(
    refusal_of("(define (%root/g a) (+ 1 (%root/g a))) (define (%root/e c) (%root/g 1))"),
    "recurses"
  )
  assert contains?(
    refusal_of("(define (%root/g a) a) (define (%root/e c) (%root/g 1 2))"),
    "takes 1 arguments"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (bpf/map_get 1 2))"),
    "declared at the top level"
  )
  assert contains?(refusal_of("(define (%root/e c) unknown)"), "not a local")
  assert contains?(refusal_of("(define (%root/e c) \"text\")"), "no lowering")
  assert contains?(
    refusal_of("(define (%root/e c) (begin (define x (bpf/map_delete %root/M 1)) 1))"),
    "declared"
  )
end

test "a program that needs more than the verifier's stack is refused before it reaches the verifier"
  names = map((i) -> "(define v#{to_s(i)} #{to_s(i)})", range(0, 70))
  text = "(define (%root/e c) (begin #{join(names, " ")} 1))"
  assert contains?(refusal_of(text), "64 stack slots")
end

test "the report counts what was emitted against what was proven"
  checked = compiled_source("(define (%root/e c) (begin (define a (bpf/packet_int c 0 8)) (+ a a)))")
  assert checked[:report][:checks] == 1
  assert checked[:report][:slots] >= 1
  assert checked[:report][:insns] > 5
  assert checked[:name] == "e"
  assert checked[:kind] == :xdp
end

test "kernel_read compiles to a field the loader binds, and the bound program reads it"
  text = "(define (%root/e c) (bpf/kernel_read (bpf/helper :get_current_task) \"task_struct\" (list \"pid\") 4))"
  p = compiled_source(text, :tracing)
  assert size(p[:fields]) == 1
  assert first(p[:fields])[:struct] == "task_struct"
  assert first(p[:fields])[:path] == ["pid"]
  bound = bind_fields(p, (_s, _path) -> {offset: 4, size: 4})
  assert bound[:fields] == []
  memory = {at: 805_306_368, bytes: [0, 0, 0, 0, 42, 0, 0, 0]}
  assert run(bound, {kernel: memory}).ret == 42
  assert run(bound, {kernel: {at: 805_306_368, bytes: [1]}}).ret == 9
  moved = bind_fields(p, (_s, _path) -> {offset: 0, size: 4})
  assert run(
    moved,
    {kernel: {at: 805_306_368, bytes: [7, 0, 0, 0, 42, 0, 0, 0]}}
  ).ret == 7
end

test "a field whose size changed on this kernel refuses, and an unbound size or name refuses at compile"
  text = "(define (%root/e c) (bpf/kernel_read 0 \"s\" (list \"f\") 4))"
  p = compiled_source(text, :tracing)
  assert (bind_fields(p, (_s, _path) -> {offset: 0, size: 8}) rescue
    :refused) == :refused
  assert contains?(
    refusal_of("(define (%root/e c) (bpf/kernel_read 0 \"s\" (list \"f\") 3))"),
    "literal size"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (bpf/kernel_read 0 1 (list \"f\") 4))"),
    "literal string"
  )
  assert contains?(
    refusal_of("(define (%root/e c) (bpf/kernel_read 0 \"s\" 1 4))"),
    "literal list"
  )
end
