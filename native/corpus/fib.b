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

def fib(n: Int) -> Int
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

digits(fib(30))
put(10)
