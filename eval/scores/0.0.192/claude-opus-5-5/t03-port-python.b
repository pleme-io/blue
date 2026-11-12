use("retsu", %i[all_but_last push])

def step(out, ch)
  run = retsu::last(out)
  if run != nil and run[0] == ch
    push(all_but_last(out), [ch, run[1] + 1])
  else
    push(out, [ch, 1])
  end
end

def run_length(s)
  reduce(step, [], chars(s))
end

test "run_length of the empty string is empty"
  assert run_length("") == []
end

test "run_length counts runs"
  assert run_length("aaab") == [["a", 3], ["b", 1]]
  assert run_length("abba") == [["a", 1], ["b", 2], ["a", 1]]
end
