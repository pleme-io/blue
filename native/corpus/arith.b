use("kiban", [:mmio_write])

UART0 = 268_435_456
SPAN = 7 * 6 - 2
HALF = floor(SPAN / 3)

def put(c: Int) -> Int
  mmio_write(UART0, 8, c)
  c
end

def digits(n: Int) -> Int
  if n >= 10
    digits(floor(n / 10))
  end
  put(48 + n % 10)
end

def show(n: Int) -> Int
  if n < 0
    put(45)
    digits(-n)
  else
    digits(n)
  end
  put(32)
end

def pick(a: Int, b: Int) -> Int
  if a != b and not (a > b) or a == 0
    a
  else
    b
  end
end

K = show(HALF)
show(-7 % 3)
show(7 % -3)
show(floor(-7 / 2))
show(floor(7 / -2))
show(floor(-8 / 2))
show(pick(3, 5))
show(pick(5, 3))
show(pick(0, -1))
show(K * 2)
show(SPAN)
put(10)
