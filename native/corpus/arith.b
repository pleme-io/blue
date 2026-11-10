use("kiban", %i[put_byte put_int])

SPAN = 7 * 6 - 2
HALF = floor(SPAN / 3)

def pick(a: Int, b: Int) -> Int
  if a != b and not (a > b) or a == 0
    a
  else
    b
  end
end

K = put_int(HALF)
put_byte(32)
put_int(-7 % 3)
put_byte(32)
put_int(7 % -3)
put_byte(32)
put_int(floor(-7 / 2))
put_byte(32)
put_int(floor(7 / -2))
put_byte(32)
put_int(floor(-8 / 2))
put_byte(32)
put_int(pick(3, 5))
put_byte(32)
put_int(pick(5, 3))
put_byte(32)
put_int(pick(0, -1))
put_byte(32)
put_int(K * 2)
put_byte(32)
put_int(SPAN)
put_byte(32)
put_byte(10)
