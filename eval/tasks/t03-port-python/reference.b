def step(out, ch)
  if out != [] and last(out)[0] == ch
    append(butlast(out), [[ch, last(out)[1] + 1]])
  else
    append(out, [[ch, 1]])
  end
end

def run_length(s)
  reduce(step, [], chars(s))
end
