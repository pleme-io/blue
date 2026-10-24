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

use("kyohi", [:ok, :ok?, :refusal, :refusal_of, :refused, :value])
use("retsu", [:first, :is_empty, :size, :slice])
use("shinsuu", [:be_bytes, :be_value, :bit_at, :bytes_hex, :hex_bytes])

preface = hex_bytes("505249202a20485454502f322e300d0a0d0a534d0d0a0d0a")

frame_types = [
  :data,
  :headers,
  :priority,
  :rst_stream,
  :settings,
  :push_promise,
  :ping,
  :goaway,
  :window_update,
  :continuation
]

error_codes = [
  :no_error,
  :protocol_error,
  :internal_error,
  :flow_control_error,
  :settings_timeout,
  :stream_closed,
  :frame_size_error,
  :refused_stream,
  :cancel,
  :compression_error,
  :connect_error,
  :enhance_your_calm,
  :inadequate_security,
  :http_1_1_required
]

setting_names = [
  :header_table_size,
  :enable_push,
  :max_concurrent_streams,
  :initial_window_size,
  :max_frame_size,
  :max_header_list_size
]

stream_states = [
  :idle,
  :reserved_local,
  :reserved_remote,
  :open,
  :half_closed_local,
  :half_closed_remote,
  :closed,
  :closed_after_reset
]

def code_of(name, names)
  i = position(name, names)
  if i < 0
    name
  else
    i
  end
end

def name_of(code, names)
  if code >= 0 and code < size(names)
    nth(code, names)
  else
    code
  end
end

def error_code(name)
  code_of(name, error_codes)
end

def error_name(code)
  name_of(code, error_codes)
end

def setting_id(name)
  code_of(name, append([nil], setting_names))
end

def setting_name(id)
  if id >= 1 and id <= size(setting_names)
    nth(id - 1, setting_names)
  else
    id
  end
end

def fault(scope, code, stream, why)
  assoc(assoc(refused(refusal(code, why)), :scope, scope), :stream, stream)
end

def scope_of(r)
  get(r, :scope)
end

def flag(on, bit)
  if on
    bit
  else
    0
  end
end

def zeros(n)
  map((_i) -> 0, range(0, n))
end

def header(len, type, flags, stream)
  append(be_bytes(len, 3), [type, flags], be_bytes(stream, 4))
end

def padded(pad, body)
  if pad.nil?
    body
  else
    append([pad], body, zeros(pad))
  end
end

def priority_bytes(p)
  dep = get(p, :depends_on) + flag(get(p, :exclusive), 2_147_483_648)
  append(be_bytes(dep, 4), [get(p, :weight) - 1])
end

def settings_bytes(pairs)
  flatten(
    map(
      fn(kv)
        append(be_bytes(setting_id(first(kv)), 2), be_bytes(nth(1, kv), 4))
      end,
      pairs
    )
  )
end

def headers_payload(f)
  p = get(f, :priority)
  lead = if p.nil?
    []
  else
    priority_bytes(p)
  end
  padded(get(f, :pad), append(lead, get(f, :block)))
end

def headers_flags(f)
  flag(get(f, :end_stream), 1) +
    flag(get(f, :end_headers), 4) +
    flag(not get(f, :pad).nil?, 8) +
    flag(not get(f, :priority).nil?, 32)
end

def wire(f)
  t = get(f, :type)
  case t
  when :data
    [
      0,
      flag(get(f, :end_stream), 1) + flag(not get(f, :pad).nil?, 8),
      padded(get(f, :pad), get(f, :data))
    ]
  when :headers
    [1, headers_flags(f), headers_payload(f)]
  when :priority
    [2, 0, priority_bytes(get(f, :priority))]
  when :rst_stream
    [3, 0, be_bytes(error_code(get(f, :code)), 4)]
  when :settings
    [4, flag(get(f, :ack), 1), append([], settings_bytes(get(f, :settings)))]
  when :push_promise
    [
      5,
      flag(get(f, :end_headers), 4) + flag(not get(f, :pad).nil?, 8),
      padded(
        get(f, :pad),
        append(be_bytes(get(f, :promised), 4), get(f, :block))
      )
    ]
  when :ping
    [6, flag(get(f, :ack), 1), get(f, :data)]
  when :goaway
    [
      7,
      0,
      append(
        be_bytes(get(f, :last_stream), 4),
        be_bytes(error_code(get(f, :code)), 4),
        get(f, :debug)
      )
    ]
  when :window_update
    [8, 0, be_bytes(get(f, :increment), 4)]
  when :continuation
    [9, flag(get(f, :end_headers), 4), get(f, :block)]
  when :unknown
    [get(f, :code), get(f, :flags), get(f, :payload)]
  else
    raise(:usage, "no frame type #{t}")
  end
end

def stream_of(f)
  if member?(get(f, :type), [:settings, :ping, :goaway])
    0
  else
    get(f, :stream)
  end
end

def encode(f)
  w = wire(f)
  body = nth(2, w)
  bytes = append(header(size(body), first(w), nth(1, w), stream_of(f)), body)
  back = decode(bytes, 16_777_215)
  if not ok?(back)
    raise(:usage, "this frame may not be sent: #{nth(1, refusal_of(back))}")
  end
  bytes
end

def conn(code, why)
  fault(:connection, code, 0, why)
end

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

def read_priority(bytes, pos)
  dep = be_value(bytes, pos, 4)
  {
    exclusive: dep >= 2_147_483_648,
    depends_on: dep % 2_147_483_648,
    weight: nth(pos + 4, bytes) + 1
  }
end

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
        data: nth(1, value(u))
      }
    )
  end
end

def headers_frame(payload, flags, stream)
  u = unpad(payload, stream, flags, :connection)
  prio = bit_at(flags, 5) == 1
  body = nth(1, value(u))
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

def rst_frame(payload, stream)
  if stream == 0
    conn(:protocol_error, "RST_STREAM on stream 0")
  elsif size(payload) != 4
    conn(:frame_size_error, "RST_STREAM of #{size(payload)} octets")
  else
    ok({type: :rst_stream, stream:, code: error_name(be_value(payload, 0, 4))})
  end
end

def setting_pair(payload, i)
  [setting_name(be_value(payload, 6 * i, 2)), be_value(payload, 6 * i + 2, 4)]
end

def bad_setting(kv)
  k = first(kv)
  v = nth(1, kv)
  if k == :enable_push and v > 1
    conn(:protocol_error, "ENABLE_PUSH of #{v}")
  elsif k == :initial_window_size and v > 2_147_483_647
    conn(:flow_control_error, "INITIAL_WINDOW_SIZE of #{v}")
  elsif k == :max_frame_size and (v < 16384 or v > 16_777_215)
    conn(:protocol_error, "MAX_FRAME_SIZE of #{v}")
  end
end

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

def push_frame(payload, flags, stream)
  u = unpad(payload, stream, flags, :connection)
  body = nth(1, value(u))
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

def ping_frame(payload, flags, stream)
  if stream != 0
    conn(:protocol_error, "PING on stream #{stream}")
  elsif size(payload) != 8
    conn(:frame_size_error, "PING of #{size(payload)} octets")
  else
    ok({type: :ping, ack: bit_at(flags, 0) == 1, data: payload})
  end
end

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

def oversize_scope(type, stream)
  if stream == 0 or member?(type, [1, 4, 5, 9])
    :connection
  else
    :stream
  end
end

def decode(bytes, max_frame_size)
  have = size(bytes)
  len = if have >= 9
    be_value(bytes, 0, 3)
  end
  type = nth(3, bytes)
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
    r = frame_of(type, nth(4, bytes), stream, slice(bytes, 9, len))
    if ok?(r)
      ok({frame: value(r), rest: slice(bytes, 9 + len, have - 9 - len)})
    else
      r
    end
  end
end

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

def allowed_send(state, kind)
  case state
  when :idle
    member?(kind, [:headers, :priority, :promised])
  when :reserved_local
    member?(kind, [:headers, :rst_stream, :priority])
  when :reserved_remote
    member?(kind, [:rst_stream, :window_update, :priority])
  when :half_closed_local
    member?(kind, [:window_update, :priority, :rst_stream, :continuation])
  when :closed
    kind == :priority
  when :closed_after_reset
    kind == :priority
  else
    true
  end
end

def after_send(state, kind)
  if kind == :rst_stream
    if member?(state, [:open, :half_closed_local])
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

def allowed_recv(state, kind)
  case state
  when :idle
    member?(kind, [:headers, :priority, :promised])
  when :reserved_local
    member?(kind, [:rst_stream, :priority, :window_update])
  when :reserved_remote
    member?(kind, [:headers, :rst_stream, :priority])
  when :half_closed_remote
    member?(kind, [:window_update, :priority, :rst_stream, :continuation])
  when :closed
    member?(kind, [:priority, :window_update, :rst_stream])
  else
    true
  end
end

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

def ends(state, dir, kind, end_stream)
  if end_stream and member?(kind, [:headers, :data])
    after_end_stream(state, dir)
  else
    state
  end
end

def step(state, dir, kind, end_stream, stream?)
  stream = stream or 0
  discard = member?(state, [:closed_after_reset]) or
    state == :closed and member?(kind, [:window_update, :rst_stream])
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
  r = read_preface(text_bytes("GET / HTTP/1.1\r\n"))
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
  h = get(value(decode(hex_bytes("000002010500000001 8286"), 16384)), :frame)
  assert get(h, :end_stream) and get(h, :end_headers)
  assert get(h, :block) == [130, 134]
  assert get(h, :priority).nil?
end

test "decode waits for a whole frame, ignores the reserved bit, and keeps what follows"
  ping = encode({type: :ping, ack: false, data: zeros(8)})
  assert decode([], 16384) == ok({frame: nil, need: 9})
  assert decode(slice(ping, 0, 5), 16384) == ok({frame: nil, need: 4})
  assert decode(slice(ping, 0, 12), 16384) == ok({frame: nil, need: 5})
  two = value(decode(append(ping, ping), 16384))
  assert get(two, :rest) == ping
  wu = hex_bytes("0000040800000000018000000a")
  assert get(value(decode(wu, 16384)), :frame) ==
    {type: :window_update, stream: 1, increment: 10}
  hi = hex_bytes("000004080080000001 0000000a")
  assert get(get(value(decode(hi, 16384)), :frame), :stream) == 1
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
  assert seen == map((c) -> [nth(1, c), nth(2, c)], cases)
  assert get(
    decode(hex_bytes("000004080000000003 80000000"), 16384),
    :stream
  ) == 3
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
  seen = map(
    fn(e)
      get(value(step(nth(0, e), nth(1, e), nth(2, e), nth(3, e), 1)), :state)
    end,
    edges
  )
  assert seen == map((e) -> nth(4, e), edges)
end

test "an illegal transition is refused with the error §5.1 and §6 name for it"
  cases = [
    [:idle, :recv, :data, :connection, :protocol_error],
    [:idle, :recv, :rst_stream, :connection, :protocol_error],
    [:idle, :recv, :window_update, :connection, :protocol_error],
    [:idle, :send, :data, :local, :protocol_error],
    [:reserved_local, :recv, :headers, :connection, :protocol_error],
    [:reserved_local, :recv, :data, :connection, :protocol_error],
    [:reserved_local, :send, :data, :local, :protocol_error],
    [:reserved_remote, :recv, :data, :connection, :protocol_error],
    [:reserved_remote, :recv, :window_update, :connection, :protocol_error],
    [:reserved_remote, :send, :headers, :local, :protocol_error],
    [:half_closed_local, :send, :data, :local, :protocol_error],
    [:half_closed_local, :send, :headers, :local, :protocol_error],
    [:half_closed_remote, :recv, :data, :stream, :stream_closed],
    [:half_closed_remote, :recv, :headers, :stream, :stream_closed],
    [:closed, :recv, :data, :stream, :stream_closed],
    [:closed, :recv, :headers, :connection, :stream_closed],
    [:closed, :send, :data, :local, :protocol_error],
    [:closed_after_reset, :send, :window_update, :local, :protocol_error]
  ]
  seen = map(
    fn(c)
      r = step(nth(0, c), nth(1, c), nth(2, c), false, 7)
      [scope_of(r), first(refusal_of(r))]
    end,
    cases
  )
  assert seen == map((c) -> [nth(3, c), nth(4, c)], cases)
  assert get(step(:half_closed_remote, :recv, :data, false, 7), :stream) == 7
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
