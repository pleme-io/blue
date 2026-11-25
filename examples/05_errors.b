# Errors and refusals
#
# Decide what is wrong as DATA: a list of [kind, why] refusals, empty when the
# input is good. Tests read the kinds, and a caller can act on every refusal at
# once. Only at the boundary does the program raise, with raise(kind, why); a
# caller that rescues it reads the error as a record (e.kind, e.message,
# e.data, e.cause), but sees only the first refusal. This is kueri's
# refusals / check.
use("retsu", %i[first is_empty last])

def port_refusals(text)
  n = to_int(text)
  if n.nil?
    [[:not_a_number, "#{text} is not a port number"]]
  elsif n < 1 or n > 65535
    [[:out_of_range, "#{n} is outside 1..65535"]]
  else
    []
  end
end

def refusal_kinds(refusals)
  map((r) -> first(r), refusals)
end

# The boundary: return the port, or raise naming every refusal.
def port_of(text)
  refusals = port_refusals(text)
  if not is_empty(refusals)
    raise(first(first(refusals)), join(map((r) -> last(r), refusals), "; "))
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
  caught = begin
    port_of("http")
  rescue e
    e
  end
  assert error?(caught)
  assert (port_of("22") rescue :failed) == 22
end

test "error() alone is a value, not a raise"
  assert error?(error(:k, "built, not thrown"))
end
