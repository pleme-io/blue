use("kiban", [:mmio_write])

UART0 = 268_435_456

def put(c: Int) -> Int
  mmio_write(UART0, 8, c)
  c
end

def twice(a: Int, b: Int) -> Int
  put(a)
  put(b)
end

put(put(put(104) + 1) - 1)
twice(put(97), put(98) + 1)
mmio_write(UART0, 8, put(120) + 1)
put(10)
