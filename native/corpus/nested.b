use("kiban", %i[mmio_write put_byte])

UART0 = 268_435_456

def twice(a: Int, b: Int) -> Int
  put_byte(a)
  put_byte(b)
end

put_byte(put_byte(put_byte(104) + 1) - 1)
twice(put_byte(97), put_byte(98) + 1)
mmio_write(UART0, 8, put_byte(120) + 1)
put_byte(10)
