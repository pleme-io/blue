use("kazu", [:sum])

def invoice_total(lines)
  sum(map((l) -> l[:price] * l[:qty], lines))
end

test "invoice_total of no lines is zero"
  assert invoice_total([]) == 0
end

test "invoice_total sums price times qty"
  assert invoice_total([{price: 2, qty: 3}, {price: 5, qty: 1}]) == 11
end
