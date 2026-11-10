use("kiban", %i[put_byte put_int])

def fib(n: Int) -> Int
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

put_int(fib(30))
put_byte(10)
