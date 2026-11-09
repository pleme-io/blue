@moduledoc """
seikika (正規化) — canonicalization: one byte form for every blue value, and the root that names it.

`encode` writes a value as bytes, `decode` reads them back, and `root` is `b3:` and the BLAKE3 hash of the bytes. Two values share a root only when they are the same value, kind for kind: the string "a", the symbol a and the keyword :a are three roots, an Int 1 and a Str "1" are two map keys, and a list of pairs is never a map.

The bytes begin with the format byte 1. Each value is a tag byte, then its body:

    0 nil       nothing
    1 bool      one byte, 0 or 1
    2 int       eight bytes, big-endian two's complement
    3 float     eight bytes, the IEEE-754 bits big-endian; NaN and the infinities are refused
    4 str       a four-byte big-endian length, then the UTF-8 bytes
    5 symbol    as str
    6 keyword   as str
    7 list      a four-byte count, then each element
    8 map       a four-byte count, then each key and its value, keys in the order of their bytes
    9 record    the name as a str body, a four-byte count, then each field's name as a str body and its value, in declared order

A union arm is the record of its arm: the runtime carries the arm's record name and no union name, so the record tag names it whole.

A value with no encoding is refused, never mapped to another: a function, a foreign handle, a channel, a fiber, a promise, an error, NaN or an infinity raises `:render_error` whose data is `{path:, kind:}`, the path the steps from the top (a list index, a map key or a record field) to the value. `decode` reads only canonical bytes and raises `:decode_error` for any other, so `encode(decode(b)) == b` whenever decode answers.

    root(1) == root("1") #=> false
    decode(encode({a: [1, "1", :one]})) == {a: [1, "1", :one]} #=> true
"""

use("baito", %i[bytes_int int_bytes slice_bytes])
use("ran", [:next_seed])
use("retsu", %i[first last])
use("shinsuu", [:bytes_hex])

@doc """
FORMAT: the byte every encoding starts with, the version of the format.

    FORMAT #=> 1
"""
FORMAT = 1

@doc """
TAGS: the tag byte of each value kind.

    TAGS[:keyword] #=> 6
"""
TAGS = {
  nil: 0,
  bool: 1,
  int: 2,
  float: 3,
  str: 4,
  symbol: 5,
  keyword: 6,
  list: 7,
  map: 8,
  record: 9
}

@doc """
RECORD_KEY: the keyword under which a record carries its name and fields.

    keyword?(RECORD_KEY) #=> true
"""
RECORD_KEY = first(read_forms(":$record"))

@doc """
TWO_50: two to the fiftieth power as a Float, the step `scale` moves by.

    TWO_50 == 1125899906842624.0 #=> true
"""
TWO_50 = to_float(shift_left(1, 50))

@doc """
TWO_52: two to the fifty-second power as a Float, the weight of a float's hidden bit.

    TWO_52 == 4503599627370496.0 #=> true
"""
TWO_52 = to_float(shift_left(1, 52))

@doc """
kind: the kind of a value: `:nil`, `:bool`, `:int`, `:float`, `:str`, `:symbol`, `:keyword`, `:list`, `:map` or `:record` for one that has an encoding, and `:nan`, `:infinity`, `:function`, `:foreign`, `:channel`, `:fiber`, `:promise`, `:error` or `:unknown` for one that has none.

    kind([]) #=> :list
    kind(1.5) #=> :float
    kind((x) -> x) #=> :function
"""
def kind(v)
  if v.nil?
    :nil
  elsif boolean?(v)
    :bool
  elsif integer?(v)
    :int
  elsif float?(v)
    if v != v
      :nan
    elsif v - v != 0.0
      :infinity
    else
      :float
    end
  elsif string?(v)
    :str
  elsif keyword?(v)
    :keyword
  elsif symbol?(v)
    :symbol
  elsif map?(v)
    if record_name(v).nil?
      :map
    else
      :record
    end
  elsif error?(v)
    :error
  elsif procedure?(v)
    :function
  elsif foreign?(v)
    :foreign
  elsif chan?(v)
    :channel
  elsif go?(v)
    :fiber
  elsif promise?(v)
    :promise
  elsif list?(v)
    :list
  else
    :unknown
  end
end

@doc """
u32: a count or length as four big-endian bytes.

    u32(258) #=> [0, 0, 1, 2]
"""
def u32(n)
  if n < 0 or n >= shift_left(1, 32)
    raise(:render_error, "a length must fit four bytes, got #{to_s(n)}")
  end
  int_bytes(n, 4, :big)
end

@doc """
text_body: a text as its four-byte length and its UTF-8 bytes.

    text_body("é") #=> [0, 0, 0, 2, 195, 169]
"""
def text_body(s)
  b = text_bytes(s)
  append(u32(length(b)), b)
end

@doc """
scale: a float times two to the power `k`, moved fifty powers at a time so every step is exact.

    scale(3.0, 2) #=> 12.0
    scale(1.0, -1074) > 0.0 #=> true
"""
def scale(x, k)
  if k > 50
    scale(x * TWO_50, k - 50)
  elsif k < -50
    scale(x / TWO_50, k + 50)
  elsif k >= 0
    x * to_float(shift_left(1, k))
  else
    x / to_float(shift_left(1, -k))
  end
end

@doc """
unit_exponent: the exponent `e` with `a` over two to the `e` in [1, 2), from a first guess `e`.

    unit_exponent(8.0, 2) #=> 3
"""
def unit_exponent(a, e)
  y = scale(a, -e)
  if y >= 2.0
    unit_exponent(a, e + 1)
  elsif y < 1.0
    unit_exponent(a, e - 1)
  else
    e
  end
end

@doc """
float_bits: the IEEE-754 binary64 bits of a finite float, as an Int; -0.0 keeps its sign bit.

    float_bits(1.0) #=> 4607182418800017408
    float_bits(0.0 * -1.0) == shift_left(1, 63) #=> true
"""
def float_bits(x)
  sign = if x < 0.0 or x == 0.0 and atan2(x, -1.0) < 0.0
    1
  else
    0
  end
  a = if sign == 1
    x * -1.0
  else
    x
  end
  fields = if a == 0.0
    [0, 0]
  elsif a < scale(1.0, -1022)
    [0, to_int(scale(a, 1074))]
  else
    e = unit_exponent(a, floor(log(a, 2)))
    [e + 1023, to_int((scale(a, -e) - 1.0) * TWO_52)]
  end
  bit_or(shift_left(sign, 63), bit_or(shift_left(fields[0], 52), fields[1]))
end

@doc """
bits_float: the float whose IEEE-754 binary64 bits these are; bits of NaN or an infinity raise `:decode_error`.

    bits_float(4607182418800017408) #=> 1.0
    bits_float(float_bits(-2.5)) #=> -2.5
"""
def bits_float(bits)
  exp = bit_and(shift_right(bits, 52), 2047)
  mant = bit_and(bits, shift_left(1, 52) - 1)
  if exp == 2047
    raise(:decode_error, "float bits #{to_s(bits)} are NaN or an infinity")
  end
  magnitude = if exp == 0
    scale(to_float(mant), -1074)
  else
    scale(to_float(mant + shift_left(1, 52)), exp - 1075)
  end
  if bit_and(shift_right_logical(bits, 63), 1) == 1
    magnitude * -1.0
  else
    magnitude
  end
end

@doc """
refuse: the `:render_error` for a value with no encoding at `path`.

    (refuse(:nan, [0]) rescue :refused) #=> :refused
"""
def refuse(found, path)
  raise(
    :render_error,
    "no canonical encoding for a value of kind #{to_s(found)} at path #{to_s(path)}",
    {data: {path:, kind: found}}
  )
end

@doc """
record_parts: a record's name and its field names in declared order, read from the name it carries.

    record_parts(json_read("{\"$record\": \"p(x,y)\", \"x\": 1, \"y\": 2}")) #=> ["p", %w[x y]]
"""
def record_parts(r)
  tag = get(r, RECORD_KEY)
  open = text_index(tag, "(", 0)
  [
    join(take(open, chars(tag)), ""),
    split(join(drop(open + 1, butlast(chars(tag))), ""), ",")
  ]
end

@doc """
field_value: the value of the record field named by its text.

    field_value({x: 1}, "x") #=> 1
"""
def field_value(r, name)
  last(first(filter((e) -> to_s(first(e)) == name, map_entries(r))))
end

@doc """
encode_at: the tagged bytes of a value found at `path`, without the format byte.

    encode_at(nil, []) #=> [0]
    encode_at(true, []) #=> [1, 1]
"""
def encode_at(v, path)
  k = kind(v)
  if k == :nil
    [TAGS[:nil]]
  elsif k == :bool
    [
      TAGS[:bool],
      if v
        1
      else
        0
      end
    ]
  elsif k == :int
    cons(TAGS[:int], int_bytes(v, 8, :big))
  elsif k == :float
    cons(TAGS[:float], int_bytes(float_bits(v), 8, :big))
  elsif member?(k, %i[str symbol keyword])
    cons(get(TAGS, k), text_body(to_s(v)))
  elsif k == :list
    append(
      [TAGS[:list]],
      u32(length(v)),
      *map((i) -> encode_at(v[i], append(path, [i])), range(0, length(v)))
    )
  elsif k == :map
    encode_map(v, path)
  elsif k == :record
    encode_record(v, path)
  else
    refuse(k, path)
  end
end

@doc """
encode_map: a map's tagged bytes: its count, then each key and value, keys in the order of their bytes.

    encode_map({}, []) #=> [8, 0, 0, 0, 0]
"""
def encode_map(m, path)
  pairs = map(
    fn(e)
      [key, value] = e
      kb = encode_at(key, append(path, [key]))
      [bytes_hex(kb), append(kb, encode_at(value, append(path, [key])))]
    end,
    map_entries(m)
  )
  append([TAGS[:map]], u32(length(pairs)), *map(last, sort_keyed(first, pairs)))
end

@doc """
encode_record: a record's tagged bytes: its name, its field count, then each field's name and value in declared order.

    encode_record(json_read("{\"$record\": \"p(x)\", \"x\": null}"), []) #=> [9, 0, 0, 0, 1, 112, 0, 0, 0, 1, 0, 0, 0, 1, 120, 0]
"""
def encode_record(r, path)
  [name, fields] = record_parts(r)
  append(
    [TAGS[:record]],
    text_body(name),
    u32(length(fields)),
    *map(
      fn(f)
        value = field_value(r, f)
        append(
          text_body(f),
          encode_at(value, append(path, [first(read_forms(":#{f}"))]))
        )
      end,
      fields
    )
  )
end

@doc """
encode: the canonical bytes of a value: the format byte, then its tagged form. A value with no encoding raises `:render_error` with `{path:, kind:}`.

    encode(nil) #=> [1, 0]
    encode([]) #=> [1, 7, 0, 0, 0, 0]
    encode("a") == encode(:a) #=> false
"""
def encode(v)
  cons(FORMAT, encode_at(v, []))
end

@doc """
root: the identity of a value, `b3:` and the BLAKE3 hash of its canonical bytes.

    root(nil) == "b3:#{blake3_hex([1, 0])}" #=> true
"""
def root(v)
  "b3:#{blake3_hex(encode(v))}"
end

@doc """
bad: the `:decode_error` for bytes that are not a canonical encoding, naming where.

    (bad(3, "no") rescue :refused) #=> :refused
"""
def bad(at, why)
  raise(:decode_error, "#{why} at byte #{to_s(at)}", {data: {at:}})
end

@doc """
byte_at: the byte at a position, raising `:decode_error` past the end.

    byte_at([7], 0) #=> 7
"""
def byte_at(bytes, at)
  if at >= length(bytes)
    bad(at, "the bytes end")
  end
  bytes[at]
end

@doc """
read_count: a four-byte count at a position and where its body starts, refused when the count exceeds the bytes left.

    read_count([0, 0, 0, 0], 0) #=> [0, 4]
"""
def read_count(bytes, at)
  if at + 4 > length(bytes)
    bad(at, "a count runs past the end")
  end
  n = bytes_int(bytes, at, 4, :big)
  if n > length(bytes) - at - 4
    bad(at, "a count of #{to_s(n)} exceeds the bytes left")
  end
  [n, at + 4]
end

@doc """
read_text: a length-prefixed UTF-8 text at a position and where it ends.

    read_text([0, 0, 0, 1, 97], 0) #=> ["a", 5]
"""
def read_text(bytes, at)
  [n, start] = read_count(bytes, at)
  s = bytes_text(slice_bytes(bytes, start, n))
  if s.nil?
    bad(start, "a text is not UTF-8")
  end
  [s, start + n]
end

@doc """
named: the symbol or keyword a text names, when the reader gives back exactly that one; else `:decode_error`.

    named(:keyword, "ok", 0) #=> :ok
"""
def named(k, s, at)
  text = if k == :keyword
    ":#{s}"
  else
    s
  end
  forms = read_forms(text) rescue []
  one = first(forms) rescue nil
  fits = if k == :keyword
    keyword?
  else
    symbol?
  end
  if length(forms) != 1 or not fits(one) or to_s(one) != s
    bad(at, "the #{to_s(k)} #{s} has no reading")
  end
  one
end

@doc """
read_items: `n` values in a row from a position, and where they end.

    read_items([0, 0], 0, 2) #=> [[nil, nil], 2]
"""
def read_items(bytes, at, n)
  reduce(
    fn(acc, _i)
      [v, next_at] = read_value(bytes, last(acc))
      [append(first(acc), [v]), next_at]
    end,
    [[], at],
    range(0, n)
  )
end

@doc """
read_map: `n` key and value pairs from a position, keys strictly ascending by their bytes, as a map and where it ends.

    read_map([2, 0, 0, 0, 0, 0, 0, 0, 1, 0], 0, 1) #=> [{1 => nil}, 10]
"""
def read_map(bytes, at, n)
  done = reduce(
    fn(acc, _i)
      [m, here, prev] = acc
      [key, key_end] = read_value(bytes, here)
      if member?(kind(key), %i[list map record])
        bad(here, "a map key is not a scalar")
      end
      kh = bytes_hex(slice_bytes(bytes, here, key_end - here))
      if not prev.nil? and compare(prev, kh) >= 0
        bad(here, "map keys are not in strictly ascending order")
      end
      [value, value_end] = read_value(bytes, key_end)
      [assoc(m, key, value), value_end, kh]
    end,
    [{}, at, nil],
    range(0, n)
  )
  [first(done), done[1]]
end

@doc """
read_record: a record's name, fields and values from a position, as the record and where it ends.

    record_name(first(read_record([0, 0, 0, 1, 112, 0, 0, 0, 1, 0, 0, 0, 1, 120, 0], 0))) #=> "p"
"""
def read_record(bytes, at)
  [name, after_name] = read_text(bytes, at)
  [n, here] = read_count(bytes, after_name)
  done = reduce(
    fn(acc, _i)
      [names, m, pos] = acc
      [f, after_field] = read_text(bytes, pos)
      [value, value_end] = read_value(bytes, after_field)
      [append(names, [f]), assoc(m, named(:keyword, f, pos), value), value_end]
    end,
    [[], {}, here],
    range(0, n)
  )
  [names, fields, end_at] = done
  r = assoc(fields, RECORD_KEY, "#{name}(#{join(names, ",")})")
  if record_name(r).nil? or length(map_entries(r)) != n + 1
    bad(at, "the record #{name} does not read back as one")
  end
  [r, end_at]
end

@doc """
read_value: the value tagged at a position, and where its bytes end.

    read_value([2, 0, 0, 0, 0, 0, 0, 0, 7], 0) #=> [7, 9]
"""
def read_value(bytes, at)
  tag = byte_at(bytes, at)
  body = at + 1
  if tag == TAGS[:nil]
    [nil, body]
  elsif tag == TAGS[:bool]
    b = byte_at(bytes, body)
    if b > 1
      bad(body, "a bool byte is 0 or 1, got #{to_s(b)}")
    end
    [b == 1, body + 1]
  elsif tag == TAGS[:int]
    if body + 8 > length(bytes)
      bad(body, "an int runs past the end")
    end
    [bytes_int(bytes, body, 8, :big), body + 8]
  elsif tag == TAGS[:float]
    if body + 8 > length(bytes)
      bad(body, "a float runs past the end")
    end
    [bits_float(bytes_int(bytes, body, 8, :big)), body + 8]
  elsif tag == TAGS[:str]
    read_text(bytes, body)
  elsif tag == TAGS[:symbol] or tag == TAGS[:keyword]
    [s, end_at] = read_text(bytes, body)
    k = if tag == TAGS[:symbol]
      :symbol
    else
      :keyword
    end
    [named(k, s, body), end_at]
  elsif tag == TAGS[:list]
    [n, here] = read_count(bytes, body)
    read_items(bytes, here, n)
  elsif tag == TAGS[:map]
    [n, here] = read_count(bytes, body)
    read_map(bytes, here, n)
  elsif tag == TAGS[:record]
    read_record(bytes, body)
  else
    bad(at, "no value kind has the tag #{to_s(tag)}")
  end
end

@doc """
decode: the value whose canonical bytes these are. Bytes that are not exactly one canonical encoding raise `:decode_error` naming the byte.

    decode([1, 4, 0, 0, 0, 1, 97]) #=> "a"
    (decode([1, 0, 0]) rescue :refused) #=> :refused
"""
def decode(bytes)
  if byte_at(bytes, 0) != FORMAT
    bad(0, "the format byte is #{to_s(bytes[0])}, not #{to_s(FORMAT)}")
  end
  [v, end_at] = read_value(bytes, 1)
  if end_at != length(bytes)
    bad(end_at, "bytes follow the value")
  end
  v
end

@doc """
same?: whether two values are one value, kind for kind, read with the runtime's predicates and not with this package's `kind`: the oracle the tests hold `root` to.

    same?("a", :a) #=> false
    same?([1, {k: 2.5}], [1, {k: 2.5}]) #=> true
"""
def same?(a, b)
  if a.nil? or b.nil?
    a.nil? and b.nil?
  elsif boolean?(a) or boolean?(b)
    boolean?(a) and boolean?(b) and a == b
  elsif integer?(a) or integer?(b)
    integer?(a) and integer?(b) and a == b
  elsif float?(a) or float?(b)
    float?(a) and float?(b) and to_s(a) == to_s(b)
  elsif string?(a) or string?(b)
    string?(a) and string?(b) and a == b
  elsif keyword?(a) or keyword?(b)
    keyword?(a) and keyword?(b) and to_s(a) == to_s(b)
  elsif symbol?(a) or symbol?(b)
    symbol?(a) and symbol?(b) and to_s(a) == to_s(b)
  elsif map?(a) or map?(b)
    map?(a) and map?(b) and same?(map_entries(a), map_entries(b))
  elsif list?(a) and list?(b)
    length(a) == length(b) and
      every?((i) -> same?(a[i], b[i]), range(0, length(a)))
  else
    false
  end
end

@doc """
GEN_TEXTS: the texts the generator spells strings with, chosen to collide with the generated symbols, keywords and numbers.

    member?("1", GEN_TEXTS) #=> true
"""
GEN_TEXTS = ["", "a", "b", "ab", "1", "1.5"]

@doc """
GEN_NAMES: the names the generator spells symbols, keywords and record fields with.

    GEN_NAMES #=> %w[a b ab]
"""
GEN_NAMES = %w[a b ab]

@doc """
GEN_FLOATS: the floats the generator draws: both zeros, the least subnormal, the largest finite, and values equal to generated Ints.

    length(GEN_FLOATS) #=> 7
"""
GEN_FLOATS = [
  0.0,
  0.0 * -1.0,
  1.0,
  1.5,
  -2.5,
  scale(1.0, -1074),
  scale(TWO_52 * 2.0 - 1.0, 971)
]

@doc """
GEN_INTS: the Ints the generator draws, both ends of the range among them.

    member?(1, GEN_INTS) #=> true
"""
GEN_INTS = [
  -1,
  0,
  1,
  2,
  256,
  9_223_372_036_854_775_807,
  -9_223_372_036_854_775_807 - 1
]

@doc """
draw: one element of a list chosen by a seed, and the next seed.

    first(draw(7, [5])) #=> 5
"""
def draw(seed, xs)
  s = next_seed(seed)
  [xs[shift_right(s, 8) % length(xs)], s]
end

@doc """
gen_many: `n` generated values at a depth, and the next seed.

    length(first(gen_many(3, 0, 0))) #=> 0
"""
def gen_many(seed, depth, n)
  reduce(
    fn(acc, _i)
      [v, s] = gen(last(acc), depth)
      [append(first(acc), [v]), s]
    end,
    [[], seed],
    range(0, n)
  )
end

@doc """
gen_scalar: a generated scalar, any kind a map key may be, and the next seed.

    member?(kind(first(gen_scalar(3))), %i[nil bool int float str symbol keyword]) #=> true
"""
def gen_scalar(seed)
  [c, s] = draw(seed, range(0, 7))
  if c == 0
    [nil, s]
  elsif c == 1
    draw(s, [true, false])
  elsif c == 2
    draw(s, GEN_INTS)
  elsif c == 3
    draw(s, GEN_FLOATS)
  elsif c == 4
    draw(s, GEN_TEXTS)
  else
    [name, s2] = draw(s, GEN_NAMES)
    prefix = if c == 5
      ""
    else
      ":"
    end
    [first(read_forms("#{prefix}#{name}")), s2]
  end
end

@doc """
gen: a generated value to `depth` levels of nesting: scalars, lists, maps, lists of pairs and records, and the next seed.

    kind(first(gen(1, 0))) != :function #=> true
"""
def gen(seed, depth)
  [
    c,
    s
  ] = draw(
    seed,
    if depth > 0
      range(0, 6)
    else
      [0]
    end
  )
  if c == 0
    gen_scalar(s)
  else
    [n, s2] = draw(s, [0, 1, 2])
    [items, s3] = gen_many(s2, depth - 1, n)
    [
      keys,
      s4
    ] = reduce(
      fn(acc, _i)
        [k, t] = gen_scalar(last(acc))
        [append(first(acc), [k]), t]
      end,
      [[], s3],
      range(0, n)
    )
    if c == 1
      [items, s4]
    elsif c == 2
      [zipmap(keys, items), s4]
    elsif c == 3
      [map((i) -> [keys[i], items[i]], range(0, n)), s4]
    elsif c == 4
      [map((i) -> [GEN_TEXTS[i + 1], items[i]], range(0, n)), s4]
    else
      [one, s5] = gen(s4, depth - 1)
      [name, s6] = draw(s5, %w[p q])
      [assoc(assoc({}, RECORD_KEY, "#{name}(x)"), :x, one), s6]
    end
  end
end

@doc """
corpus: the hand-picked values whose roots a lossy encoding shares: one text as a string, symbol and keyword; an Int, a Float and a string as keys; a list of pairs beside a map; empty containers nested; a record beside its plain map.

    length(corpus) > 20 #=> true
"""
def corpus()
  sym = first(read_forms("a"))
  [
    nil,
    false,
    true,
    0,
    1,
    0.0,
    0.0 * -1.0,
    1.0,
    "",
    "a",
    sym,
    :a,
    "1",
    {1 => :v},
    {"1" => :v},
    {1.0 => :v},
    {sym => :v},
    {a: :v},
    {"a" => :v},
    [["k", 1]],
    {"k" => 1},
    [[:k, 1]],
    {k: 1},
    [],
    {},
    [[]],
    [{}],
    [[], []],
    [[[]]],
    [nil],
    {a: []},
    {a: {}},
    ["ab"],
    %w[a b],
    ["ab", ""],
    ["", "ab"],
    {x: 1},
    json_read("{\"$record\": \"p(x)\", \"x\": 1}"),
    json_read("{\"$record\": \"q(x)\", \"x\": 1}"),
    {"$record" => "p(x)", "x" => 1},
    {nil => nil, false => 0, 2 => "2", "b" => [:b], c: {}}
  ]
end

@doc """
caught: the kind and data of the error calling `f` raises, or nil when it returns.

    caught(() -> 1) #=> nil
"""
def caught(f)
  f()
  nil
rescue e
  [e.kind, e.data]
end

test "every kind reads back as itself, and its bytes are the only bytes that read back to it"
  values = append(corpus, first(gen_many(11, 3, 60)))
  every?(
    fn(v)
      b = encode(v)
      back = decode(b)
      assert same?(back, v)
      assert encode(back) == b
      true
    end,
    values
  )
  inf = scale(1.0, 1023) * 2.0
  assert same?(decode(encode(scale(1.0, -1074))), scale(1.0, -1074))
  assert same?(decode(encode(GEN_FLOATS[6])), GEN_FLOATS[6])
  assert kind(inf) == :infinity
end

test "two values that are not one value never share a root"
  values = append(corpus, first(gen_many(5, 3, 160)))
  reps = reduce(
    fn(acc, v)
      if any?((r) -> same?(r, v), acc)
        acc
      else
        append(acc, [v])
      end
    end,
    [],
    values
  )
  roots = map(root, reps)
  assert length(distinct(roots)) == length(reps)
  every?(
    fn(v)
      assert root(v) == root(first(filter((r) -> same?(r, v), reps)))
      true
    end,
    values
  )
  assert root("a") != root(first(read_forms("a")))
  assert root("a") != root(:a)
  assert root({1 => :v}) != root({"1" => :v})
  assert root([["k", 1]]) != root({"k" => 1})
  assert root([[]]) != root([{}])
end

test "a value with no encoding is refused, naming the path to it"
  inf = scale(1.0, 1023) * 2.0
  assert caught(() -> encode([1, {k: (x) -> x}])) ==
    [:render_error, {path: [1, :k], kind: :function}]
  assert caught(() -> encode({a: [0, inf - inf]})) ==
    [:render_error, {path: [:a, 1], kind: :nan}]
  assert caught(() -> encode([inf])) ==
    [:render_error, {path: [0], kind: :infinity}]
  r = json_read("{\"$record\": \"p(x)\", \"x\": 1}")
  assert caught(() -> root(assoc(r, :x, length))) ==
    [:render_error, {path: [:x], kind: :function}]
end

test "bytes that are not one canonical encoding are refused"
  assert first(caught(() -> decode([2, 0]))) == :decode_error
  assert first(caught(() -> decode([1, 0, 0]))) == :decode_error
  assert first(caught(() -> decode([1, 1, 2]))) == :decode_error
  assert first(caught(() -> decode([1, 4, 0, 0, 0, 9, 97]))) == :decode_error
  assert first(caught(() -> decode([1, 3, 127, 240, 0, 0, 0, 0, 0, 0]))) ==
    :decode_error
  unsorted = [
    1,
    8,
    0,
    0,
    0,
    2,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    2,
    0,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    0
  ]
  assert first(caught(() -> decode(unsorted))) == :decode_error
  assert decode(
    [
      1,
      8,
      0,
      0,
      0,
      2,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      2,
      0
    ]
  ) == {1 => nil, 2 => nil}
end
