use("shinsuu", %i[bytes_hex hex_bytes])

FRAMES = 400

def payload(seed, n)
  map((i) -> (seed * 31 + i * 17) % 256, range(n))
end

def frame(seed)
  body = payload(seed, 64)
  wire = bytes_hex(append([1, 0, 64], body))
  back = hex_bytes(wire)
  if back[3] != body[0]
    raise(:hexmsg, "round trip lost a byte")
  end
  length(wire)
end

write_stdout(unlines([reduce((a, s) -> a + frame(s), 0, range(FRAMES))]))
