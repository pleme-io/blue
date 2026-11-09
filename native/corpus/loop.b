use("kiban", [:mmio_write])

UART0 = 268_435_456

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

def walk(i: Int, acc: Int) -> Int
  if i == 0
    acc
  elsif i % 3 == 0
    walk(i - 1, acc + i * 2)
  elsif i % 5 == 1
    walk(i - 1, acc - i)
  else
    walk(i - 1, acc + 1)
  end
end

digits(walk(3_000_000, 0))
put(10)
