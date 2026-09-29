# Errors and refusals
#
# Decide what is wrong as DATA: a list of [kind, why] refusals, empty when the
# input is good. Tests read the kinds. Only at the boundary does the program
# raise, with throw(error(kind, why)); error(...) alone raises nothing. A
# caught error cannot be read (its kind and message are not reachable), which
# is why the refusals are data first. This is kueri's q_refusals / q_check.
use("retsu", [:first, :is_empty, :last])

def port_refusals(text)
  n = to_int(text)
  if n == nil
    [[:not_a_number, "#{text} is not a port number"]]
  elsif n < 1 || n > 65535
    [[:out_of_range, "#{n} is outside 1..65535"]]
  else
    []
  end
end

def refusal_kinds(refusals)
  map(fn(r) first(r) end, refusals)
end

# The boundary: return the port, or raise naming every refusal.
def port_of(text)
  refusals = port_refusals(text)
  if !is_empty(refusals)
    throw(
      error(
        first(first(refusals)),
        join(map(fn(r) last(r) end, refusals), "; ")
      )
    )
  end
  to_int(text)
end

test "a good port has no refusals"
  assert port_refusals("8080") == []
  assert port_of("8080") == 8080
end

test "each bad input is refused with its own kind"
  assert refusal_kinds(port_refusals("http")) == [:not_a_number]
  assert refusal_kinds(port_refusals("70000")) == [:out_of_range]
  assert refusal_kinds(port_refusals("0")) == [:out_of_range]
end

test "the boundary raises, and a caller can catch it"
  caught = try(port_of("http"), catch(e(), e))
  assert error?(caught)
  assert try(port_of("22"), catch(_e(), :failed)) == 22
end

test "error() alone is a value, not a raise"
  assert error?(error(:k, "built, not thrown"))
end
