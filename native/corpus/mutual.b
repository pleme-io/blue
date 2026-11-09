use("kiban", [:mmio_write])

UART0 = 268_435_456

def put(c: Int) -> Int
  mmio_write(UART0, 8, c)
  c
end

def is_even(n: Int) -> Int
  if n == 0
    1
  else
    is_odd(n - 1)
  end
end

def is_odd(n: Int) -> Int
  if n == 0
    0
  else
    is_even(n - 1)
  end
end

put(48 + is_even(10))
put(48 + is_even(7))
put(48 + is_odd(9999))
put(10)
