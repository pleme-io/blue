@moduledoc """
btf — the BPF Type Format as data: the kernel's own description of its types, read from `/sys/kernel/btf/vmlinux`, so a program finds a hook's id and a field's offset on the kernel it runs on.

`read` takes the bytes of a BTF blob. `find` gives a named type's id, `type_at` a type by id, and `field` walks a struct to a member, through anonymous unions, to its offset and size in bytes. A CO-RE relocation is this lookup at load time.

    b = read(sample)
    find(b, "task", :struct) #=> 2
    field(b, "task", ["pid"]).offset #=> 4
    field(b, "task", ["pid"]).size #=> 4
"""

use("baito", [:bytes_int])
use("retsu", %i[first flat_map rest size])

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

test "bytes that are no BTF, a field that is absent and a walk into a scalar each refuse by name"
  assert (read([0, 0, 0, 0]) rescue :refused) == :refused
  assert (read(map((_i) -> 0, range(0, 24))) rescue :refused) == :refused
  b = read(sample)
  assert (field(b, "task", ["gone"]) rescue :refused) == :refused
  assert (field(b, "task", %w[pid deeper]) rescue :refused) == :refused
  assert (field(b, "nothing", ["pid"]) rescue :refused) == :refused
end
