use("kiban", %i[put_byte put_int])

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

put_int(is_even(10))
put_int(is_even(7))
put_int(is_odd(9999))
put_byte(10)
