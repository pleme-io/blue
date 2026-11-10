use("kiban", [:put_byte])

def grow(n: Int) -> Int
  put_byte(43)
  grow(n * 1000)
end

grow(1)
