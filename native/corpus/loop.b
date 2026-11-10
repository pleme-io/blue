use("kiban", %i[put_byte put_int])

N = 3_000_000

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

put_int(walk(N, 0))
put_byte(10)
