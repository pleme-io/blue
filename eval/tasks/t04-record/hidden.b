test "eval t04: an item is a record with its fields in order"
  pen = item("pen", 2, 5)
  assert item?(pen)
  assert not item?({name: "pen", price: 2, qty: 5})
  assert pen == item({qty: 5, price: 2, name: "pen"})
  assert pen.price == 2
end

test "eval t04: total sums price times quantity"
  assert total([]) == 0
  assert total([item("pen", 2, 5), item("cup", 3, 1)]) == 13
end

test "eval t04: restock is a copy"
  pen = item("pen", 2, 5)
  more = restock(pen, 4)
  assert item?(more)
  assert more.qty == 9
  assert pen.qty == 5
  assert more.name == "pen"
end
