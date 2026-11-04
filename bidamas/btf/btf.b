@moduledoc """
btf — the BPF Type Format as data: the kernel's own description of its types, read from `/sys/kernel/btf/vmlinux`, so a program finds a hook's id and a field's offset on the kernel it runs on.

`read` takes the bytes of a BTF blob. `find` gives a named type's id, `type_at` a type by id, and `field` walks a struct to a member, through anonymous unions, to its offset and size in bytes. A CO-RE relocation is this lookup at load time.

    b = read(sample)
    find(b, "task", :struct) #=> 2
    field(b, "task", ["pid"]).offset #=> 4
    field(b, "task", ["pid"]).size #=> 4
"""

use("baito", %i[bytes_int layout pack width])
use("retsu", %i[first flat_map index_of rest size])

@doc """
kinds: BTF's kinds in the order of their numbers, from `include/uapi/linux/btf.h`.

    nth(4, kinds) #=> :struct
    nth(12, kinds) #=> :func
"""
def kinds()
  %i[
    void
    int
    ptr
    array
    struct
    union
    enum
    fwd
    typedef
    volatile
    const
    restrict
    func
    func_proto
    var
    datasec
    float
    decl_tag
    type_tag
    enum64
  ]
end

@doc """
word_at: the little-endian 32-bit word at a byte position.

    word_at([1, 0, 0, 0], 0) #=> 1
"""
def word_at(bytes, at)
  bytes_int(bytes, at, 4)
end

@doc """
header_of: a blob's section offsets, each from the blob's start.

    header_of(sample)[:type_off] #=> 24
"""
def header_of(bytes)
  if length(bytes) < 24 or bytes_int(bytes, 0, 2) != 60319
    raise(:decode_error, "these bytes are not BTF: the magic is not 0xeB9F")
  end
  length_of_header = word_at(bytes, 4)
  {
    header: length_of_header,
    type_off: length_of_header + word_at(bytes, 8),
    type_len: word_at(bytes, 12),
    str_off: length_of_header + word_at(bytes, 16),
    str_len: word_at(bytes, 20)
  }
end

@doc """
words_from: whole words from a byte position.

    words_from([1, 0, 0, 0, 2, 0, 0, 0], 0, 2) #=> [1, 2]
"""
def words_from(bytes, at, count)
  map((i) -> word_at(bytes, at + i * 4), range(0, count))
end

@doc """
trailing_words: the words a type of this kind number and member count takes past its three.

    trailing_words(4, 2) #=> 6
    trailing_words(8, 0) #=> 0
"""
def trailing_words(kind, vlen)
  case kind
  when 1
    1
  when 3
    3
  when 4
    vlen * 3
  when 5
    vlen * 3
  when 6
    vlen * 2
  when 13
    vlen * 2
  when 14
    1
  when 15
    vlen * 3
  when 17
    1
  when 19
    vlen * 3
  else
    0
  end
end

@doc """
index_step: one type added to the index, and where the next starts.

    index_step({at: 0, next_id: 1, starts: {}, by_name: {}}, [0, shift_left(8, 24), 0])[:at] #=> 3
"""
def index_step(acc, words)
  at = acc[:at]
  info = words[at + 1]
  kind = bit_and(shift_right_logical(info, 24), 31)
  vlen = bit_and(info, 65535)
  name = words[at]
  id = acc[:next_id]
  named = if name == 0
    acc[:by_name]
  else
    assoc(acc[:by_name], name, append(get(acc[:by_name], name) or [], [id]))
  end
  {
    at: at + 3 + trailing_words(kind, vlen),
    next_id: id + 1,
    starts: assoc(acc[:starts], id, at),
    by_name: named
  }
end

@doc """
type_index: where each type starts and each name's ids, from the type words.

    type_index([0, shift_left(8, 24), 0])[:next_id] #=> 2
    type_index([])[:next_id] #=> 1
"""
def type_index(words)
  count = length(words)
  acc = {at: 0, next_id: 1, starts: {}, by_name: {}}
  while(acc[:at] < count, set!(acc, index_step(acc, words)))
  acc
end

@doc """
nul: the one-character string a string section separates names with.

    text_bytes(nul) #=> [0]
"""
def nul()
  bytes_text([0])
end

@doc """
strings_step: one name added to the string tables, at its byte offset.

    strings_step({from: 0, to_offset: {}, to_name: {}}, "ab")[:from] #=> 3
"""
def strings_step(acc, name)
  from = acc[:from]
  {
    from: from + length(text_bytes(name)) + 1,
    to_offset: assoc(acc[:to_offset], name, from),
    to_name: assoc(acc[:to_name], from, name)
  }
end

@doc """
string_tables: the string section's names by offset and offsets by name.

    get(string_tables("ab")[:to_offset], "ab") #=> 0
"""
def string_tables(text)
  reduce(strings_step, {from: 0, to_offset: {}, to_name: {}}, split(text, nul))
end

@doc """
table_of: the type table from type words and string bytes, refusing strings that are not UTF-8.

    table_of([], [0])[:count] #=> 0
    (table_of([], [255]) rescue :refused) #=> :refused
"""
def table_of(words, strings)
  text = bytes_text(strings)
  if text.nil?
    raise(:decode_error, "this BTF's string section is not UTF-8")
  end
  tables = string_tables(text)
  index = type_index(words)
  {
    words:,
    starts: index[:starts],
    by_name: index[:by_name],
    to_offset: tables[:to_offset],
    to_name: tables[:to_name],
    count: index[:next_id] - 1
  }
end

@doc """
read: a BTF blob's bytes as a table of its types. Bytes that are no BTF raise :decode_error.

    read(sample)[:count] #=> 6
    (read([1, 2, 3]) rescue :refused) #=> :refused
"""
def read(bytes)
  h = header_of(bytes)
  table_of(
    words_from(bytes, h[:type_off], floor(h[:type_len] / 4)),
    map((i) -> bytes[h[:str_off] + i], range(0, h[:str_len]))
  )
end

@doc """
open: the BTF blob a file holds, reading its sections as words and text rather than byte by byte.

    (open("/no/such/btf") rescue :refused) #=> :refused
"""
def open(path)
  h = header_of(read_bytes(path, 0, 24))
  table_of(
    read_u32s(path, h[:type_off], floor(h[:type_len] / 4)),
    read_bytes(path, h[:str_off], h[:str_len])
  )
end

@doc """
vmlinux_path: where a running kernel publishes its own types; `open` reads it.

    vmlinux_path #=> "/sys/kernel/btf/vmlinux"
"""
def vmlinux_path()
  "/sys/kernel/btf/vmlinux"
end

@doc """
name_of: the name at a string offset, empty when there is none.

    name_of(read(sample), 1) #=> "int"
    name_of(read(sample), 999) #=> ""
"""
def name_of(b, offset)
  get(b[:to_name], offset) or ""
end

@doc """
member_of: the struct member whose three words start here.

    member_of(read(sample), 7)[:name] #=> "state"
"""
def member_of(b, at)
  raw = b[:words][at + 2]
  {name: name_of(b, b[:words][at]), type: b[:words][at + 1], bits: raw}
end

@doc """
type_at: the type with this id as a record: {id:, kind:, name:, size:, type:}, and `members` for a struct or union. Id 0 is void; an id past the table is nil.

    type_at(read(sample), 1).kind #=> :int
    type_at(read(sample), 0).kind #=> :void
    type_at(read(sample), 99).nil? #=> true
"""
def type_at(b, id)
  if id == 0
    {id: 0, kind: :void, name: "", size: 0}
  else
    at = get(b[:starts], id)
    if at.nil?
      nil
    else
      words = b[:words]
      info = words[at + 1]
      kind = kinds[bit_and(shift_right_logical(info, 24), 31)]
      vlen = bit_and(info, 65535)
      extra = words[at + 2]
      base = {
        id:,
        kind:,
        name: name_of(b, words[at]),
        vlen:,
        size: extra,
        type: extra
      }
      if member?(kind, %i[struct union])
        assoc(
          base,
          :members,
          map((i) -> member_of(b, at + 3 + i * 3), range(0, vlen))
        )
      elsif kind == :array
        assoc(assoc(base, :element, words[at + 3]), :count, words[at + 5])
      elsif kind == :func_proto
        assoc(
          base,
          :params,
          map(
            fn(i)
              {
                name: name_of(b, words[at + 3 + i * 2]),
                type: words[at + 4 + i * 2]
              }
            end,
            range(0, vlen)
          )
        )
      elsif kind == :datasec
        assoc(
          base,
          :vars,
          map(
            fn(i)
              {
                type: words[at + 3 + i * 3],
                offset: words[at + 4 + i * 3],
                size: words[at + 5 + i * 3]
              }
            end,
            range(0, vlen)
          )
        )
      else
        base
      end
    end
  end
end

@doc """
find: the id of the type of this name and kind, nil when this table has none.

    find(read(sample), "int", :int) #=> 1
    find(read(sample), "task", :union).nil? #=> true
    find(read(sample), "nothing", :struct).nil? #=> true
"""
def find(b, name, kind)
  offset = get(b[:to_offset], name)
  if offset.nil?
    nil
  else
    ids = get(b[:by_name], offset) or []
    retsu::find_first((id) -> type_at(b, id)[:kind] == kind, ids)
  end
end

@doc """
need: the id of the type of this name and kind, and raises :not_found naming it when this table has none.

    need(read(sample), "int", :int) #=> 1
    (need(read(sample), "nothing", :int) rescue :refused) #=> :refused
"""
def need(b, name, kind)
  id = find(b, name, kind)
  if id.nil?
    raise(:not_found, "this kernel's BTF has no #{to_s(kind)} #{name}")
  end
  id
end

@doc """
resolved: the type behind typedefs and qualifiers.

    resolved(read(sample), 3).kind #=> :int
"""
def resolved(b, id)
  t = type_at(b, id)
  if t.nil?
    raise(:decode_error, "no BTF type #{to_s(id)}")
  elsif member?(t[:kind], %i[typedef volatile const restrict type_tag])
    resolved(b, t[:type])
  else
    t
  end
end

@doc """
size_of: a type's size in bytes, through typedefs, qualifiers and arrays. A pointer is 8.

    size_of(read(sample), 1) #=> 4
    size_of(read(sample), 3) #=> 4
    size_of(read(sample), 2) #=> 16
"""
def size_of(b, id)
  t = resolved(b, id)
  case t[:kind]
  when :ptr
    8
  when :array
    t[:count] * size_of(b, t[:element])
  else
    t[:size]
  end
end

@doc """
bit_offset: a member's bit offset, a bitfield's size taken off when its struct says.

    bit_offset({bits: 32}, false) #=> 32
    bit_offset({bits: shift_left(3, 24) + 8}, true) #=> 8
"""
def bit_offset(m, struct_kind_flag)
  if struct_kind_flag
    bit_and(m[:bits], 16_777_215)
  else
    m[:bits]
  end
end

@doc """
kind_flag_of: whether a struct's members carry bitfield sizes.

    kind_flag_of(read(sample), 2) #=> false
"""
def kind_flag_of(b, id)
  at = get(b[:starts], id)
  bit_and(shift_right_logical(b[:words][at + 1], 31), 1) == 1
end

@doc """
member_search: a member by name, searching anonymous unions and adding their offsets.

    member_search(read(sample), type_at(read(sample), 2), "inner")[:bits] #=> 64
    member_search(read(sample), type_at(read(sample), 2), "gone").nil? #=> true
"""
def member_search(b, t, name)
  flagged = kind_flag_of(b, t[:id])
  reduce(
    fn(found, m)
      if found != nil
        found
      elsif m[:name] == name
        {bits: bit_offset(m, flagged), type: m[:type]}
      elsif m[:name] == ""
        inner = resolved(b, m[:type])
        if member?(inner[:kind], %i[struct union])
          deeper = member_search(b, inner, name)
          if deeper.nil?
            nil
          else
            {bits: bit_offset(m, flagged) + deeper[:bits], type: deeper[:type]}
          end
        end
      end
    end,
    nil,
    t[:members]
  )
end

@doc """
walk: a type and bit offset at the end of a path of member names.

    walk(read(sample), 2, 0, ["pid"])[:bits] #=> 32
"""
def walk(b, at_type, bits, path)
  if path == []
    {type: at_type, bits:}
  else
    t = resolved(b, at_type)
    if not member?(t[:kind], %i[struct union])
      raise(
        :not_found,
        "#{t[:name]} is no struct, so it has no field #{to_s(first(path))}"
      )
    end
    m = member_search(b, t, first(path))
    if m.nil?
      raise(
        :not_found,
        "#{t[:name]} has no field #{to_s(first(path))} on this kernel"
      )
    end
    walk(b, m[:type], bits + m[:bits], rest(path))
  end
end

@doc """
field: a named struct's field by its path of member names, through anonymous unions: {offset:, size:, type:}, offset and size in bytes. A bitfield, or a field this kernel's struct does not have, raises by name.

    field(read(sample), "task", ["pid"]).offset #=> 4
    field(read(sample), "task", ["state"]).offset #=> 0
    field(read(sample), "task", ["inner"]).size #=> 4
    (field(read(sample), "task", ["nope"]) rescue :refused) #=> :refused
"""
def field(b, struct_name, path)
  id = need(b, struct_name, :struct)
  got = walk(b, id, 0, path)
  if got[:bits] % 8 != 0
    raise(:bad_option, "#{struct_name}.#{join(path, ".")} is a bitfield")
  end
  {
    offset: floor(got[:bits] / 8),
    size: size_of(b, got[:type]),
    type: got[:type]
  }
end

@doc """
function_id: the id of a kernel function, what a tracing or LSM program names as its target. An LSM hook's function is `bpf_lsm_` and the hook's name.

    function_id(read(sample), "run") #=> 5
    (function_id(read(sample), "nothing") rescue :refused) #=> :refused
"""
def function_id(b, name)
  need(b, name, :func)
end

@doc """
member_index: a member's place among its struct's own members, what a :struct_ops program names at load. A struct with no such member raises.

    member_index(read(sample), "task", "pid") #=> 1
    (member_index(read(sample), "task", "nope") rescue :refused) #=> :refused
"""
def member_index(b, struct_name, name)
  members = type_at(b, need(b, struct_name, :struct))[:members]
  at = index_of(map((m) -> m[:name], members), name)
  if at < 0
    raise(:not_found, "#{struct_name} has no member #{name}")
  end
  at
end

@doc """
smallest: the smallest BTF blob a kernel takes: one `int`. A :struct_ops map must name a BTF object of its own, whatever its value's type.

    size(smallest) #=> 45
    type_at(read(smallest), 1).name #=> "int"
"""
def smallest()
  append(
    *[
      [159, 235, 1, 0],
      word_bytes(24),
      word_bytes(0),
      word_bytes(16),
      word_bytes(16),
      word_bytes(5),
      word_bytes(1),
      word_bytes(shift_left(1, 24)),
      word_bytes(4),
      word_bytes(32),
      [0],
      text_bytes("int"),
      [0]
    ]
  )
end

@doc """
word_bytes: a word's four little-endian bytes.

    word_bytes(258) #=> [2, 1, 0, 0]
"""
def word_bytes(n)
  map((i) -> bit_and(shift_right_logical(n, i * 8), 255), range(0, 4))
end

@doc """
sample: a small BTF blob by hand, for tests and examples: 1 `int` of 4 bytes; 2 struct `task` {state int at 0; pid at 32 bits; an anonymous union holding inner int at 64 bits}; 3 typedef `pid_t` of `int`; 4 that anonymous union; 5 func `run`; 6 a pointer to `int`.

    size(sample) > 24 #=> true
"""
def sample()
  names = %w[int task state pid inner pid_t run]
  strings = append([0], flat_map(names, (n) -> append(text_bytes(n), [0])))
  words = [
    1,
    shift_left(1, 24),
    4,
    32,
    5,
    shift_left(4, 24) + 3,
    16,
    10,
    1,
    0,
    16,
    3,
    32,
    0,
    4,
    64,
    26,
    shift_left(8, 24),
    1,
    0,
    shift_left(5, 24) + 1,
    4,
    20,
    1,
    0,
    32,
    shift_left(12, 24),
    0,
    0,
    shift_left(2, 24),
    1
  ]
  body = flat_map(words, word_bytes)
  header = append(
    *[
      [159, 235, 1, 0],
      word_bytes(24),
      word_bytes(0),
      word_bytes(length(body)),
      word_bytes(length(body)),
      word_bytes(length(strings))
    ]
  )
  append(*[header, body, strings])
end

@doc """
int_type: an integer type of this many bytes, signed unless the last argument says not.

    int_type("int", 4).size #=> 4
    int_type("__u32", 4, false).signed #=> false
"""
def int_type(name, count, is_signed?)
  {kind: :int, name:, size: count, signed: is_signed != false}
end

@doc """
pointer_to: a pointer to the type with this id; 0 is void.

    pointer_to(3).type #=> 3
"""
def pointer_to(id)
  {kind: :ptr, name: "", type: id}
end

@doc """
array_of: an array of `count` elements of a type, its index of a type.

    array_of(1, 2, 8).count #=> 8
"""
def array_of(element, index, count)
  {kind: :array, name: "", element:, index:, count:}
end

@doc """
proto_type: a function's type: what it returns and its parameters, each {name:, type:}.

    proto_type(1, []).type #=> 1
"""
def proto_type(returns, params)
  {kind: :func_proto, name: "", type: returns, params:}
end

@doc """
sized_type: a type of a size holding rows: :struct, each row {name:, type:, bits:} and an empty name making it anonymous, or :datasec, each row {type:, offset:, size:}.

    sized_type(:struct, "s", 8, []).size #=> 8
    sized_type(:datasec, ".maps", 0, [])[:vars] #=> []
"""
def sized_type(kind, name, count, rows)
  key = if kind == :datasec
    :vars
  else
    :members
  end
  assoc({kind:, name:, size: count}, key, rows)
end

@doc """
linked_type: a :func or :var of a name, a type and a linkage: :static, :global or, for a function, :extern.

    linked_type(:func, "f", 2, :global).linkage #=> :global
    linked_type(:var, "v", 2, :global).type #=> 2
"""
def linked_type(kind, name, type_id, linkage)
  assoc({kind:, name:, type: type_id}, :linkage, linkage)
end

@doc """
linkage_number: a linkage's number in BTF; a name that is none raises.

    linkage_number(:global) #=> 1
    (linkage_number(:weak) rescue :refused) #=> :refused
"""
def linkage_number(linkage)
  case linkage
  when :static
    0
  when :global
    1
  when :extern
    2
  else
    raise(:bad_option, "no BTF linkage #{to_s(linkage)}")
  end
end

@doc """
intern: types with one more, or the same types when it is already there: {types:, id:}.

    intern([], int_type("int", 4)).id #=> 1
    intern([int_type("int", 4)], int_type("int", 4)).id #=> 1
"""
def intern(types, t)
  at = index_of(types, t)
  if at < 0
    {types: append(types, [t]), id: size(types) + 1}
  else
    {types:, id: at + 1}
  end
end

@doc """
names_in: every name a type holds, in the order the string section lists them.

    names_in(sized_type(:struct, "s", 4, [{name: "a", type: 1, bits: 0}])) #=> ["s", "a"]
    names_in(pointer_to(1)) #=> []
"""
def names_in(t)
  own = if t[:name] == ""
    []
  else
    [t[:name]]
  end
  inner = map((m) -> m[:name], append(t[:members] or [], t[:params] or []))
  append(own, filter((n) -> n != "", inner))
end

@doc """
strings_of: a string section and each name's offset, the empty name first: {bytes:, offsets:}.

    strings_of([], [])[:bytes] #=> [0]
    get(strings_of([int_type("int", 4)], ["xdp"])[:offsets], "xdp") #=> 5
"""
def strings_of(types, names)
  reduce(
    fn(acc, name)
      if get(acc[:offsets], name) != nil
        acc
      else
        {
          bytes: append(append(acc[:bytes], text_bytes(name)), [0]),
          offsets: assoc(acc[:offsets], name, length(acc[:bytes]))
        }
      end
    end,
    {bytes: [0], offsets: {"" => 0}},
    append(flat_map(types, names_in), names)
  )
end

@doc """
info_word: a type's second word: its kind's number, its count and its flag.

    info_word(:ptr, 0) #=> 33554432
"""
def info_word(kind, vlen)
  bit_or(shift_left(index_of(kinds, kind), 24), vlen)
end

@doc """
type_words: one type as its words, each name by its offset in `offsets`. A type of a kind this writer has no form for raises.

    size(type_words(pointer_to(1), {"" => 0})) #=> 3
    (type_words({kind: :fwd, name: ""}, {"" => 0}) rescue :refused) #=> :refused
"""
def type_words(t, offsets)
  name = get(offsets, t[:name])
  case t[:kind]
  when :int
    encoding = if t[:signed]
      1
    else
      0
    end
    [
      name,
      info_word(:int, 0),
      t[:size],
      bit_or(shift_left(encoding, 24), t[:size] * 8)
    ]
  when :ptr
    [0, info_word(:ptr, 0), t[:type]]
  when :array
    [0, info_word(:array, 0), 0, t[:element], t[:index], t[:count]]
  when :struct
    append(
      [name, info_word(:struct, size(t[:members])), t[:size]],
      flat_map(t[:members], (m) -> [get(offsets, m[:name]), m[:type], m[:bits]])
    )
  when :func_proto
    append(
      [0, info_word(:func_proto, size(t[:params])), t[:type]],
      flat_map(t[:params], (p) -> [get(offsets, p[:name]), p[:type]])
    )
  when :func
    [name, info_word(:func, linkage_number(t[:linkage])), t[:type]]
  when :var
    [name, info_word(:var, 0), t[:type], linkage_number(t[:linkage])]
  when :datasec
    append(
      [name, info_word(:datasec, size(t[:vars])), t[:size]],
      flat_map(t[:vars], (v) -> [v[:type], v[:offset], v[:size]])
    )
  else
    raise(:bad_option, "the BTF writer has no form for #{to_s(t[:kind])}")
  end
end

@doc """
header_layout: `struct btf_header`.

    width(header_layout) #=> 24
"""
def header_layout()
  layout(
    [
      %i[magic u16],
      %i[version u8],
      %i[flags u8],
      %i[hdr_len u32],
      %i[type_off u32],
      %i[type_len u32],
      %i[str_off u32],
      %i[str_len u32]
    ]
  )
end

@doc """
encode: types, each made by the words above and its id its place from 1, as a BTF blob. `names` adds strings no type holds, such as the section names `.BTF.ext` names.

    read(encode([int_type("int", 4)]))[:count] #=> 1
    read(encode([]))[:count] #=> 0
"""
def encode(types, names?)
  strings = strings_of(types, names or [])
  body = flat_map(
    flat_map(types, (t) -> type_words(t, strings[:offsets])),
    word_bytes
  )
  append(
    *[
      pack(
        header_layout,
        {
          magic: 60319,
          version: 1,
          flags: 0,
          hdr_len: 24,
          type_off: 0,
          type_len: length(body),
          str_off: length(body),
          str_len: length(strings[:bytes])
        }
      ),
      body,
      strings[:bytes]
    ]
  )
end

@doc """
ext_header_layout: `struct btf_ext_header`, through its CO-RE fields.

    width(ext_header_layout) #=> 32
"""
def ext_header_layout()
  layout(
    [
      %i[magic u16],
      %i[version u8],
      %i[flags u8],
      %i[hdr_len u32],
      %i[func_info_off u32],
      %i[func_info_len u32],
      %i[line_info_off u32],
      %i[line_info_len u32],
      %i[core_relo_off u32],
      %i[core_relo_len u32]
    ]
  )
end

@doc """
ext_section_words: one ELF section's func_info as words: its name's offset, its count, then `[byte offset, type id]`.

    ext_section_words({section: "xdp", funcs: [{at: 0, type: 2}]}, {"xdp" => 1}) #=> [1, 1, 0, 2]
"""
def ext_section_words(s, offsets)
  append(
    [get(offsets, s[:section]), size(s[:funcs])],
    flat_map(s[:funcs], (f) -> [f[:at], f[:type]])
  )
end

@doc """
ext_line_words: one ELF section's line info as words: its name's offset, its count, then `[byte offset, file, text, position]`.

    ext_line_words({section: "xdp", lines: [{at: 0, file: "f", text: "t", pos: 2051}]}, {"xdp" => 1, "f" => 5, "t" => 7}) #=> [1, 1, 0, 5, 7, 2051]
"""
def ext_line_words(s, offsets)
  append(
    [get(offsets, s[:section]), size(s[:lines])],
    flat_map(
      s[:lines],
      (l) -> [l[:at], get(offsets, l[:file]), get(offsets, l[:text]), l[:pos]]
    )
  )
end

@doc """
ext_core_words: one ELF section's CO-RE relocations as words: its name's offset, its count, then `[byte offset, type, access text, kind]`.

    ext_core_words({section: "xdp", relos: [{at: 8, type: 2, access: "0:0", kind: 0}]}, {"xdp" => 1, "0:0" => 5}) #=> [1, 1, 8, 2, 5, 0]
"""
def ext_core_words(s, offsets)
  append(
    [get(offsets, s[:section]), size(s[:relos])],
    flat_map(
      s[:relos],
      (r) -> [r[:at], r[:type], get(offsets, r[:access]), r[:kind]]
    )
  )
end

@doc """
encode_ext: the `.BTF.ext` for these types and names: each of `sections` {section:, funcs: [{at:, type:}]}, and each of `lines` {section:, lines: [{at:, file:, text:, pos:}]}, and each of `core` {section:, relos: [{at:, type:, access:, kind:}]}, `at` in bytes from the section's start, `pos` the line above ten bits of column.

    read_ext(encode_ext([], ["xdp"], [{section: "xdp", funcs: [{at: 0, type: 1}]}]), encode([], ["xdp"])) #=> [{section: "xdp", funcs: [{at: 0, type: 1}]}]
    read_ext(encode_ext([], [], []), encode([])) #=> []
"""
def encode_ext(types, names, sections, lines?, core?)
  offsets = strings_of(types, names)[:offsets]
  body = if sections == []
    []
  else
    flat_map(
      append([8], flat_map(sections, (s) -> ext_section_words(s, offsets))),
      word_bytes
    )
  end
  line_body = if (lines or []) == []
    []
  else
    flat_map(
      append([16], flat_map(lines, (s) -> ext_line_words(s, offsets))),
      word_bytes
    )
  end
  after_lines = length(body) + length(line_body)
  core_body = if (core or []) == []
    []
  else
    flat_map(
      append([16], flat_map(core, (s) -> ext_core_words(s, offsets))),
      word_bytes
    )
  end
  append(
    pack(
      ext_header_layout,
      {
        magic: 60319,
        version: 1,
        flags: 0,
        hdr_len: 32,
        func_info_off: 0,
        func_info_len: length(body),
        line_info_off: length(body),
        line_info_len: length(line_body),
        core_relo_off: after_lines,
        core_relo_len: length(core_body)
      }
    ),
    append(*[body, line_body, core_body])
  )
end

@doc """
ext_step: one section of a func_info read, and where the next starts.

    ext_step({at: 0, sections: []}, append(word_bytes(0), word_bytes(0)),{to_name: {0 => ""}}, 8)[:at] #=> 8
"""
def ext_step(acc, bytes, b, record)
  at = acc[:at]
  count = word_at(bytes, at + 4)
  funcs = map(
    fn(i)
      from = at + 8 + i * record
      {at: word_at(bytes, from), type: word_at(bytes, from + 4)}
    end,
    range(0, count)
  )
  {
    at: at + 8 + count * record,
    sections: append(
      acc[:sections],
      [{section: name_of(b, word_at(bytes, at)), funcs:}]
    )
  }
end

@doc """
read_ext: a `.BTF.ext`'s func_info by section, names read from the BTF blob beside it. Bytes that are no `.BTF.ext` raise :decode_error.

    read_ext(encode_ext([], [], []), encode([])) #=> []
    (read_ext([1, 2, 3], encode([])) rescue :refused) #=> :refused
"""
def read_ext(bytes, blob)
  if length(bytes) < 24 or bytes_int(bytes, 0, 2) != 60319
    raise(:decode_error, "these bytes are not BTF.ext: the magic is not 0xeB9F")
  end
  hdr = word_at(bytes, 4)
  from = hdr + word_at(bytes, 8)
  count = word_at(bytes, 12)
  if count == 0
    []
  else
    b = read(blob)
    record = word_at(bytes, from)
    acc = {at: 0, sections: []}
    inner = map((i) -> bytes[from + 4 + i], range(0, count - 4))
    while(acc[:at] < count - 4, set!(acc, ext_step(acc, inner, b, record)))
    acc[:sections]
  end
end

@doc """
read_lines: a `.BTF.ext`'s line info by section, strings read from the BTF blob beside it, each row {at:, file:, text:, line:, col:}. A record longer than the 16 bytes the kernel reads keeps its first 16.

    read_lines(encode_ext([], [], []), encode([])) #=> []
"""
def read_lines(bytes, blob)
  hdr = word_at(bytes, 4)
  from = hdr + word_at(bytes, 16)
  count = word_at(bytes, 20)
  if count == 0
    []
  else
    b = read(blob)
    record = word_at(bytes, from)
    stop = from + count
    acc = {at: from + 4, sections: []}
    while(acc[:at] < stop, set!(acc, line_step(acc, bytes, b, record)))
    acc[:sections]
  end
end

@doc """
line_step: one section of a line info read, and where the next starts.

    line_step({at: 0, sections: []}, append(word_bytes(0), word_bytes(0)), read(encode([])), 16)[:at] #=> 8
"""
def line_step(acc, bytes, b, record)
  at = acc[:at]
  count = word_at(bytes, at + 4)
  rows = map(
    fn(i)
      row = at + 8 + i * record
      pos = word_at(bytes, row + 12)
      {
        at: word_at(bytes, row),
        file: name_of(b, word_at(bytes, row + 4)),
        text: name_of(b, word_at(bytes, row + 8)),
        line: shift_right_logical(pos, 10),
        col: bit_and(pos, 1023)
      }
    end,
    range(0, count)
  )
  {
    at: at + 8 + count * record,
    sections: append(
      acc[:sections],
      [{section: name_of(b, word_at(bytes, at)), lines: rows}]
    )
  }
end

@doc """
read_core: a `.BTF.ext`'s CO-RE relocations by section, each {at:, type:, access:, kind:}. An ext that holds none, or a header too short to, has none.

    read_core(encode_ext([], [], []), encode([])) #=> []
"""
def read_core(bytes, blob)
  hdr = word_at(bytes, 4)
  if hdr < 32 or word_at(bytes, 28) == 0
    []
  else
    from = hdr + word_at(bytes, 24)
    record = word_at(bytes, from)
    b = read(blob)
    stop = from + word_at(bytes, 28)
    acc = {at: from + 4, sections: []}
    while(acc[:at] < stop, set!(acc, core_step(acc, bytes, b, record)))
    acc[:sections]
  end
end

@doc """
core_step: one section of a CO-RE read, and where the next starts.

    core_step({at: 0, sections: []}, append(word_bytes(0), word_bytes(0)), read(encode([])), 16)[:at] #=> 8
"""
def core_step(acc, bytes, b, record)
  at = acc[:at]
  count = word_at(bytes, at + 4)
  rows = map(
    fn(i)
      row = at + 8 + i * record
      {
        at: word_at(bytes, row),
        type: word_at(bytes, row + 4),
        access: name_of(b, word_at(bytes, row + 8)),
        kind: word_at(bytes, row + 12)
      }
    end,
    range(0, count)
  )
  {
    at: at + 8 + count * record,
    sections: append(
      acc[:sections],
      [{section: name_of(b, word_at(bytes, at)), relos: rows}]
    )
  }
end

test "CO-RE relocations in a BTF.ext sit after line info and read back by section"
  names = %w[xdp 0:1]
  types = [
    int_type("int", 4),
    sized_type(
      :struct,
      "s",
      8,
      [{name: "f", type: 1, bits: 0}, {name: "g", type: 1, bits: 32}]
    )
  ]
  ext = encode_ext(
    types,
    names,
    [],
    [],
    [{section: "xdp", relos: [{at: 16, type: 2, access: "0:1", kind: 0}]}]
  )
  blob = encode(types, names)
  assert read_core(ext, blob) ==
    [{section: "xdp", relos: [{at: 16, type: 2, access: "0:1", kind: 0}]}]
  assert word_at(ext, 28) == 28
  assert read_lines(ext, blob) == []
  both = encode_ext(
    types,
    append(names, %w[f t]),
    [],
    [{section: "xdp", lines: [{at: 0, file: "f", text: "t", pos: 2051}]}],
    [{section: "xdp", relos: [{at: 16, type: 2, access: "0:1", kind: 0}]}]
  )
  whole = encode(types, append(names, %w[f t]))
  assert size(read_lines(both, whole)) == 1
  assert size(read_core(both, whole)) == 1
end

test "line info in a BTF.ext sits after its func_info and reads back by section"
  names = %w[xdp f.b text]
  types = [proto_type(0, []), linked_type(:func, "e", 1, :global)]
  ext = encode_ext(
    types,
    names,
    [{section: "xdp", funcs: [{at: 0, type: 2}]}],
    [{section: "xdp", lines: [{at: 0, file: "f.b", text: "text", pos: 2051}]}]
  )
  blob = encode(types, names)
  assert read_ext(ext, blob) == [{section: "xdp", funcs: [{at: 0, type: 2}]}]
  assert read_lines(ext, blob) ==
    [
      {
        section: "xdp",
        lines: [{at: 0, file: "f.b", text: "text", line: 2, col: 3}]
      }
    ]
  assert word_at(ext, 16) == 20
  assert word_at(ext, 20) == 28
  assert word_at(ext, 24) == 48
end

test "a table of no types reads as empty, and finds nothing"
  empty = append(
    *[
      [159, 235, 1, 0],
      word_bytes(24),
      word_bytes(0),
      word_bytes(0),
      word_bytes(0),
      word_bytes(1),
      [0]
    ]
  )
  b = read(empty)
  assert b[:count] == 0
  assert find(b, "x", :struct).nil?
end

test "the sample's types read back as they were written by hand"
  b = read(sample)
  assert b[:count] == 6
  assert size_of(b, 6) == 8
  assert type_at(b, 2)[:name] == "task"
  assert size(type_at(b, 2)[:members]) == 3
  assert first(type_at(b, 2)[:members])[:name] == "state"
  assert type_at(b, 3)[:kind] == :typedef
  assert type_at(b, 5)[:kind] == :func
end

test "a field is found through a typedef and an anonymous union, at its bit offset over 8"
  b = read(sample)
  assert field(b, "task", ["state"]) == {offset: 0, size: 4, type: 1}
  assert field(b, "task", ["pid"]).offset == 4
  assert field(b, "task", ["inner"]).offset == 8
end

test "open reads a file's sections as read reads its bytes"
  dir = path_join(getenv("TMPDIR", "/tmp"), "btf-open-#{to_s(now_ms)}")
  mkdir_p(dir)
  path = path_join(dir, "sample.btf")
  write_bytes(path, sample)
  b = open(path)
  assert b[:count] == 6
  assert field(b, "task", ["pid"]).offset == 4
  rm_rf(dir)
end

test "written types read back: a field, a function's parameters and a section's variables"
  types = [
    int_type("int", 4),
    sized_type(
      :struct,
      "task",
      8,
      [{name: "a", type: 1, bits: 0}, {name: "b", type: 1, bits: 32}]
    ),
    pointer_to(2),
    proto_type(1, [{name: "ctx", type: 3}]),
    linked_type(:func, "run", 4, :global),
    array_of(1, 1, 3),
    linked_type(:var, "v", 6, :global),
    sized_type(:datasec, ".maps", 12, [{type: 7, offset: 0, size: 12}])
  ]
  b = read(encode(types))
  assert b[:count] == 8
  assert field(b, "task", ["b"]).offset == 4
  assert size_of(b, 6) == 12
  assert type_at(b, 4)[:params] == [{name: "ctx", type: 3}]
  assert function_id(b, "run") == 5
  assert type_at(b, 5)[:vlen] == 1
  assert type_at(b, 8)[:vars] == [{type: 7, offset: 0, size: 12}]
  assert find(b, ".maps", :datasec) == 8
  assert bit_and(
    type_at(read(encode([int_type("u", 4, false)])), 1)[:vlen],
    1
  ) == 0
end

test "the encoding of one known type is the bytes the format states, checked by hand"
  assert encode([int_type("int", 4)]) ==
    [
      159,
      235,
      1,
      0,
      24,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      16,
      0,
      0,
      0,
      16,
      0,
      0,
      0,
      5,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      4,
      0,
      0,
      0,
      32,
      0,
      0,
      1,
      0,
      105,
      110,
      116,
      0
    ]
  assert slice_after_header(encode([int_type("u", 1, false)])) ==
    [1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 8, 0, 0, 0]
end

@doc """
slice_after_header: the first type's sixteen bytes of a blob.

    size(slice_after_header(encode([int_type("u", 1, false)]))) #=> 16
"""
def slice_after_header(bytes)
  map((i) -> bytes[24 + i], range(0, 16))
end

test "interning keeps one id per type, and an empty string table holds only the empty name"
  one = intern([], pointer_to(0))
  again = intern(one[:types], pointer_to(0))
  other = intern(one[:types], pointer_to(1))
  assert one[:id] == 1
  assert again[:id] == 1
  assert size(again[:types]) == 1
  assert other[:id] == 2
  assert strings_of([], [])[:bytes] == [0]
  assert strings_of([], %w[a a b])[:offsets]["b"] == 3
end

test "a BTF.ext's func_info reads back by section, in bytes, and an empty one is empty"
  names = %w[xdp .text]
  sections = [
    {section: "xdp", funcs: [{at: 0, type: 2}]},
    {section: ".text", funcs: [{at: 0, type: 3}, {at: 40, type: 4}]}
  ]
  assert read_ext(encode_ext([], names, sections), encode([], names)) ==
    sections
  assert read_ext(encode_ext([], [], []), encode([])) == []
  assert (read_ext([0, 0, 0, 0], encode([])) rescue :refused) == :refused
  no_magic = map((_i) -> 0, range(0, 32))
  assert (read_ext(no_magic, encode([])) rescue :refused) == :refused
end

test "a type the writer has no form for and a linkage that is none each refuse by name"
  assert (encode([{kind: :fwd, name: "x"}]) rescue :refused) == :refused
  assert (encode([linked_type(:func, "f", 1, :weak)]) rescue :refused) ==
    :refused
end

test "bytes that are no BTF, a field that is absent and a walk into a scalar each refuse by name"
  assert (read([0, 0, 0, 0]) rescue :refused) == :refused
  assert (read(map((_i) -> 0, range(0, 24))) rescue :refused) == :refused
  b = read(sample)
  assert (field(b, "task", ["gone"]) rescue :refused) == :refused
  assert (field(b, "task", %w[pid deeper]) rescue :refused) == :refused
  assert (field(b, "nothing", ["pid"]) rescue :refused) == :refused
end
