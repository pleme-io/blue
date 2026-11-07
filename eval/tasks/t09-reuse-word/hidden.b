test "eval t09: invoice_total answers what it answered before"
  assert invoice_total([]) == 0
  assert invoice_total([{price: 2, qty: 3}, {price: 5, qty: 1}]) == 11
end

test "eval t09: the copy is gone and the existing word is called"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert not contains?(src, "def total(")
  assert not contains?(src, "reduce(")
  assert contains?(src, "sum(")
end
