@moduledoc """
tajuu (多重) — multiplexing: HTTP/2's frames and the streams they carry
(RFC 9113).

A frame is a map with a `type` and that type's fields, bytes as lists of
integers. `decode` reads one frame from the front of the bytes received so
far and answers one of three things: the frame and the rest, `need` (more
bytes must arrive; not an error), or a refusal carrying the RFC's error code
as its kind plus `scope` (:connection or :stream) and the stream, so a
caller answers GOAWAY or RST_STREAM without re-deriving which. `encode`
writes a frame and refuses one `decode` would refuse. `step` is the stream
state machine of §5.1 as a pure function of a state and one event. A frame
of an unknown type decodes as :unknown, for the caller to discard (§4.1).
What needs a connection's memory (SETTINGS in force, CONTINUATION order,
stream-id parity, flow-control windows) is not here.

    error_name(99) #=> 99
"""

use("kyohi", %i[ok ok? refusal refusal_of refused value])
use("retsu", %i[first is_empty size slice])
use("shinsuu", %i[be_bytes be_value bit_at bytes_hex hex_bytes])

@doc """
preface: The 24 octets a client sends first on every HTTP/2 connection (§3.4).

    size(preface) #=> 24
    first(preface) #=> 80
"""
preface = hex_bytes("505249202a20485454502f322e300d0a0d0a534d0d0a0d0a")

@doc """
frame_types: The frame types of §6, each at the index that is its type code.

    frame_types[4] #=> :settings
"""
frame_types = %i[
  data
  headers
  priority
  rst_stream
  settings
  push_promise
  ping
  goaway
  window_update
  continuation
]

@doc """
error_codes: The error codes of §7, each at the index that is its code.

    error_codes[1] #=> :protocol_error
"""
error_codes = %i[
  no_error
  protocol_error
  internal_error
  flow_control_error
  settings_timeout
  stream_closed
  frame_size_error
  refused_stream
  cancel
  compression_error
  connect_error
  enhance_your_calm
  inadequate_security
  http_1_1_required
]

@doc """
setting_names: The settings of §6.5.2, in identifier order from 1.

    setting_names[4] #=> :max_frame_size
"""
setting_names = %i[
  header_table_size
  enable_push
  max_concurrent_streams
  initial_window_size
  max_frame_size
  max_header_list_size
]

@doc """
stream_states: The stream states of §5.1, with a closed stream that was reset kept apart.

    size(stream_states) #=> 8
"""
stream_states = %i[
  idle
  reserved_local
  reserved_remote
  open
  half_closed_local
  half_closed_remote
  closed
  closed_after_reset
]

@doc """
code_of: The index of `name` in `names`: its wire code. A name not listed is kept as it
is, so a code already numeric passes through.

    code_of(:b, %i[a b]) #=> 1
    code_of(7, %i[a b]) #=> 7
"""
def code_of(name, names)
  i = position(name, names)
  if i < 0
    name
  else
    i
  end
end

@doc """
name_of: The name at index `code` in `names`; a code past the list is kept as a number.

    name_of(1, %i[a b]) #=> :b
    name_of(9, %i[a b]) #=> 9
"""
def name_of(code, names)
  if code >= 0 and code < size(names)
    names[code]
  else
    code
  end
end

@doc """
error_code: The wire code of an error name; an unknown code is kept as a number.

    error_code(:protocol_error) #=> 1
    error_code(:http_1_1_required) #=> 13
"""
def error_code(name)
  code_of(name, error_codes)
end

@doc """
error_name: The name of an error code, or the code itself when §7 names none.

    error_name(8) #=> :cancel
"""
def error_name(code)
  name_of(code, error_codes)
end

@doc """
setting_id: The identifier of a setting name, counting from 1.

    setting_id(:header_table_size) #=> 1
    setting_id(:max_frame_size) #=> 5
"""
def setting_id(name)
  code_of(name, append([nil], setting_names))
end

@doc """
setting_name: The name of a setting identifier, or the identifier itself when unknown.

    setting_name(4) #=> :initial_window_size
    setting_name(99) #=> 99
"""
def setting_name(id)
  if id >= 1 and id <= size(setting_names)
    setting_names[id - 1]
  else
    id
  end
end

@doc """
fault: A refusal whose kind is the RFC error code, carrying the scope (:connection or
:stream) and the stream it is about.

    scope_of(fault(:stream, :cancel, 3, "gone")) #=> :stream
    fault(:stream, :cancel, 3, "gone")[:stream] #=> 3
"""
def fault(scope, code, stream, why)
  assoc(assoc(refused(refusal(code, why)), :scope, scope), :stream, stream)
end

@doc """
scope_of: Whether a refusal ends the connection or only its stream.

    scope_of(conn(:protocol_error, "bad")) #=> :connection
"""
def scope_of(r)
  r[:scope]
end

@doc """
flag: `bit` when `on`, else 0: one flag's share of a flags octet.

    flag(true, 4) #=> 4
    flag(false, 4) #=> 0
"""
def flag(on, bit)
  if on
    bit
  else
    0
  end
end

@doc """
zeros: `n` zero octets.

    zeros(3) #=> [0, 0, 0]
"""
def zeros(n)
  map((_i) -> 0, range(0, n))
end

@doc """
header: The 9-octet frame header of §4.1: a 24-bit length, the type, the flags, the
31-bit stream id.

    header(5, 0, 1, 3) #=> [0, 0, 5, 0, 1, 0, 0, 0, 3]
"""
def header(len, type, flags, stream)
  append(be_bytes(len, 3), [type, flags], be_bytes(stream, 4))
end

@doc """
padded: A payload with its padding: the pad length, the body, that many zeros. No pad
leaves the body as it is.

    padded(2, [7]) #=> [2, 7, 0, 0]
    padded(nil, [7]) #=> [7]
"""
def padded(pad, body)
  if pad.nil?
    body
  else
    append([pad], body, zeros(pad))
  end
end

@doc """
priority_bytes: A priority's five octets: the stream it depends on with the exclusive bit,
then the weight less one.

    priority_bytes({depends_on: 1, exclusive: true, weight: 16}) #=> [128, 0, 0, 1, 15]
"""
def priority_bytes(p)
  dep = p[:depends_on] + flag(p[:exclusive], 2_147_483_648)
  append(be_bytes(dep, 4), [p[:weight] - 1])
end

@doc """
settings_bytes: SETTINGS pairs as their six-octet entries: a 16-bit identifier, a 32-bit value.

    settings_bytes([[:enable_push, 0]]) #=> [0, 2, 0, 0, 0, 0]
"""
def settings_bytes(pairs)
  flatten(
    map(
      (kv) -> append(be_bytes(setting_id(first(kv)), 2), be_bytes(kv[1], 4)),
      pairs
    )
  )
end

@doc """
headers_payload: A HEADERS frame's payload: its priority when it has one, then the header
block, padded when it carries a pad.

    headers_payload({block: [130], pad: nil, priority: nil}) #=> [130]
"""
def headers_payload(f)
  p = f[:priority]
  lead = if p.nil?
    []
  else
    priority_bytes(p)
  end
  padded(f[:pad], append(lead, f[:block]))
end

@doc """
headers_flags: A HEADERS frame's flags octet: END_STREAM 1, END_HEADERS 4, PADDED 8,
PRIORITY 32.

    headers_flags({end_stream: true, end_headers: true, pad: nil, priority: nil}) #=> 5
"""
def headers_flags(f)
  flag(f[:end_stream], 1) +
    flag(f[:end_headers], 4) +
    flag(not f[:pad].nil?, 8) +
    flag(not f[:priority].nil?, 32)
end

@doc """
wire: A frame as [type code, flags, payload], before its header is written.

    wire({type: :ping, ack: true, data: [1, 2, 3, 4, 5, 6, 7, 8]}) #=> [6, 1, [1, 2, 3, 4, 5, 6, 7, 8]]
    wire({type: :window_update, increment: 1}) #=> [8, 0, [0, 0, 0, 1]]
"""
def wire(f)
  t = f[:type]
  case t
  when :data
    [
      0,
      flag(f[:end_stream], 1) + flag(not f[:pad].nil?, 8),
      padded(f[:pad], f[:data])
    ]
  when :headers
    [1, headers_flags(f), headers_payload(f)]
  when :priority
    [2, 0, priority_bytes(f[:priority])]
  when :rst_stream
    [3, 0, be_bytes(error_code(f[:code]), 4)]
  when :settings
    [4, flag(f[:ack], 1), append([], settings_bytes(f[:settings]))]
  when :push_promise
    [
      5,
      flag(f[:end_headers], 4) + flag(not f[:pad].nil?, 8),
      padded(f[:pad], append(be_bytes(f[:promised], 4), f[:block]))
    ]
  when :ping
    [6, flag(f[:ack], 1), f[:data]]
  when :goaway
    [
      7,
      0,
      append(
        be_bytes(f[:last_stream], 4),
        be_bytes(error_code(f[:code]), 4),
        f[:debug]
      )
    ]
  when :window_update
    [8, 0, be_bytes(f[:increment], 4)]
  when :continuation
    [9, flag(f[:end_headers], 4), f[:block]]
  when :unknown
    [f[:code], f[:flags], f[:payload]]
  else
    raise(:usage, "no frame type #{t}")
  end
end

@doc """
stream_of: The stream a frame is sent on: 0 for SETTINGS, PING and GOAWAY, which belong
to the connection, else its own.

    stream_of({type: :ping}) #=> 0
    stream_of({type: :data, stream: 3}) #=> 3
"""
def stream_of(f)
  if member?(f[:type], %i[settings ping goaway])
    0
  else
    f[:stream]
  end
end

@doc """
encode: A frame's bytes, header and payload. A frame `decode` would refuse is
refused here as :usage, so nothing malformed is sent.

    encode({type: :window_update, stream: 0, increment: 1}) #=> [0, 0, 4, 8, 0, 0, 0, 0, 0, 0, 0, 0, 1]
"""
def encode(f)
  w = wire(f)
  body = w[2]
  bytes = append(header(size(body), first(w), w[1], stream_of(f)), body)
  back = decode(bytes, 16_777_215)
  if not ok?(back)
    raise(:usage, "this frame may not be sent: #{refusal_of(back)[1]}")
  end
  bytes
end

@doc """
conn: A refusal that ends the whole connection, on stream 0.

    conn(:protocol_error, "bad")[:stream] #=> 0
"""
def conn(code, why)
  fault(:connection, code, 0, why)
end

@doc """
unpad: A payload's body without its padding, as [pad length, body]; a frame without
the PADDED flag (bit 3) is [nil, payload]. Padding that fills the payload is a
connection error.

    value(unpad([2, 7, 0, 0], 1, 8, :stream)) #=> [2, [7]]
    value(unpad([7], 1, 0, :stream)) #=> [nil, [7]]
"""
def unpad(payload, stream, flags, scope)
  len = size(payload)
  if bit_at(flags, 3) == 0
    ok([nil, payload])
  elsif len < 1
    fault(scope, :frame_size_error, stream, "a padded frame has no pad length")
  elsif first(payload) >= len
    conn(
      :protocol_error,
      "padding of #{first(payload)} fills a payload of #{len}"
    )
  else
    ok([first(payload), slice(payload, 1, len - 1 - first(payload))])
  end
end

@doc """
read_priority: The priority written at `pos`: the exclusive bit, the stream it depends on,
and the weight (the octet plus one).

    read_priority([128, 0, 0, 1, 15], 0) #=> {exclusive: true, depends_on: 1, weight: 16}
"""
def read_priority(bytes, pos)
  dep = be_value(bytes, pos, 4)
  {
    exclusive: dep >= 2_147_483_648,
    depends_on: dep % 2_147_483_648,
    weight: bytes[pos + 4] + 1
  }
end

@doc """
data_frame: A DATA frame read from its payload and flags; DATA on stream 0 is a
connection error.

    value(data_frame([104, 105], 1, 1)) #=> {type: :data, stream: 1, end_stream: true, pad: nil, data: [104, 105]}
    scope_of(data_frame([], 0, 0)) #=> :connection
"""
def data_frame(payload, flags, stream)
  u = unpad(payload, stream, flags, :stream)
  if stream == 0
    conn(:protocol_error, "DATA on stream 0")
  elsif not ok?(u)
    u
  else
    ok(
      {
        type: :data,
        stream:,
        end_stream: bit_at(flags, 0) == 1,
        pad: first(value(u)),
        data: value(u)[1]
      }
    )
  end
end

@doc """
headers_frame: A HEADERS frame read from its payload and flags: the priority when the
PRIORITY flag is set, then the header block.

    value(headers_frame([130], 4, 1))[:block] #=> [130]
    value(headers_frame([130], 4, 1))[:end_headers] #=> true
"""
def headers_frame(payload, flags, stream)
  u = unpad(payload, stream, flags, :connection)
  prio = bit_at(flags, 5) == 1
  body = value(u)[1]
  if stream == 0
    conn(:protocol_error, "HEADERS on stream 0")
  elsif not ok?(u)
    u
  elsif prio and size(body) < 5
    conn(:frame_size_error, "HEADERS has no room for its priority")
  else
    ok(
      {
        type: :headers,
        stream:,
        end_stream: bit_at(flags, 0) == 1,
        end_headers: bit_at(flags, 2) == 1,
        pad: first(value(u)),
        priority: if prio
          read_priority(body, 0)
        end,
        block: if prio
          slice(body, 5, size(body) - 5)
        else
          body
        end
      }
    )
  end
end

@doc """
priority_frame: A PRIORITY frame: five octets on a stream other than 0. A wrong length is
a stream error.

    value(priority_frame([0, 0, 0, 1, 15], 3))[:priority][:weight] #=> 16
    scope_of(priority_frame([0], 3)) #=> :stream
"""
def priority_frame(payload, stream)
  if stream == 0
    conn(:protocol_error, "PRIORITY on stream 0")
  elsif size(payload) != 5
    fault(
      :stream,
      :frame_size_error,
      stream,
      "PRIORITY of #{size(payload)} octets"
    )
  else
    ok({type: :priority, stream:, priority: read_priority(payload, 0)})
  end
end

@doc """
rst_frame: An RST_STREAM frame: a four-octet error code on a stream other than 0.

    value(rst_frame([0, 0, 0, 8], 3)) #=> {type: :rst_stream, stream: 3, code: :cancel}
"""
def rst_frame(payload, stream)
  if stream == 0
    conn(:protocol_error, "RST_STREAM on stream 0")
  elsif size(payload) != 4
    conn(:frame_size_error, "RST_STREAM of #{size(payload)} octets")
  else
    ok({type: :rst_stream, stream:, code: error_name(be_value(payload, 0, 4))})
  end
end

@doc """
setting_pair: The `i`th six-octet SETTINGS entry as [name, value].

    setting_pair([0, 2, 0, 0, 0, 0], 0) #=> [:enable_push, 0]
"""
def setting_pair(payload, i)
  [setting_name(be_value(payload, 6 * i, 2)), be_value(payload, 6 * i + 2, 4)]
end

@doc """
bad_setting: The connection error a setting's value makes (§6.5.2), or nil when it is
in range.

    bad_setting([:enable_push, 1]) #=> nil
    scope_of(bad_setting([:max_frame_size, 100])) #=> :connection
"""
def bad_setting(kv)
  k = first(kv)
  v = kv[1]
  if k == :enable_push and v > 1
    conn(:protocol_error, "ENABLE_PUSH of #{v}")
  elsif k == :initial_window_size and v > 2_147_483_647
    conn(:flow_control_error, "INITIAL_WINDOW_SIZE of #{v}")
  elsif k == :max_frame_size and (v < 16384 or v > 16_777_215)
    conn(:protocol_error, "MAX_FRAME_SIZE of #{v}")
  end
end

@doc """
settings_frame: A SETTINGS frame: an ack with no payload, or whole six-octet entries on
stream 0, each value in range.

    value(settings_frame([0, 2, 0, 0, 0, 0], 0, 0)) #=> {type: :settings, ack: false, settings: [[:enable_push, 0]]}
    value(settings_frame([], 1, 0)) #=> {type: :settings, ack: true, settings: []}
"""
def settings_frame(payload, flags, stream)
  ack = bit_at(flags, 0) == 1
  len = size(payload)
  pairs = if len % 6 == 0
    map((i) -> setting_pair(payload, i), range(0, len / 6))
  else
    []
  end
  bad = filter((r) -> not r.nil?, map(bad_setting, pairs))
  if stream != 0
    conn(:protocol_error, "SETTINGS on stream #{stream}")
  elsif ack and len != 0
    conn(:frame_size_error, "a SETTINGS ack carries #{len} octets")
  elsif len % 6 != 0
    conn(:frame_size_error, "SETTINGS of #{len} octets")
  elsif not is_empty(bad)
    first(bad)
  else
    ok({type: :settings, ack:, settings: pairs})
  end
end

@doc """
push_frame: A PUSH_PROMISE frame: the promised stream, never 0, then a header block.

    value(push_frame([0, 0, 0, 2, 130], 4, 1))[:promised] #=> 2
"""
def push_frame(payload, flags, stream)
  u = unpad(payload, stream, flags, :connection)
  body = value(u)[1]
  if stream == 0
    conn(:protocol_error, "PUSH_PROMISE on stream 0")
  elsif not ok?(u)
    u
  elsif size(body) < 4
    conn(:frame_size_error, "PUSH_PROMISE has no promised stream")
  elsif be_value(body, 0, 4) % 2_147_483_648 == 0
    conn(:protocol_error, "PUSH_PROMISE promises stream 0")
  else
    ok(
      {
        type: :push_promise,
        stream:,
        end_headers: bit_at(flags, 2) == 1,
        pad: first(value(u)),
        promised: be_value(body, 0, 4) % 2_147_483_648,
        block: slice(body, 4, size(body) - 4)
      }
    )
  end
end

@doc """
ping_frame: A PING frame: exactly eight octets, on stream 0.

    value(ping_frame([1, 2, 3, 4, 5, 6, 7, 8], 1, 0))[:ack] #=> true
    ok?(ping_frame([1], 0, 0)) #=> false
"""
def ping_frame(payload, flags, stream)
  if stream != 0
    conn(:protocol_error, "PING on stream #{stream}")
  elsif size(payload) != 8
    conn(:frame_size_error, "PING of #{size(payload)} octets")
  else
    ok({type: :ping, ack: bit_at(flags, 0) == 1, data: payload})
  end
end

@doc """
goaway_frame: A GOAWAY frame on stream 0: the last stream processed, the error code and
any debug octets.

    value(goaway_frame([0, 0, 0, 5, 0, 0, 0, 0], 0)) #=> {type: :goaway, last_stream: 5, code: :no_error, debug: []}
"""
def goaway_frame(payload, stream)
  if stream != 0
    conn(:protocol_error, "GOAWAY on stream #{stream}")
  elsif size(payload) < 8
    conn(:frame_size_error, "GOAWAY of #{size(payload)} octets")
  else
    ok(
      {
        type: :goaway,
        last_stream: be_value(payload, 0, 4) % 2_147_483_648,
        code: error_name(be_value(payload, 4, 4)),
        debug: slice(payload, 8, size(payload) - 8)
      }
    )
  end
end

@doc """
window_frame: A WINDOW_UPDATE frame: a four-octet increment that is not 0. A zero
increment is a stream error on a stream, a connection error on stream 0.

    value(window_frame([0, 0, 0, 9], 1))[:increment] #=> 9
    scope_of(window_frame([0, 0, 0, 0], 1)) #=> :stream
"""
def window_frame(payload, stream)
  inc = if size(payload) == 4
    be_value(payload, 0, 4) % 2_147_483_648
  end
  if size(payload) != 4
    conn(:frame_size_error, "WINDOW_UPDATE of #{size(payload)} octets")
  elsif inc == 0 and stream == 0
    conn(:protocol_error, "a connection WINDOW_UPDATE of 0")
  elsif inc == 0
    fault(:stream, :protocol_error, stream, "a WINDOW_UPDATE of 0")
  else
    ok({type: :window_update, stream:, increment: inc})
  end
end

@doc """
continuation_frame: A CONTINUATION frame: more of a header block, on a stream other than 0.

    value(continuation_frame([130], 4, 1)) #=> {type: :continuation, stream: 1, end_headers: true, block: [130]}
"""
def continuation_frame(payload, flags, stream)
  if stream == 0
    conn(:protocol_error, "CONTINUATION on stream 0")
  else
    ok(
      {
        type: :continuation,
        stream:,
        end_headers: bit_at(flags, 2) == 1,
        block: payload
      }
    )
  end
end

@doc """
frame_of: The frame a type code, flags, stream and payload make; an unknown type is
kept as :unknown, for the caller to discard (§4.1).

    value(frame_of(42, 0, 1, [7]))[:type] #=> :unknown
"""
def frame_of(type, flags, stream, payload)
  case type
  when 0
    data_frame(payload, flags, stream)
  when 1
    headers_frame(payload, flags, stream)
  when 2
    priority_frame(payload, stream)
  when 3
    rst_frame(payload, stream)
  when 4
    settings_frame(payload, flags, stream)
  when 5
    push_frame(payload, flags, stream)
  when 6
    ping_frame(payload, flags, stream)
  when 7
    goaway_frame(payload, stream)
  when 8
    window_frame(payload, stream)
  when 9
    continuation_frame(payload, flags, stream)
  else
    ok({type: :unknown, code: type, flags:, stream:, payload:})
  end
end

@doc """
oversize_scope: What a frame over the size limit ends (§4.2): the connection for stream 0
and for frames that change header state, else only the stream.

    oversize_scope(0, 1) #=> :stream
    oversize_scope(1, 1) #=> :connection
"""
def oversize_scope(type, stream)
  if stream == 0 or member?(type, [1, 4, 5, 9])
    :connection
  else
    :stream
  end
end

@doc """
decode: One frame from the front of the bytes so far: the frame and the rest, how
many more bytes are needed, or a refusal carrying its scope and stream.

    value(decode([0, 0], 16384)) #=> {frame: nil, need: 7}
    value(decode([0, 0, 4, 8, 0, 0, 0, 0, 0, 0, 0, 0, 1, 9], 16384)) #=> {frame: {type: :window_update, stream: 0, increment: 1}, rest: [9]}
"""
def decode(bytes, max_frame_size)
  have = size(bytes)
  len = if have >= 9
    be_value(bytes, 0, 3)
  end
  type = bytes[3]
  stream = if have >= 9
    be_value(bytes, 5, 4) % 2_147_483_648
  end
  if have < 9
    ok({frame: nil, need: 9 - have})
  elsif len > max_frame_size
    fault(
      oversize_scope(type, stream),
      :frame_size_error,
      stream,
      "a frame of #{len} octets is over #{max_frame_size}"
    )
  elsif have < 9 + len
    ok({frame: nil, need: 9 + len - have})
  else
    r = frame_of(type, bytes[4], stream, slice(bytes, 9, len))
    if ok?(r)
      ok({frame: value(r), rest: slice(bytes, 9 + len, have - 9 - len)})
    else
      r
    end
  end
end

@doc """
read_preface: The connection preface read from the front of the bytes: the rest once all
24 octets match, how many more are needed while a prefix matches, and a
connection error on the first octet that does not.

    value(read_preface(slice(preface, 0, 10))) #=> {rest: nil, need: 14}
    ok?(read_preface([1])) #=> false
"""
def read_preface(bytes)
  n = blue::min(size(bytes), 24)
  if slice(bytes, 0, n) != slice(preface, 0, n)
    conn(:protocol_error, "the connection preface is wrong")
  elsif n < 24
    ok({rest: nil, need: 24 - n})
  else
    ok({rest: slice(bytes, 24, size(bytes) - 24)})
  end
end

@doc """
allowed_send: Whether a frame of `kind` may be sent on a stream in `state` (§5.1).

    allowed_send(:idle, :headers) #=> true
    allowed_send(:idle, :data) #=> false
"""
def allowed_send(state, kind)
  case state
  when :idle
    member?(kind, %i[headers priority promised])
  when :reserved_local
    member?(kind, %i[headers rst_stream priority])
  when :reserved_remote
    member?(kind, %i[rst_stream window_update priority])
  when :half_closed_local
    member?(kind, %i[window_update priority rst_stream continuation])
  when :closed
    kind == :priority
  when :closed_after_reset
    kind == :priority
  else
    true
  end
end

@doc """
after_send: The state a stream moves to on sending `kind`, before END_STREAM is applied.

    after_send(:idle, :headers) #=> :open
    after_send(:open, :rst_stream) #=> :closed_after_reset
"""
def after_send(state, kind)
  if kind == :rst_stream
    if member?(state, %i[open half_closed_local])
      :closed_after_reset
    else
      :closed
    end
  elsif state == :idle and kind == :headers
    :open
  elsif state == :idle and kind == :promised
    :reserved_local
  elsif state == :reserved_local and kind == :headers
    :half_closed_remote
  else
    state
  end
end

@doc """
recv_refusal: The error for receiving `kind` where §5.1 forbids it: STREAM_CLOSED on a
half-closed (remote) stream and for DATA on a closed one, else a connection
error.

    scope_of(recv_refusal(:half_closed_remote, :data, 1)) #=> :stream
    scope_of(recv_refusal(:idle, :data, 1)) #=> :connection
"""
def recv_refusal(state, kind, stream)
  if state == :half_closed_remote
    fault(
      :stream,
      :stream_closed,
      stream,
      "#{kind} on a half-closed (remote) stream"
    )
  elsif state == :closed and kind == :data
    fault(:stream, :stream_closed, stream, "DATA on a closed stream")
  elsif state == :closed
    conn(:stream_closed, "#{kind} on closed stream #{stream}")
  else
    conn(:protocol_error, "#{kind} on stream #{stream} in state #{state}")
  end
end

@doc """
allowed_recv: Whether a frame of `kind` may be received on a stream in `state` (§5.1).

    allowed_recv(:closed, :window_update) #=> true
    allowed_recv(:closed, :headers) #=> false
"""
def allowed_recv(state, kind)
  case state
  when :idle
    member?(kind, %i[headers priority promised])
  when :reserved_local
    member?(kind, %i[rst_stream priority window_update])
  when :reserved_remote
    member?(kind, %i[headers rst_stream priority])
  when :half_closed_remote
    member?(kind, %i[window_update priority rst_stream continuation])
  when :closed
    member?(kind, %i[priority window_update rst_stream])
  else
    true
  end
end

@doc """
after_recv: The state a stream moves to on receiving `kind`, before END_STREAM is applied.

    after_recv(:idle, :promised) #=> :reserved_remote
    after_recv(:open, :rst_stream) #=> :closed
"""
def after_recv(state, kind)
  if kind == :rst_stream and state != :closed_after_reset
    :closed
  elsif state == :idle and kind == :headers
    :open
  elsif state == :idle and kind == :promised
    :reserved_remote
  elsif state == :reserved_remote and kind == :headers
    :half_closed_local
  else
    state
  end
end

@doc """
after_end_stream: The state after END_STREAM in direction `dir`: one side closes, and the
second side to close closes the stream.

    after_end_stream(:open, :send) #=> :half_closed_local
    after_end_stream(:half_closed_local, :recv) #=> :closed
"""
def after_end_stream(state, dir)
  if dir == :send and state == :open
    :half_closed_local
  elsif dir == :send and state == :half_closed_remote
    :closed
  elsif dir == :recv and state == :open
    :half_closed_remote
  elsif dir == :recv and state == :half_closed_local
    :closed
  else
    state
  end
end

@doc """
ends: END_STREAM applied when it is set on a HEADERS or DATA frame; any other frame
leaves the state.

    ends(:open, :recv, :data, true) #=> :half_closed_remote
    ends(:open, :recv, :ping, true) #=> :open
"""
def ends(state, dir, kind, end_stream)
  if end_stream and member?(kind, %i[headers data])
    after_end_stream(state, dir)
  else
    state
  end
end

@doc """
step: The stream state machine of §5.1: one frame sent or received in a state gives
the next state and whether to discard the frame, or a refusal. A frame this
side may not send is refused with scope :local.

    value(step(:idle, :send, :headers, true, 1)) #=> {state: :half_closed_local, discard: false}
    scope_of(step(:idle, :send, :data, false, 1)) #=> :local
"""
def step(state, dir, kind, end_stream, stream?)
  stream = stream or 0
  discard = member?(state, [:closed_after_reset]) or
    state == :closed and member?(kind, %i[window_update rst_stream])
  if not member?(state, stream_states)
    raise(:usage, "no stream state #{state}")
  elsif dir == :send and not allowed_send(state, kind)
    fault(
      :local,
      :protocol_error,
      stream,
      "#{kind} may not be sent in state #{state}"
    )
  elsif dir == :send
    ok(
      {
        state: ends(after_send(state, kind), :send, kind, end_stream),
        discard: false
      }
    )
  elsif not allowed_recv(state, kind)
    recv_refusal(state, kind, stream)
  else
    ok(
      {state: ends(after_recv(state, kind), :recv, kind, end_stream), discard:}
    )
  end
end

test "the connection preface is the 24 octets of §3.4, read in pieces"
  assert size(preface) == 24
  assert bytes_text(slice(preface, 0, 14)) == "PRI * HTTP/2.0"
  assert slice(preface, 14, 4) == [13, 10, 13, 10]
  assert bytes_text(slice(preface, 18, 2)) == "SM"
  assert slice(preface, 20, 4) == [13, 10, 13, 10]
  assert read_preface(slice(preface, 0, 10)) == ok({rest: nil, need: 14})
  assert read_preface(append(preface, [0, 0])) == ok({rest: [0, 0]})
  assert read_preface([]) == ok({rest: nil, need: 24})
  assert read_preface(slice(preface, 0, 23)) == ok({rest: nil, need: 1})
  assert read_preface(preface) == ok({rest: []})
  r = read_preface(text_bytes(unlines(["GET / HTTP/1.1\r"])))
  assert first(refusal_of(r)) == :protocol_error
  assert scope_of(r) == :connection
end

test "every frame type round-trips through encode and decode"
  frames = [
    {type: :data, stream: 1, end_stream: true, pad: nil, data: [1, 2, 3]},
    {type: :data, stream: 3, end_stream: false, pad: 4, data: []},
    {
      type: :headers,
      stream: 1,
      end_stream: false,
      end_headers: true,
      pad: nil,
      priority: nil,
      block: [130, 134]
    },
    {
      type: :headers,
      stream: 5,
      end_stream: true,
      end_headers: false,
      pad: 2,
      priority: {exclusive: true, depends_on: 3, weight: 256},
      block: [130]
    },
    {
      type: :priority,
      stream: 7,
      priority: {exclusive: false, depends_on: 0, weight: 16}
    },
    {type: :rst_stream, stream: 1, code: :cancel},
    {type: :rst_stream, stream: 1, code: 99},
    {
      type: :settings,
      ack: false,
      settings: [
        [:initial_window_size, 65535],
        [:max_frame_size, 16384],
        [42, 7]
      ]
    },
    {type: :settings, ack: true, settings: []},
    {
      type: :push_promise,
      stream: 1,
      end_headers: true,
      pad: nil,
      promised: 2,
      block: [136]
    },
    {type: :ping, ack: true, data: [1, 2, 3, 4, 5, 6, 7, 8]},
    {
      type: :goaway,
      last_stream: 2_147_483_647,
      code: :no_error,
      debug: text_bytes("bye")
    },
    {type: :window_update, stream: 0, increment: 2_147_483_647},
    {type: :continuation, stream: 1, end_headers: true, block: [1]},
    {type: :unknown, code: 250, flags: 9, stream: 3, payload: [7]}
  ]
  same = map(
    (f) -> value(decode(encode(f), 16384)) == {frame: f, rest: []},
    frames
  )
  assert same == map((_f) -> true, frames)
end

test "the bytes of known frames, checked by hand against §4.1 and §6"
  assert bytes_hex(encode({type: :settings, ack: true, settings: []})) ==
    "000000040100000000"
  assert bytes_hex(encode({type: :window_update, stream: 1, increment: 1})) ==
    "00000408000000000100000001"
  assert bytes_hex(
    encode({type: :data, stream: 1, end_stream: true, pad: 1, data: [255]})
  ) == "00000300090000000101ff00"
  assert bytes_hex(
    encode({type: :rst_stream, stream: 3, code: :refused_stream})
  ) == "00000403000000000300000007"
  h = value(decode(hex_bytes("000002010500000001 8286"), 16384))[:frame]
  assert h[:end_stream] and h[:end_headers]
  assert h[:block] == [130, 134]
  assert h[:priority].nil?
end

test "decode waits for a whole frame, ignores the reserved bit, and keeps what follows"
  ping = encode({type: :ping, ack: false, data: zeros(8)})
  assert decode([], 16384) == ok({frame: nil, need: 9})
  assert decode(slice(ping, 0, 5), 16384) == ok({frame: nil, need: 4})
  assert decode(slice(ping, 0, 12), 16384) == ok({frame: nil, need: 5})
  two = value(decode(append(ping, ping), 16384))
  assert two[:rest] == ping
  wu = hex_bytes("0000040800000000018000000a")
  assert value(decode(wu, 16384))[:frame] ==
    {type: :window_update, stream: 1, increment: 10}
  hi = hex_bytes("000004080080000001 0000000a")
  assert value(decode(hi, 16384))[:frame][:stream] == 1
end

test "malformed frames are refused with the code and scope RFC 9113 names"
  cases = [
    ["000001000000000000 00", :connection, :protocol_error],
    ["000002000800000001 0505", :connection, :protocol_error],
    ["000002000800000001 0200", :connection, :protocol_error],
    ["000000000800000001", :stream, :frame_size_error],
    ["000001010000000000 82", :connection, :protocol_error],
    ["000002012000000001 0000", :connection, :frame_size_error],
    ["000004020000000001 00000000", :stream, :frame_size_error],
    ["000005020000000000 0000000010", :connection, :protocol_error],
    ["000003030000000001 000000", :connection, :frame_size_error],
    ["000004030000000000 00000008", :connection, :protocol_error],
    ["000006040000000001 000300000064", :connection, :protocol_error],
    ["000006040100000000 000300000064", :connection, :frame_size_error],
    ["000005040000000000 0003000000", :connection, :frame_size_error],
    ["000006040000000000 000200000002", :connection, :protocol_error],
    ["000006040000000000 000480000000", :connection, :flow_control_error],
    ["000006040000000000 000500003fff", :connection, :protocol_error],
    ["000006040000000000 000501000000", :connection, :protocol_error],
    ["000004050400000000 00000002", :connection, :protocol_error],
    ["000004050400000001 00000000", :connection, :protocol_error],
    ["000003050400000001 000000", :connection, :frame_size_error],
    ["000008060000000001 0000000000000000", :connection, :protocol_error],
    ["000007060000000000 00000000000000", :connection, :frame_size_error],
    ["000008070000000001 0000000000000000", :connection, :protocol_error],
    ["000007070000000000 00000000000000", :connection, :frame_size_error],
    ["000003080000000001 000001", :connection, :frame_size_error],
    ["000004080000000000 00000000", :connection, :protocol_error],
    ["000004080000000003 80000000", :stream, :protocol_error],
    ["000001090400000000 82", :connection, :protocol_error]
  ]
  seen = map(
    fn(c)
      r = decode(hex_bytes(first(c)), 16384)
      [scope_of(r), first(refusal_of(r))]
    end,
    cases
  )
  assert seen == map((c) -> [c[1], c[2]], cases)
  assert decode(hex_bytes("000004080000000003 80000000"), 16384)[:stream] == 3
end

test "a frame over SETTINGS_MAX_FRAME_SIZE is refused, on the connection when it could change it"
  big = append(header(16385, 0, 0, 1), zeros(16385))
  assert scope_of(decode(big, 16384)) == :stream
  assert first(refusal_of(decode(big, 16384))) == :frame_size_error
  assert ok?(decode(big, 16385))
  assert scope_of(decode(append(header(20000, 1, 4, 1), []), 16384)) ==
    :connection
  assert scope_of(decode(header(20000, 8, 0, 0), 16384)) == :connection
end

test "encode refuses a frame no endpoint may send, and names the rule"
  caught = begin
    encode({type: :data, stream: 0, end_stream: false, pad: nil, data: []})
  rescue e
    e
  end
  assert caught.kind == :usage
  assert contains?(caught.message, "DATA on stream 0")
  wrong = begin
    encode({type: :nonesuch})
  rescue e
    e
  end
  assert wrong.kind == :usage
end

test "the codes of §7 and §6.5.2 keep their numbers, and an unknown one stays a number"
  assert error_code(:no_error) == 0
  assert error_code(:compression_error) == 9
  assert error_code(:http_1_1_required) == 13
  assert error_name(11) == :enhance_your_calm
  assert error_name(99) == 99
  assert setting_id(:header_table_size) == 1
  assert setting_id(:max_header_list_size) == 6
  assert size(frame_types) == 10
end

test "every edge of the stream state diagram, Figure 2 of §5.1"
  edges = [
    [:idle, :send, :headers, false, :open],
    [:idle, :recv, :headers, false, :open],
    [:idle, :send, :headers, true, :half_closed_local],
    [:idle, :recv, :headers, true, :half_closed_remote],
    [:idle, :send, :promised, false, :reserved_local],
    [:idle, :recv, :promised, false, :reserved_remote],
    [:idle, :send, :priority, false, :idle],
    [:idle, :recv, :priority, false, :idle],
    [:reserved_local, :send, :headers, false, :half_closed_remote],
    [:reserved_local, :send, :headers, true, :closed],
    [:reserved_local, :send, :rst_stream, false, :closed],
    [:reserved_local, :recv, :rst_stream, false, :closed],
    [:reserved_local, :recv, :window_update, false, :reserved_local],
    [:reserved_remote, :recv, :headers, false, :half_closed_local],
    [:reserved_remote, :recv, :headers, true, :closed],
    [:reserved_remote, :send, :rst_stream, false, :closed],
    [:reserved_remote, :recv, :rst_stream, false, :closed],
    [:reserved_remote, :send, :window_update, false, :reserved_remote],
    [:open, :send, :data, true, :half_closed_local],
    [:open, :recv, :data, true, :half_closed_remote],
    [:open, :send, :data, false, :open],
    [:open, :recv, :push_promise, false, :open],
    [:open, :send, :rst_stream, false, :closed_after_reset],
    [:open, :recv, :rst_stream, false, :closed],
    [:half_closed_local, :recv, :data, true, :closed],
    [:half_closed_local, :recv, :headers, false, :half_closed_local],
    [:half_closed_local, :send, :window_update, false, :half_closed_local],
    [:half_closed_local, :send, :rst_stream, false, :closed_after_reset],
    [:half_closed_local, :recv, :rst_stream, false, :closed],
    [:half_closed_remote, :send, :data, true, :closed],
    [:half_closed_remote, :send, :headers, false, :half_closed_remote],
    [:half_closed_remote, :recv, :window_update, false, :half_closed_remote],
    [:half_closed_remote, :recv, :continuation, false, :half_closed_remote],
    [:half_closed_remote, :send, :rst_stream, false, :closed],
    [:half_closed_remote, :recv, :rst_stream, false, :closed],
    [:closed, :send, :priority, false, :closed],
    [:closed, :recv, :priority, false, :closed],
    [:closed, :recv, :window_update, false, :closed],
    [:closed_after_reset, :recv, :data, false, :closed_after_reset],
    [:closed_after_reset, :recv, :headers, true, :closed_after_reset]
  ]
  seen = map((e) -> value(step(e[0], e[1], e[2], e[3], 1))[:state], edges)
  assert seen == map((e) -> e[4], edges)
end

test "an illegal transition is refused with the error §5.1 and §6 name for it"
  cases = [
    %i[idle recv data connection protocol_error],
    %i[idle recv rst_stream connection protocol_error],
    %i[idle recv window_update connection protocol_error],
    %i[idle send data local protocol_error],
    %i[reserved_local recv headers connection protocol_error],
    %i[reserved_local recv data connection protocol_error],
    %i[reserved_local send data local protocol_error],
    %i[reserved_remote recv data connection protocol_error],
    %i[reserved_remote recv window_update connection protocol_error],
    %i[reserved_remote send headers local protocol_error],
    %i[half_closed_local send data local protocol_error],
    %i[half_closed_local send headers local protocol_error],
    %i[half_closed_remote recv data stream stream_closed],
    %i[half_closed_remote recv headers stream stream_closed],
    %i[closed recv data stream stream_closed],
    %i[closed recv headers connection stream_closed],
    %i[closed send data local protocol_error],
    %i[closed_after_reset send window_update local protocol_error]
  ]
  seen = map(
    fn(c)
      r = step(c[0], c[1], c[2], false, 7)
      [scope_of(r), first(refusal_of(r))]
    end,
    cases
  )
  assert seen == map((c) -> [c[3], c[4]], cases)
  assert step(:half_closed_remote, :recv, :data, false, 7)[:stream] == 7
end

test "frames that arrive after this end reset a stream are discarded, not refused"
  assert step(:closed_after_reset, :recv, :data, false) ==
    ok({state: :closed_after_reset, discard: true})
  assert step(:closed, :recv, :window_update, false) ==
    ok({state: :closed, discard: true})
  assert step(:closed, :recv, :priority, false) ==
    ok({state: :closed, discard: false})
  assert step(:open, :recv, :data, false) == ok({state: :open, discard: false})
  assert size(stream_states) == 8
  wrong = begin
    step(:nowhere, :recv, :data, false)
  rescue e
    e
  end
  assert wrong.kind == :usage
end
