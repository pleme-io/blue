use("kiban", %i[put_byte put_int])

SPAN = 7 * 6 - 2
HALF = floor(SPAN / 3)

def show(n: Int) -> Int
  put_int(n)
  put_byte(32)
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
put_byte(10)
