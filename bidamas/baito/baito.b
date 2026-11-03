@moduledoc """
baito (バイト) — bytes as data: integers at a declared width and order, and record layouts that say where each field sits.

A layout is the one description of a binary record. `layout` lays its fields out as a C compiler would, `pack` writes a record to bytes and `unpack` reads one back, so a kernel struct, an ELF header, a BPF map value and a wire message are each declared once and read the same way in both directions. A byte is an integer 0..255; bytes are a list of them.

Field kinds are `:u8 :u16 :u32 :u64 :i8 :i16 :i32 :i64`, `[:bytes, n]`, `[:text, n]` (a NUL-padded string), `[:array, kind, n]`, and a nested layout.

    point = layout([[:x, :u16], [:y, :u32]])
    width(point) #=> 8
    unpack(point, pack(point, {x: 1, y: 2})) #=> {x: 1, y: 2}
"""

use("retsu", %i[first flat_map repeat rest take_while])

@doc """
kind_width: the bytes a scalar kind takes, nil when the word names no scalar.

    kind_width(:u32) #=> 4
    kind_width(:other) #=> nil
"""
def kind_width(kind)
  if member?(kind, %i[u8 i8])
    1
  elsif member?(kind, %i[u16 i16])
    2
  elsif member?(kind, %i[u32 i32])
    4
  elsif member?(kind, %i[u64 i64])
    8
  end
end

@doc """
signed?: whether a scalar kind reads its top bit as a sign.

    signed?(:i8) #=> true
    signed?(:u8) #=> false
"""
def signed?(kind)
  member?(kind, %i[i8 i16 i32 i64])
end

@doc """
int_bytes: the low `count` bytes of an integer in two's complement, little first unless `order` is `:big`.

    int_bytes(258, 2) #=> [2, 1]
    int_bytes(258, 2, :big) #=> [1, 2]
    int_bytes(-1, 2) #=> [255, 255]
"""
def int_bytes(n, count, order?)
  if not member?(count, [1, 2, 4, 8])
    raise(
      :bad_option,
      "an integer takes 1, 2, 4 or 8 bytes, got #{to_s(count)}"
    )
  end
  low_first = map((i) -> bit_and(shift_right(n, i * 8), 255), range(0, count))
  if order == :big
    reverse(low_first)
  else
    low_first
  end
end

@doc """
bytes_int: the integer `count` bytes hold at position `at`, signed when `sign` is true. Reading past the end raises.

    bytes_int([2, 1], 0, 2) #=> 258
    bytes_int([255, 255], 0, 2, :little, true) #=> -1
    bytes_int([1, 2], 0, 2, :big) #=> 258
"""
def bytes_int(bytes, at, count, order?, sign?)
  if at < 0 or at + count > length(bytes)
    raise(
      :decode_error,
      "#{to_s(count)} bytes at #{to_s(at)} run past #{to_s(length(bytes))} bytes"
    )
  end
  positions = if order == :big
    range(0, count)
  else
    reverse(range(0, count))
  end
  raw = reduce(
    (acc, i) -> bit_or(shift_left(acc, 8), bytes[at + i]),
    0,
    positions
  )
  if sign == true and
      count < 8 and
      bit_and(raw, shift_left(1, count * 8 - 1)) != 0
    raw - shift_left(1, count * 8)
  else
    raw
  end
end

@doc """
fits?: whether an integer can be held by a scalar kind.

    fits?(255, :u8) #=> true
    fits?(256, :u8) #=> false
    fits?(-1, :i8) #=> true
    fits?(-1, :u64) #=> true
"""
def fits?(n, kind)
  count = kind_width(kind)
  if count == 8
    true
  elsif signed?(kind)
    n >= -shift_left(1, count * 8 - 1) and n < shift_left(1, count * 8 - 1)
  else
    n >= 0 and n < shift_left(1, count * 8)
  end
end

@doc """
align_up: the first multiple of `alignment` at or past `n`.

    align_up(5, 4) #=> 8
    align_up(8, 4) #=> 8
    align_up(0, 8) #=> 0
"""
def align_up(n, alignment)
  n + alignment - 1 - (n + alignment - 1) % alignment
end

@doc """
compound_kind: what shape a field kind has: `:scalar`, `:layout`, or a list's head.

    compound_kind(:u8) #=> :scalar
    compound_kind([:bytes, 4]) #=> :bytes
"""
def compound_kind(kind)
  if list?(kind)
    first(kind)
  elsif map?(kind)
    :layout
  else
    :scalar
  end
end

@doc """
kind_size: the bytes a field kind takes, and raises naming a kind that is none.

    kind_size(:u16) #=> 2
    kind_size([:bytes, 16]) #=> 16
    kind_size([:array, :u32, 3]) #=> 12
"""
def kind_size(kind)
  case compound_kind(kind)
  when :scalar
    count = kind_width(kind)
    if count.nil?
      raise(:bad_option, "no field kind #{to_s(kind)}")
    end
    count
  when :bytes
    kind[1]
  when :text
    kind[1]
  when :array
    kind_size(kind[1]) * kind[2]
  when :layout
    kind[:width]
  else
    raise(:bad_option, "no field kind #{to_s(kind)}")
  end
end

@doc """
kind_alignment: where a field kind must start: its own width for a scalar, 1 for bytes and text, the widest member for a nested layout.

    kind_alignment(:u32) #=> 4
    kind_alignment([:bytes, 16]) #=> 1
    kind_alignment([:array, :u16, 3]) #=> 2
"""
def kind_alignment(kind)
  case compound_kind(kind)
  when :scalar
    kind_size(kind)
  when :array
    kind_alignment(kind[1])
  when :layout
    kind[:alignment]
  else
    1
  end
end

@doc """
layout: a record layout from `[name, kind]` pairs, each field at the next offset its alignment allows and the whole rounded up to its widest member, as a C struct. `{packed: true}` puts each field straight after the last and adds no padding.

    layout([[:a, :u8], [:b, :u32]]).width #=> 8
    layout([[:a, :u8], [:b, :u32]], {packed: true}).width #=> 5
    layout([]).width #=> 0
"""
def layout(fields, opts?)
  packed = (opts or {})[:packed] == true
  placed = reduce(
    fn(acc, field)
      kind = field[1]
      alignment = if packed
        1
      else
        kind_alignment(kind)
      end
      at = align_up(acc[:end], alignment)
      {
        end: at + kind_size(kind),
        alignment: blue::max(acc[:alignment], alignment),
        fields: append(acc[:fields], [{name: first(field), kind:, offset: at}])
      }
    end,
    {end: 0, alignment: 1, fields: []},
    fields
  )
  {
    fields: placed[:fields],
    alignment: placed[:alignment],
    width: align_up(placed[:end], placed[:alignment])
  }
end

@doc """
width: the bytes a record of this layout takes.

    width(layout([[:a, :u8], [:b, :u32]])) #=> 8
"""
def width(l)
  l[:width]
end

@doc """
field_of: the placed field of this name, and raises naming the fields a layout has when there is none.

    field_of(layout([[:a, :u8], [:b, :u16]]), :b).offset #=> 2
"""
def field_of(l, name)
  found = find(l[:fields], (f) -> f[:name] == name)
  if found.nil?
    raise(
      :bad_option,
      "no field #{to_s(name)}; this layout has #{join(map((f) -> to_s(f[:name]), l[:fields]), ", ")}"
    )
  end
  found
end

@doc """
offset: where a field starts, a dotted list of names walking into nested layouts.

    offset(layout([[:a, :u8], [:b, :u16]]), :b) #=> 2
    offset(layout([[:h, layout([[:x, :u32]])], [:y, :u32]]), [:h, :x]) #=> 0
"""
def offset(l, path)
  if list?(path)
    head = field_of(l, first(path))
    if rest(path) == []
      head[:offset]
    else
      head[:offset] + offset(head[:kind], rest(path))
    end
  else
    field_of(l, path)[:offset]
  end
end

@doc """
scalar_bytes: an integer field's bytes, refused by the field's name when it does not fit.

    scalar_bytes(1, :u8, :little, :a) #=> [1]
    (scalar_bytes(256, :u8, :little, :a) rescue :refused) #=> :refused
"""
def scalar_bytes(value, kind, order, name)
  if not integer?(value)
    raise(:bad_option, "field #{to_s(name)} is an integer, got #{to_s(value)}")
  end
  if not fits?(value, kind)
    raise(
      :bad_option,
      "field #{to_s(name)}: #{to_s(value)} does not fit #{to_s(kind)}"
    )
  end
  int_bytes(value, kind_width(kind), order)
end

@doc """
text_bytes_padded: a text field's bytes, NUL padded, refused when no NUL fits.

    text_bytes_padded("a", 2, :n) #=> [97, 0]
"""
def text_bytes_padded(value, count, name)
  bytes = text_bytes(value)
  if length(bytes) >= count
    raise(
      :bad_option,
      "field #{to_s(name)}: text of #{to_s(length(bytes))} bytes needs a NUL in #{to_s(count)}"
    )
  end
  append(bytes, repeat(0, count - length(bytes)))
end

@doc """
raw_bytes_padded: a bytes field's bytes, zero padded.

    raw_bytes_padded([1], 2, :n) #=> [1, 0]
"""
def raw_bytes_padded(value, count, name)
  if length(value) > count
    raise(
      :bad_option,
      "field #{to_s(name)}: #{to_s(length(value))} bytes do not fit #{to_s(count)}"
    )
  end
  append(value, repeat(0, count - length(value)))
end

@doc """
array_bytes: an array field's bytes, an absent item as zeros.

    array_bytes([[1]], [:bytes, 1], 2, :little, :n) #=> [1, 0]
"""
def array_bytes(value, kind, count, order, name)
  items = value or []
  if length(items) > count
    raise(
      :bad_option,
      "field #{to_s(name)}: #{to_s(length(items))} items do not fit #{to_s(count)}"
    )
  end
  flat_map(range(0, count), (i) -> field_bytes(items[i], kind, order, name))
end

@doc """
field_bytes: any field's bytes, by its kind.

    field_bytes({a: 1}, layout([[:a, :u8]]), :little, :n) #=> [1]
    field_bytes(nil, layout([[:a, :u16]]), :little, :n) #=> [0, 0]
"""
def field_bytes(value, kind, order, name)
  case compound_kind(kind)
  when :scalar
    scalar_bytes(value or 0, kind, order, name)
  when :bytes
    raw_bytes_padded(value or [], kind[1], name)
  when :text
    text_bytes_padded(value or "", kind[1], name)
  when :array
    array_bytes(value, kind[1], kind[2], order, name)
  when :layout
    pack(kind, value or {}, order)
  end
end

@doc """
pack: a record as this layout's bytes, an absent field as zeros and the padding zeroed. A value that does not fit its field raises by the field's name.

    pack(layout([[:a, :u8], [:b, :u16]]), {a: 1, b: 2}) #=> [1, 0, 2, 0]
    pack(layout([[:a, :u8]]), {}) #=> [0]
    pack(layout([[:n, [:text, 4]]]), {n: "hi"}) #=> [104, 105, 0, 0]
"""
def pack(l, record, order?)
  placed = reduce(
    fn(acc, field)
      filler = repeat(0, field[:offset] - acc[:end])
      body = field_bytes(
        get(record, field[:name]),
        field[:kind],
        order,
        field[:name]
      )
      {
        end: field[:offset] + length(body),
        chunks: append(acc[:chunks], [filler, body])
      }
    end,
    {end: 0, chunks: []},
    l[:fields]
  )
  append(*append(placed[:chunks], [repeat(0, l[:width] - placed[:end])]))
end

@doc """
text_of: the text before a field's first NUL.

    text_of([97, 0, 98]) #=> "a"
    text_of([]) #=> ""
"""
def text_of(bytes)
  taken = take_while((b) -> b != 0, bytes)
  bytes_text(taken) or ""
end

@doc """
slice_bytes: bytes from a position, raising when they run short.

    slice_bytes([1, 2, 3], 1, 2) #=> [2, 3]
"""
def slice_bytes(bytes, at, count)
  if at < 0 or at + count > length(bytes)
    raise(
      :decode_error,
      "#{to_s(count)} bytes at #{to_s(at)} run past #{to_s(length(bytes))} bytes"
    )
  end
  map((i) -> bytes[at + i], range(0, count))
end

@doc """
field_value: a field's value at a position, by its kind.

    field_value([1], 0, :u8, :little) #=> 1
    field_value([1, 2], 0, [:array, :u8, 2], :little) #=> [1, 2]
"""
def field_value(bytes, at, kind, order)
  case compound_kind(kind)
  when :scalar
    bytes_int(bytes, at, kind_width(kind), order, signed?(kind))
  when :bytes
    slice_bytes(bytes, at, kind[1])
  when :text
    text_of(slice_bytes(bytes, at, kind[1]))
  when :array
    inner = kind[1]
    step = kind_size(inner)
    map(
      (i) -> field_value(bytes, at + i * step, inner, order),
      range(0, kind[2])
    )
  when :layout
    unpack(kind, bytes, at, order)
  end
end

@doc """
unpack: the record a layout's bytes hold at position `at`. Bytes that run short raise :decode_error.

    unpack(layout([[:a, :u8], [:b, :u16]]), [1, 0, 2, 0]) #=> {a: 1, b: 2}
    unpack(layout([[:b, :u8]]), [9, 7], 1) #=> {b: 7}
    unpack(layout([[:n, [:text, 4]]]), [104, 105, 0, 0]) #=> {n: "hi"}
"""
def unpack(l, bytes, at?, order?)
  reduce(
    fn(acc, field)
      assoc(
        acc,
        field[:name],
        field_value(bytes, (at or 0) + field[:offset], field[:kind], order)
      )
    end,
    {},
    l[:fields]
  )
end

test "the empty layout takes no bytes and packs and unpacks to nothing"
  empty = layout([])
  assert width(empty) == 0
  assert pack(empty, {}) == []
  assert unpack(empty, []) == {}
end

test "pack and unpack are inverse over every scalar kind at its extremes"
  kinds = [
    [:u8, 0],
    [:u8, 255],
    [:i8, -128],
    [:i8, 127],
    [:u16, 65535],
    [:i16, -32768],
    [:u32, 4_294_967_295],
    [:i32, -2_147_483_648],
    [:u64, -1],
    [:i64, 9_223_372_036_854_775_807]
  ]
  each_ok = map(
    fn(row)
      l = layout([[:v, first(row)]])
      unpack(l, pack(l, {v: row[1]}))[:v] == row[1]
    end,
    kinds
  )
  assert every?((ok) -> ok, each_ok)
end

test "a layout places fields as gcc places them: bpf_insn and a padded struct, by hand"
  insn = layout([%i[code u8], %i[regs u8], %i[off i16], %i[imm i32]])
  assert width(insn) == 8
  assert offset(insn, :imm) == 4
  padded = layout([%i[a u8], %i[b u64], %i[c u16]])
  assert offset(padded, :b) == 8
  assert offset(padded, :c) == 16
  assert width(padded) == 24
end

test "the bytes of a known bpf instruction match the ISA's own encoding"
  insn = layout([%i[code u8], %i[regs u8], %i[off i16], %i[imm i32]])
  assert pack(insn, {code: 183, regs: 0, off: 0, imm: 1}) ==
    [183, 0, 0, 0, 1, 0, 0, 0]
end

test "byte order changes the bytes and not the value"
  l = layout([%i[port u16]])
  assert pack(l, {port: 8080}, :big) == [31, 144]
  assert pack(l, {port: 8080}) == [144, 31]
  assert unpack(l, [31, 144], 0, :big) == {port: 8080}
end

test "nested layouts, arrays, bytes and text round trip in place"
  head = layout([%i[kind u32], [:name, [:text, 8]]])
  l = layout(
    [[:h, head], [:xs, [:array, :u16, 3]], [:raw, [:bytes, 2]], %i[end u8]]
  )
  rec = {h: {kind: 7, name: "abc"}, xs: [1, 2, 3], raw: [9, 8], end: 1}
  assert unpack(l, pack(l, rec)) == rec
  assert offset(l, %i[h name]) == 4
  assert width(l) == 24
end

test "a value too wide, a field too long and a short read each refuse by name"
  l = layout([%i[a u8], [:n, [:text, 2]]])
  assert (pack(l, {a: 256}) rescue :refused) == :refused
  assert (pack(l, {n: "ab"}) rescue :refused) == :refused
  assert (unpack(l, [1]) rescue :refused) == :refused
  assert (offset(l, :nope) rescue :refused) == :refused
  assert (layout([%i[a f32]]) rescue :refused) == :refused
end

test "an integer read past the end of its bytes raises, and one read at the end does not"
  short = fn(at, count)
    begin
      bytes_int([1, 2], at, count)
    rescue :decode_error
      :short
    end
  end
  assert short(0, 3) == :short
  assert short(1, 2) == :short
  assert short(-1, 1) == :short
  assert bytes_int([1, 2], 1, 1) == 2
end

test "a control: signed and unsigned read the same byte differently"
  assert bytes_int([255], 0, 1) == 255
  assert bytes_int([255], 0, 1, :little, true) == -1
end
