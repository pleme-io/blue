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

test "nothing has no median"
  assert median([]).nil?
end

test "an odd length answers the middle value once sorted"
  assert median([9, 1, 5]) == 5
  assert median([4]) == 4
end

test "an even length answers the mean of the two middle values"
  assert median([4, 1, 3, 2]) == 2.5
  assert median([10, 2]) == 6
end
