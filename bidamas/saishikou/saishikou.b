# saishikou (再試行) — retrying a step that can fail for a moment.
#
# retrying(policy, step) calls step, a zero-parameter function, and returns its
# value. When step raises, it is called again after a pause, until it has been
# called policy.times times; then the last error is raised unchanged. The
# policy is a record: times (how many calls in all), wait_ms (the pause before
# the second call, doubled before each later one) and, optionally, on (the
# error kinds worth retrying; any other kind is raised at once).

def retrying(policy, step)
  attempt(step, policy.times, get(policy, :wait_ms), get(policy, :on), 1)
end

def attempt(step, times, wait_ms, kinds, n)
  step()
rescue e
  if n >= times or not retryable?(e, kinds)
    raise(e)
  else
    pause(wait_ms, n)
    attempt(step, times, wait_ms, kinds, n + 1)
  end
end

def retryable?(e, kinds)
  kinds.nil? or member?(e.kind, kinds)
end

def pause(wait_ms, n)
  if wait_ms != nil and wait_ms > 0
    sleep_ms(wait_ms * expt(2, n - 1))
  end
end

def flaky(failures)
  calls = [0]
  fn()
    set!(calls, [first(calls) + 1])
    if first(calls) <= failures
      raise(:refused, "call #{first(calls)} refused")
    end
    first(calls)
  end
end

test "a step that succeeds is called once"
  assert retrying({times: 3, wait_ms: 0}, () -> 7) == 7
end

test "a step that fails twice succeeds on the third call"
  assert retrying({times: 3, wait_ms: 0}, flaky(2)) == 3
end

test "a step that fails every time raises its last error"
  e = begin
    retrying({times: 2, wait_ms: 0}, flaky(5))
  rescue :refused as e
    e
  end
  assert e.message == "call 2 refused"
end

test "a kind outside on is raised at once"
  e = begin
    retrying({times: 5, wait_ms: 0, on: [:timeout]}, flaky(5))
  rescue :refused as e
    e
  end
  assert e.message == "call 1 refused"
end
