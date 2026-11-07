use("kazu", [:sum])

def invoice_total(lines)
  sum(map((l) -> l[:price] * l[:qty], lines))
end
