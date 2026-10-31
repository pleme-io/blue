use("ibuki", %i[dock flash flash_send])
use("retsu", %i[first last])

@doc """
sendable: how many of `count` full packets a fresh Flash bucket sends at one instant.

    sendable(20) #=> 12
"""
def sendable(count: Int) -> Int
  last(
    reduce(
      fn(acc, _i)
        r = flash_send(first(acc), 1280, 0)
        if r.verdict == :sent
          [r.bucket, last(acc) + 1]
        else
          [r.bucket, last(acc)]
        end
      end,
      [flash({}), 0],
      range(count)
    )
  )
end

@doc """
line: one packet's verdict as the pacer prints it.

    line(5, {verdict: :wait, wait_ms: 16}) #=> "t=5 wait 16"
"""
def line(at: Int, r) -> Str
  if r.verdict == :wait
    "t=#{to_s(at)} wait #{to_s(r.wait_ms)}"
  else
    "t=#{to_s(at)} #{to_s(r.verdict)}"
  end
end

def main()
  out = reduce(
    fn(acc, _i)
      at = now_ms
      r = flash_send(first(acc), 1280, at)
      [r.bucket, append(last(acc), [line(at, r)])]
    end,
    [flash({}), []],
    range(16)
  )
  write_stdout(unlines(last(out)))
end

test "a fresh bucket sends twelve full packets and holds the thirteenth", {
  target: sendable
}
  assert sendable(0) == 0
  assert sendable(12) == 12
  assert sendable(20) == 12
end

test "the network is outside this frame: a breach no rescue swallows", {
  satisfies: %i[nist_ac_6 nist_sc_7],
  target: sendable
}
  assert_panics tcp_connect_ms("192.0.2.1", 80, 100) rescue :swallowed
end

test "the lock this project wrote docks as a crystal: the clock is provided and nothing else is reached"
  d = dock(
    {},
    json_read(read_file(path_join(getenv("GEN_ROOT", "."), "Bluefile.lock")))
  )
  assert d.class == :crystal
  assert d.reach == []
  assert d.refusals == []
end
