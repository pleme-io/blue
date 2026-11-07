record item(name: Str, price: Int, qty: Int)

def total(items)
  reduce((n, i) -> n + i.price * i.qty, 0, items)
end

def restock(i, n)
  item(**i, qty: i.qty + n)
end
