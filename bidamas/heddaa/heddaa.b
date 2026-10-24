use("kyohi", [:and_then, :ok, :ok?, :refusal, :refusal_of, :refused, :value])
use("retsu", [:first, :is_empty, :size, :slice])
use("shinsuu", [:bit_at, :bytes_hex, :hex_bytes, :shift_left, :shift_right])

# heddaa (ヘッダー) — header fields as HTTP/2 carries them: HPACK (RFC 7541).
#
# A field is [name, value]. Each is a string, or the byte list it arrived as
# when its octets are not UTF-8, so a decoder never refuses a field HPACK
# allows and never loses a byte. A table is the dynamic table plus its sizes:
# `max` is the size in force, `limit` the most the peer may raise it to
# (SETTINGS_HEADER_TABLE_SIZE). `encode` and `decode` are pure: each takes a
# table and returns the next one, so the two ends of a connection stay in step
# only by threading what they return. A malformed block is refused as data,
# kind :compression_error, which RFC 9113 §4.3 makes a connection error.
# Sources: RFC 7541 §4 (tables), §5 (integers, strings), §6 (representations),
# Appendix A (static table), Appendix B (Huffman code), Appendix C (examples).

huffman_codes = [
  [8184, 13],
  [8_388_568, 23],
  [268_435_426, 28],
  [268_435_427, 28],
  [268_435_428, 28],
  [268_435_429, 28],
  [268_435_430, 28],
  [268_435_431, 28],
  [268_435_432, 28],
  [16_777_194, 24],
  [1_073_741_820, 30],
  [268_435_433, 28],
  [268_435_434, 28],
  [1_073_741_821, 30],
  [268_435_435, 28],
  [268_435_436, 28],
  [268_435_437, 28],
  [268_435_438, 28],
  [268_435_439, 28],
  [268_435_440, 28],
  [268_435_441, 28],
  [268_435_442, 28],
  [1_073_741_822, 30],
  [268_435_443, 28],
  [268_435_444, 28],
  [268_435_445, 28],
  [268_435_446, 28],
  [268_435_447, 28],
  [268_435_448, 28],
  [268_435_449, 28],
  [268_435_450, 28],
  [268_435_451, 28],
  [20, 6],
  [1016, 10],
  [1017, 10],
  [4090, 12],
  [8185, 13],
  [21, 6],
  [248, 8],
  [2042, 11],
  [1018, 10],
  [1019, 10],
  [249, 8],
  [2043, 11],
  [250, 8],
  [22, 6],
  [23, 6],
  [24, 6],
  [0, 5],
  [1, 5],
  [2, 5],
  [25, 6],
  [26, 6],
  [27, 6],
  [28, 6],
  [29, 6],
  [30, 6],
  [31, 6],
  [92, 7],
  [251, 8],
  [32764, 15],
  [32, 6],
  [4091, 12],
  [1020, 10],
  [8186, 13],
  [33, 6],
  [93, 7],
  [94, 7],
  [95, 7],
  [96, 7],
  [97, 7],
  [98, 7],
  [99, 7],
  [100, 7],
  [101, 7],
  [102, 7],
  [103, 7],
  [104, 7],
  [105, 7],
  [106, 7],
  [107, 7],
  [108, 7],
  [109, 7],
  [110, 7],
  [111, 7],
  [112, 7],
  [113, 7],
  [114, 7],
  [252, 8],
  [115, 7],
  [253, 8],
  [8187, 13],
  [524_272, 19],
  [8188, 13],
  [16380, 14],
  [34, 6],
  [32765, 15],
  [3, 5],
  [35, 6],
  [4, 5],
  [36, 6],
  [5, 5],
  [37, 6],
  [38, 6],
  [39, 6],
  [6, 5],
  [116, 7],
  [117, 7],
  [40, 6],
  [41, 6],
  [42, 6],
  [7, 5],
  [43, 6],
  [118, 7],
  [44, 6],
  [8, 5],
  [9, 5],
  [45, 6],
  [119, 7],
  [120, 7],
  [121, 7],
  [122, 7],
  [123, 7],
  [32766, 15],
  [2044, 11],
  [16381, 14],
  [8189, 13],
  [268_435_452, 28],
  [1_048_550, 20],
  [4_194_258, 22],
  [1_048_551, 20],
  [1_048_552, 20],
  [4_194_259, 22],
  [4_194_260, 22],
  [4_194_261, 22],
  [8_388_569, 23],
  [4_194_262, 22],
  [8_388_570, 23],
  [8_388_571, 23],
  [8_388_572, 23],
  [8_388_573, 23],
  [8_388_574, 23],
  [16_777_195, 24],
  [8_388_575, 23],
  [16_777_196, 24],
  [16_777_197, 24],
  [4_194_263, 22],
  [8_388_576, 23],
  [16_777_198, 24],
  [8_388_577, 23],
  [8_388_578, 23],
  [8_388_579, 23],
  [8_388_580, 23],
  [2_097_116, 21],
  [4_194_264, 22],
  [8_388_581, 23],
  [4_194_265, 22],
  [8_388_582, 23],
  [8_388_583, 23],
  [16_777_199, 24],
  [4_194_266, 22],
  [2_097_117, 21],
  [1_048_553, 20],
  [4_194_267, 22],
  [4_194_268, 22],
  [8_388_584, 23],
  [8_388_585, 23],
  [2_097_118, 21],
  [8_388_586, 23],
  [4_194_269, 22],
  [4_194_270, 22],
  [16_777_200, 24],
  [2_097_119, 21],
  [4_194_271, 22],
  [8_388_587, 23],
  [8_388_588, 23],
  [2_097_120, 21],
  [2_097_121, 21],
  [4_194_272, 22],
  [2_097_122, 21],
  [8_388_589, 23],
  [4_194_273, 22],
  [8_388_590, 23],
  [8_388_591, 23],
  [1_048_554, 20],
  [4_194_274, 22],
  [4_194_275, 22],
  [4_194_276, 22],
  [8_388_592, 23],
  [4_194_277, 22],
  [4_194_278, 22],
  [8_388_593, 23],
  [67_108_832, 26],
  [67_108_833, 26],
  [1_048_555, 20],
  [524_273, 19],
  [4_194_279, 22],
  [8_388_594, 23],
  [4_194_280, 22],
  [33_554_412, 25],
  [67_108_834, 26],
  [67_108_835, 26],
  [67_108_836, 26],
  [134_217_694, 27],
  [134_217_695, 27],
  [67_108_837, 26],
  [16_777_201, 24],
  [33_554_413, 25],
  [524_274, 19],
  [2_097_123, 21],
  [67_108_838, 26],
  [134_217_696, 27],
  [134_217_697, 27],
  [67_108_839, 26],
  [134_217_698, 27],
  [16_777_202, 24],
  [2_097_124, 21],
  [2_097_125, 21],
  [67_108_840, 26],
  [67_108_841, 26],
  [268_435_453, 28],
  [134_217_699, 27],
  [134_217_700, 27],
  [134_217_701, 27],
  [1_048_556, 20],
  [16_777_203, 24],
  [1_048_557, 20],
  [2_097_126, 21],
  [4_194_281, 22],
  [2_097_127, 21],
  [2_097_128, 21],
  [8_388_595, 23],
  [4_194_282, 22],
  [4_194_283, 22],
  [33_554_414, 25],
  [33_554_415, 25],
  [16_777_204, 24],
  [16_777_205, 24],
  [67_108_842, 26],
  [8_388_596, 23],
  [67_108_843, 26],
  [134_217_702, 27],
  [67_108_844, 26],
  [67_108_845, 26],
  [134_217_703, 27],
  [134_217_704, 27],
  [134_217_705, 27],
  [134_217_706, 27],
  [134_217_707, 27],
  [268_435_454, 28],
  [134_217_708, 27],
  [134_217_709, 27],
  [134_217_710, 27],
  [134_217_711, 27],
  [134_217_712, 27],
  [67_108_846, 26],
  [1_073_741_823, 30]
]

static_entries = [
  [":authority", ""],
  [":method", "GET"],
  [":method", "POST"],
  [":path", "/"],
  [":path", "/index.html"],
  [":scheme", "http"],
  [":scheme", "https"],
  [":status", "200"],
  [":status", "204"],
  [":status", "206"],
  [":status", "304"],
  [":status", "400"],
  [":status", "404"],
  [":status", "500"],
  ["accept-charset", ""],
  ["accept-encoding", "gzip, deflate"],
  ["accept-language", ""],
  ["accept-ranges", ""],
  ["accept", ""],
  ["access-control-allow-origin", ""],
  ["age", ""],
  ["allow", ""],
  ["authorization", ""],
  ["cache-control", ""],
  ["content-disposition", ""],
  ["content-encoding", ""],
  ["content-language", ""],
  ["content-length", ""],
  ["content-location", ""],
  ["content-range", ""],
  ["content-type", ""],
  ["cookie", ""],
  ["date", ""],
  ["etag", ""],
  ["expect", ""],
  ["expires", ""],
  ["from", ""],
  ["host", ""],
  ["if-match", ""],
  ["if-modified-since", ""],
  ["if-none-match", ""],
  ["if-range", ""],
  ["if-unmodified-since", ""],
  ["last-modified", ""],
  ["link", ""],
  ["location", ""],
  ["max-forwards", ""],
  ["proxy-authenticate", ""],
  ["proxy-authorization", ""],
  ["range", ""],
  ["referer", ""],
  ["refresh", ""],
  ["retry-after", ""],
  ["server", ""],
  ["set-cookie", ""],
  ["strict-transport-security", ""],
  ["transfer-encoding", ""],
  ["user-agent", ""],
  ["vary", ""],
  ["via", ""],
  ["www-authenticate", ""]
]

def code_key(code, len)
  code * 32 + len
end

huffman_lookup = zipmap(
  map((c) -> code_key(first(c), nth(1, c)), huffman_codes),
  range(0, 257)
)

static_exact = zipmap(map((e) -> to_s(e), static_entries), range(1, 62))

static_names = zipmap(
  reverse(map((e) -> first(e), static_entries)),
  reverse(range(1, 62))
)

def broken(why)
  refused(refusal(:compression_error, why))
end

def octets(x)
  if string?(x)
    text_bytes(x)
  else
    x
  end
end

def field_part(bytes)
  t = bytes_text(bytes)
  if t.nil?
    bytes
  else
    t
  end
end

def entry_size(name, value)
  size(octets(name)) + size(octets(value)) + 32
end

def table(max)
  {entries: [], size: 0, max:, limit: max, updates: []}
end

def entries(t)
  map((e) -> [first(e), nth(1, e)], get(t, :entries))
end

def table_size(t)
  get(t, :size)
end

def table_max(t)
  get(t, :max)
end

def with_limit(t, limit)
  assoc(t, :limit, limit)
end

def keep_step(acc, e, room)
  total = nth(1, acc) + nth(2, e)
  if nth(2, acc) and total <= room
    [first(acc) + 1, total, true]
  else
    [first(acc), nth(1, acc), false]
  end
end

def evict(t, room)
  es = get(t, :entries)
  r = reduce((acc, e) -> keep_step(acc, e, room), [0, 0, true], es)
  assoc(assoc(t, :entries, slice(es, 0, first(r))), :size, nth(1, r))
end

def insert(t, name, value)
  s = entry_size(name, value)
  if s > get(t, :max)
    assoc(assoc(t, :entries, []), :size, 0)
  else
    e = evict(t, get(t, :max) - s)
    assoc(
      assoc(e, :entries, cons([name, value, s], get(e, :entries))),
      :size,
      get(e, :size) + s
    )
  end
end

def resize(t, max)
  if max > get(t, :limit) or max < 0
    raise(:usage, "table size #{max} is outside 0..#{get(t, :limit)}")
  end
  e = evict(assoc(t, :max, max), max)
  assoc(e, :updates, append(get(t, :updates), [max]))
end

def lookup(t, index)
  es = get(t, :entries)
  if index >= 1 and index <= 61
    nth(index - 1, static_entries)
  elsif index >= 62 and index - 62 < size(es)
    e = nth(index - 62, es)
    [first(e), nth(1, e)]
  end
end

def continuation(n)
  if n < 128
    [n]
  else
    cons(n % 128 + 128, continuation(floor(n / 128)))
  end
end

def encode_int(n, prefix, high)
  top = expt(2, prefix) - 1
  if n < top
    [high + n]
  else
    cons(high + top, continuation(n - top))
  end
end

def continue_int(bytes, pos, acc, m)
  if m > 28
    broken("an integer is longer than this decoder takes")
  elsif pos >= size(bytes)
    broken("an integer runs past the end of the block")
  else
    b = nth(pos, bytes)
    v = acc + shift_left(b % 128, m)
    if b < 128
      ok([v, pos + 1])
    else
      continue_int(bytes, pos + 1, v, m + 7)
    end
  end
end

def decode_int(bytes, pos, prefix)
  top = expt(2, prefix) - 1
  if pos >= size(bytes)
    broken("an integer runs past the end of the block")
  else
    v = nth(pos, bytes) % expt(2, prefix)
    if v < top
      ok([v, pos + 1])
    else
      continue_int(bytes, pos + 1, top, 0)
    end
  end
end

def huffman_size(data)
  bits = reduce((a, b) -> a + nth(1, nth(b, huffman_codes)), 0, octets(data))
  floor((bits + 7) / 8)
end

def huffman_encode(data)
  st = [0, 0]
  out = map(
    fn(b)
      c = nth(b, huffman_codes)
      acc = shift_left(first(st), nth(1, c)) + first(c)
      n = nth(1, st) + nth(1, c)
      k = floor(n / 8)
      left = n - 8 * k
      set!(st, [acc % expt(2, left), left])
      map((j) -> shift_right(acc, n - 8 * (j + 1)) % 256, range(0, k))
    end,
    octets(data)
  )
  pad = 8 - nth(1, st)
  if pad == 8
    append([], flatten(out))
  else
    append(flatten(out), [shift_left(first(st), pad) + expt(2, pad) - 1])
  end
end

def huffman_bit(s, bit)
  acc = first(s) * 2 + bit
  len = nth(1, s) + 1
  sym = get(huffman_lookup, code_key(acc, len))
  if sym.nil?
    [acc, len, nth(2, s) or len >= 30, nth(3, s)]
  elsif sym == 256
    [0, 0, true, nth(3, s)]
  else
    [0, 0, nth(2, s), append(nth(3, s), [sym])]
  end
end

def huffman_decode(bytes)
  st = [0, 0, false]
  out = map(
    fn(b)
      r = reduce(
        (s, i) -> huffman_bit(s, bit_at(b, i)),
        [first(st), nth(1, st), nth(2, st), []],
        [7, 6, 5, 4, 3, 2, 1, 0]
      )
      set!(st, [first(r), nth(1, r), nth(2, r)])
      nth(3, r)
    end,
    bytes
  )
  len = nth(1, st)
  if nth(2, st)
    broken("a Huffman string holds EOS or a code longer than 30 bits")
  elsif len > 7
    broken("Huffman padding is longer than 7 bits")
  elsif first(st) != expt(2, len) - 1
    broken("Huffman padding is not the start of EOS")
  else
    ok(append([], flatten(out)))
  end
end

def encode_string(x, huffman)
  raw = octets(x)
  if huffman == true or huffman == :shorter and huffman_size(raw) < size(raw)
    h = huffman_encode(raw)
    append(encode_int(size(h), 7, 128), h)
  else
    append(encode_int(size(raw), 7, 0), raw)
  end
end

def string_body(bytes, start, len, huffman)
  raw = slice(bytes, start, len)
  if start + len > size(bytes)
    broken("a string runs past the end of the block")
  elsif huffman
    and_then(huffman_decode(raw), (d) -> ok([field_part(d), start + len]))
  else
    ok([field_part(raw), start + len])
  end
end

def decode_string(bytes, pos)
  if pos >= size(bytes)
    broken("a string runs past the end of the block")
  else
    huffman = nth(pos, bytes) >= 128
    and_then(
      decode_int(bytes, pos, 7),
      (n) -> string_body(bytes, nth(1, n), first(n), huffman)
    )
  end
end

def add_field(st, f, next, sensitive)
  n = size(get(st, :fields))
  marked = if sensitive
    append(get(st, :sensitive), [n])
  else
    get(st, :sensitive)
  end
  merge_state(
    st,
    {
      fields: append(get(st, :fields), [f]),
      sensitive: marked,
      pos: next,
      open: false
    }
  )
end

def merge_state(st, changes)
  reduce((m, kv) -> assoc(m, first(kv), nth(1, kv)), st, map_entries(changes))
end

def indexed_field(st, index, next)
  f = lookup(get(st, :table), index)
  if index == 0
    broken("index 0 names no field")
  elsif f.nil?
    broken("index #{index} is outside both tables")
  else
    ok(add_field(st, f, next, false))
  end
end

def literal_done(st, f, next, how)
  s = add_field(st, f, next, how == :never)
  if how == :incremental
    ok(assoc(s, :table, insert(get(s, :table), first(f), nth(1, f))))
  else
    ok(s)
  end
end

def literal_value(st, block, name, next, how)
  and_then(
    decode_string(block, next),
    (v) -> literal_done(st, [name, first(v)], nth(1, v), how)
  )
end

def literal_name(st, block, index, next, how)
  f = lookup(get(st, :table), index)
  if index == 0
    and_then(
      decode_string(block, next),
      (n) -> literal_value(st, block, first(n), nth(1, n), how)
    )
  elsif f.nil?
    broken("index #{index} is outside both tables")
  else
    literal_value(st, block, first(f), next, how)
  end
end

def literal(st, block, prefix, how)
  and_then(
    decode_int(block, get(st, :pos), prefix),
    (iv) -> literal_name(st, block, first(iv), nth(1, iv), how)
  )
end

def apply_update(st, n, next)
  t = get(st, :table)
  if n > get(t, :limit)
    broken("table size #{n} is over the limit #{get(t, :limit)}")
  else
    ok(merge_state(st, {table: evict(assoc(t, :max, n), n), pos: next}))
  end
end

def size_update(st, block)
  if get(st, :open)
    and_then(
      decode_int(block, get(st, :pos), 5),
      (iv) -> apply_update(st, first(iv), nth(1, iv))
    )
  else
    broken("a table size update follows a field")
  end
end

def decode_one(st, block)
  pos = get(st, :pos)
  b = nth(pos, block)
  if b >= 128
    and_then(
      decode_int(block, pos, 7),
      (iv) -> indexed_field(st, first(iv), nth(1, iv))
    )
  elsif b >= 64
    literal(st, block, 6, :incremental)
  elsif b >= 32
    size_update(st, block)
  elsif b >= 16
    literal(st, block, 4, :never)
  else
    literal(st, block, 4, :plain)
  end
end

def decode(t, block)
  r = ok({pos: 0, fields: [], sensitive: [], table: t, open: true})
  while(
    ok?(r) and get(value(r), :pos) < size(block),
    set!(r, decode_one(value(r), block))
  )
  and_then(
    r,
    fn(st)
      ok(
        {
          fields: get(st, :fields),
          sensitive: get(st, :sensitive),
          table: get(st, :table)
        }
      )
    end
  )
end

def exact_index(t, name, value)
  s = get(static_exact, to_s([name, value]))
  d = position([name, value], entries(t))
  if s != nil
    s
  elsif d >= 0
    d + 62
  end
end

def name_index(t, name)
  s = get(static_names, name)
  d = position(name, map((e) -> first(e), get(t, :entries)))
  if s != nil
    s
  elsif d >= 0
    d + 62
  end
end

def literal_bytes(index, name, value, prefix, high, huffman)
  head = if index.nil?
    append([high], encode_string(name, huffman))
  else
    encode_int(index, prefix, high)
  end
  append(head, encode_string(value, huffman))
end

def encode_field(t, f, huffman, never, plain)
  name = first(f)
  value = nth(1, f)
  sensitive = member?(name, never)
  exact = if sensitive
    nil
  else
    exact_index(t, name, value)
  end
  index = name_index(t, name)
  if exact != nil
    [encode_int(exact, 7, 128), t]
  elsif sensitive
    [literal_bytes(index, name, value, 4, 16, huffman), t]
  elsif member?(name, plain)
    [literal_bytes(index, name, value, 4, 0, huffman), t]
  else
    [literal_bytes(index, name, value, 6, 64, huffman), insert(t, name, value)]
  end
end

def size_updates(t)
  us = get(t, :updates)
  low = reduce((a, b) -> blue::min(a, b), get(t, :max), us)
  if is_empty(us)
    []
  elsif low < get(t, :max)
    append(encode_int(low, 5, 32), encode_int(get(t, :max), 5, 32))
  else
    encode_int(get(t, :max), 5, 32)
  end
end

def encode(t, fields, opts?)
  opts = opts or {}
  huffman = if get(opts, :huffman).nil?
    :shorter
  else
    get(opts, :huffman)
  end
  never = get(opts, :never) or []
  plain = get(opts, :plain) or []
  head = size_updates(t)
  cell = [assoc(t, :updates, [])]
  out = map(
    fn(f)
      r = encode_field(first(cell), f, huffman, never, plain)
      set!(cell, [nth(1, r)])
      first(r)
    end,
    fields
  )
  {block: append(head, flatten(out)), table: first(cell)}
end

test "integers on an N-bit prefix, RFC 7541 C.1, and the edge at 2^N - 1"
  assert encode_int(10, 5, 0) == [10]
  assert encode_int(1337, 5, 0) == [31, 154, 10]
  assert encode_int(42, 8, 0) == [42]
  assert encode_int(30, 5, 0) == [30]
  assert encode_int(31, 5, 0) == [31, 0]
  assert encode_int(0, 7, 128) == [128]
  assert decode_int([31, 154, 10], 0, 5) == ok([1337, 3])
  assert decode_int([234, 31], 0, 5) == ok([10, 1])
  assert decode_int(encode_int(31, 5, 0), 0, 5) == ok([31, 2])
  assert refusal_of(decode_int([31, 154], 0, 5)) ==
    [:compression_error, "an integer runs past the end of the block"]
  assert first(
    refusal_of(decode_int([31, 255, 255, 255, 255, 255, 1], 0, 5))
  ) == :compression_error
  assert first(refusal_of(decode_int([], 0, 5))) == :compression_error
end

test "the Huffman code is the complete prefix code of Appendix B"
  assert size(huffman_codes) == 257
  assert reduce((a, c) -> a + expt(2, 30 - nth(1, c)), 0, huffman_codes) ==
    expt(2, 30)
  assert nth(48, huffman_codes) == [0, 5]
  assert nth(256, huffman_codes) == [1_073_741_823, 30]
end

test "Huffman strings of RFC 7541 C.4 encode and decode"
  assert bytes_hex(huffman_encode("www.example.com")) ==
    "f1e3c2e5f23a6ba0ab90f4ff"
  assert bytes_hex(huffman_encode("no-cache")) == "a8eb10649cbf"
  assert bytes_hex(huffman_encode("custom-key")) == "25a849e95ba97d7f"
  assert bytes_hex(huffman_encode("custom-value")) == "25a849e95bb8e8b4bf"
  assert huffman_decode(hex_bytes("f1e3c2e5f23a6ba0ab90f4ff")) ==
    ok(text_bytes("www.example.com"))
  assert huffman_encode("") == []
  assert huffman_decode([]) == ok([])
  assert huffman_size("www.example.com") == 12
  assert huffman_decode(huffman_encode(range(0, 256))) == ok(range(0, 256))
end

test "Huffman decoding refuses long padding, padding that is not EOS, and EOS"
  good = huffman_encode("a")
  assert good == [31]
  assert ok?(huffman_decode(good))
  assert first(refusal_of(huffman_decode(append(good, [255])))) ==
    :compression_error
  whole = huffman_encode("aaaaaaaa")
  assert size(whole) == 5
  assert huffman_decode(whole) == ok(text_bytes("aaaaaaaa"))
  assert nth(1, refusal_of(huffman_decode(append(whole, [255])))) ==
    "Huffman padding is longer than 7 bits"
  assert nth(1, refusal_of(huffman_decode([24]))) ==
    "Huffman padding is not the start of EOS"
  assert first(refusal_of(huffman_decode([255, 255, 255, 255]))) ==
    :compression_error
end

test "the static table is Appendix A, indexed from 1"
  t = table(4096)
  assert size(static_entries) == 61
  assert lookup(t, 1) == [":authority", ""]
  assert lookup(t, 2) == [":method", "GET"]
  assert lookup(t, 16) == ["accept-encoding", "gzip, deflate"]
  assert lookup(t, 61) == ["www-authenticate", ""]
  assert lookup(t, 0).nil?
  assert lookup(t, 62).nil?
  assert get(static_names, ":method") == 2
  assert get(static_names, ":status") == 8
end

test "the dynamic table counts octets plus 32, evicts the oldest, and empties for an entry too big"
  assert entry_size("custom-key", "custom-header") == 55
  assert entry_size("é", "") == 34
  t = insert(insert(table(110), "a", "1"), "b", "2")
  assert table_size(t) == 68
  assert entries(t) == [["b", "2"], ["a", "1"]]
  assert lookup(t, 62) == ["b", "2"]
  t2 = insert(t, "c", "333333333333333333333333333333333333333")
  assert entries(t2) ==
    [["c", "333333333333333333333333333333333333333"], ["b", "2"]]
  assert table_size(t2) == 106
  assert table_size(insert(t2, "x", repeat_text("y", 200))) == 0
  assert entries(resize(t2, 80)) ==
    [["c", "333333333333333333333333333333333333333"]]
  assert entries(resize(t2, 71)) == []
  assert entries(resize(t2, 0)) == []
end

test "each representation of RFC 7541 C.2"
  a = encode(table(4096), [["custom-key", "custom-header"]], {huffman: false})
  assert bytes_hex(get(a, :block)) ==
    "400a637573746f6d2d6b65790d637573746f6d2d686561646572"
  assert table_size(get(a, :table)) == 55
  b = encode(
    table(4096),
    [[":path", "/sample/path"]],
    {huffman: false, plain: [":path"]}
  )
  assert bytes_hex(get(b, :block)) == "040c2f73616d706c652f70617468"
  assert table_size(get(b, :table)) == 0
  c = encode(
    table(4096),
    [["password", "secret"]],
    {huffman: false, never: ["password"]}
  )
  assert bytes_hex(get(c, :block)) == "100870617373776f726406736563726574"
  assert bytes_hex(get(encode(table(4096), [[":method", "GET"]]), :block)) ==
    "82"
  d = value(decode(table(4096), get(c, :block)))
  assert get(d, :fields) == [["password", "secret"]]
  assert get(d, :sensitive) == [0]
  assert table_size(get(d, :table)) == 0
  e = value(decode(table(4096), get(a, :block)))
  assert entries(get(e, :table)) == [["custom-key", "custom-header"]]
  assert get(value(decode(table(4096), hex_bytes("82"))), :fields) ==
    [[":method", "GET"]]
end

test "three requests share one dynamic table, without Huffman (C.3) and with it (C.4)"
  r1 = [
    [":method", "GET"],
    [":scheme", "http"],
    [":path", "/"],
    [":authority", "www.example.com"]
  ]
  r2 = append(r1, [["cache-control", "no-cache"]])
  r3 = [
    [":method", "GET"],
    [":scheme", "https"],
    [":path", "/index.html"],
    [":authority", "www.example.com"],
    ["custom-key", "custom-value"]
  ]
  plain = [
    "828684410f7777772e6578616d706c652e636f6d",
    "828684be58086e6f2d6361636865",
    "828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565"
  ]
  huffed = [
    "828684418cf1e3c2e5f23a6ba0ab90f4ff",
    "828684be5886a8eb10649cbf",
    "828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf"
  ]
  assert exchange(4096, [r1, r2, r3], plain, false) == [57, 110, 164]
  assert exchange(4096, [r1, r2, r3], huffed, true) == [57, 110, 164]
end

test "three responses evict through a 256-octet table, without Huffman (C.5) and with it (C.6)"
  date1 = "Mon, 21 Oct 2013 20:13:21 GMT"
  home = "https://www.example.com"
  s1 = [
    [":status", "302"],
    ["cache-control", "private"],
    ["date", date1],
    ["location", home]
  ]
  s2 = [
    [":status", "307"],
    ["cache-control", "private"],
    ["date", date1],
    ["location", home]
  ]
  s3 = [
    [":status", "200"],
    ["cache-control", "private"],
    ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
    ["location", home],
    ["content-encoding", "gzip"],
    ["set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]
  ]
  plain = [
    "4803 3330 3258 0770 7269 7661 7465 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3120 474d 546e 1768 7474 7073 3a2f 2f77 7777 2e65 7861 6d70 6c65 2e63 6f6d",
    "4803 3330 37c1 c0bf",
    "88c1 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3220 474d 54c0 5a04 677a 6970 7738 666f 6f3d 4153 444a 4b48 514b 425a 584f 5157 454f 5049 5541 5851 5745 4f49 553b 206d 6178 2d61 6765 3d33 3630 303b 2076 6572 7369 6f6e 3d31"
  ]
  huffed = [
    "4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3",
    "4883 640e ffc1 c0bf",
    "88c1 6196 d07a be94 1054 d444 a820 0595 040b 8166 e084 a62d 1bff c05a 839b d9ab 77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b 3960 d5af 2708 7f36 72c1 ab27 0fb5 291f 9587 3160 65c0 03ed 4ee5 b106 3d50 07"
  ]
  assert exchange(256, [s1, s2, s3], plain, false) == [222, 222, 215]
  assert exchange(256, [s1, s2, s3], huffed, true) == [222, 222, 215]
  last_table = get(
    encode(get(encode(get(encode(table(256), s1), :table), s2), :table), s3),
    :table
  )
  assert map((e) -> first(e), entries(last_table)) ==
    ["set-cookie", "content-encoding", "date"]
end

test "a decoder refuses what no encoder may send, and accepts the same bytes made legal"
  t = table(100)
  assert nth(1, refusal_of(decode(t, [128]))) == "index 0 names no field"
  assert nth(1, refusal_of(decode(t, [190]))) ==
    "index 62 is outside both tables"
  assert first(refusal_of(decode(t, encode_int(4096, 5, 32)))) ==
    :compression_error
  assert nth(1, refusal_of(decode(t, [130, 32]))) ==
    "a table size update follows a field"
  assert first(refusal_of(decode(t, [64, 10, 97]))) == :compression_error
  assert first(refusal_of(decode(t, [64]))) == :compression_error
  assert table_max(get(value(decode(t, [32, 130])), :table)) == 0
  assert get(value(decode(t, [32, 130])), :fields) == [[":method", "GET"]]
  assert table_max(
    get(value(decode(with_limit(t, 4096), encode_int(4096, 5, 32))), :table)
  ) == 4096
  assert get(value(decode(t, [])), :fields) == []
end

test "an encoder signals a table resize first, the smallest size before the final one"
  t = resize(resize(table(4096), 0), 4096)
  out = encode(t, [[":method", "GET"]])
  assert get(out, :block) == [32, 63, 225, 31, 130]
  assert get(encode(get(out, :table), [[":method", "GET"]]), :block) == [130]
  back = value(decode(table(4096), get(out, :block)))
  assert table_max(get(back, :table)) == 4096
  assert get(back, :fields) == [[":method", "GET"]]
  assert get(encode(resize(table(4096), 100), []), :block) == [63, 69]
end

test "a field whose octets are not UTF-8 survives as bytes, and Huffman is used only when shorter"
  out = encode(table(4096), [["x-raw", [255, 0]], ["x-text", "aaaaaaaa"]])
  back = value(decode(table(4096), get(out, :block)))
  assert get(back, :fields) == [["x-raw", [255, 0]], ["x-text", "aaaaaaaa"]]
  assert entries(get(back, :table)) == entries(get(out, :table))
  assert encode_string("aaaaaaaa", :shorter) ==
    append([133], huffman_encode("aaaaaaaa"))
  assert encode_string([255, 0], :shorter) == [2, 255, 0]
  assert encode_string("a", false) == [1, 97]
end

def exchange(max, lists, hexes, huffman)
  cell = [table(max), table(max)]
  map(
    fn(i)
      out = encode(first(cell), nth(i, lists), {huffman:})
      back = value(decode(nth(1, cell), get(out, :block)))
      set!(cell, [get(out, :table), get(back, :table)])
      if bytes_hex(get(out, :block)) != bytes_hex(hex_bytes(nth(i, hexes)))
        raise(:mismatch, "block #{i}: #{bytes_hex(get(out, :block))}")
      end
      if get(back, :fields) != nth(i, lists) or
          entries(get(back, :table)) != entries(get(out, :table))
        raise(:mismatch, "decode #{i}")
      end
      table_size(get(out, :table))
    end,
    range(0, size(lists))
  )
end

def repeat_text(s, n)
  join(map((_i) -> s, range(0, n)), "")
end
