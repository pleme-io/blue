from functools import reduce

xs = map(lambda x: x * 3, range(1000000))
evens = filter(lambda x: x % 2 == 0, xs)
print(reduce(lambda a, x: a + x, evens, 0))
