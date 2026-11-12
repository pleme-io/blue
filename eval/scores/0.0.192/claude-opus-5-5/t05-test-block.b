use("junjo", [:sort])

def median(xs)
  s = sort(xs)
  n = count(s)
  h = floor(n / 2)
  if n == 0
    nil
  elsif n % 2 == 1
    s[h]
  else
    (s[h - 1] + s[h]) / 2
  end
end

test "median of the empty list is nil"
  assert median([]).nil?
end

test "median of one item is that item"
  assert median([7]) == 7
end

test "median of an odd length out of order"
  assert median([9, 1, 5]) == 5
  assert median([3, 8, 1, 10, 2]) == 3
end

test "median of an even length out of order"
  assert median([10, 1, 4, 2]) == 3
  assert median([8, 2]) == 5
  assert median([7, 1, 2, 4]) == 3
end
