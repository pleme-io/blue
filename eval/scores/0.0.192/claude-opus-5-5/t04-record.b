record item(name: Str, price: Int, qty: Int)

def total(items)
  reduce((acc, i) -> acc + i.price * i.qty, 0, items)
end

def restock(i, n)
  item(**i, qty: i.qty + n)
end

test "total of no items is zero"
  assert total([]) == 0
end

test "total sums price times qty"
  assert total([item("pen", 2, 5), item("ink", 3, 1)]) == 13
end

test "restock is a copy"
  pen = item("pen", 2, 5)
  more = restock(pen, 3)
  assert more.qty == 8
  assert pen.qty == 5
  assert item?(more)
  assert not item?({name: "pen", price: 2, qty: 5})
end
