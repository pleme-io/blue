use("kiban", [:mmio_write])

UART0 = 268_435_456

def put(c: Int) -> Int
  mmio_write(UART0, 8, c)
  c
end

def grow(n: Int) -> Int
  put(43)
  grow(n * 1000)
end

grow(1)
