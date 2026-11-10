use("kiban", %i[put_byte put_int])

N = 30

def fib(n: Int) -> Int
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

put_int(fib(N))
put_byte(10)
