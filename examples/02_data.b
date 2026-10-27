# Parsing and transforming data
#
# Text becomes records, records become answers. A record is a map with label
# keys; to_int answers nil for a field that is not a number, so a bad row is
# found rather than read as zero. JSON objects parse into [key, value] pairs,
# not maps: read their fields with deeta.
use("deeta", [:get_int, :get_str])
use("kazu", [:sum])
use("moji", [:is_blank, :lines, :trim])
use("retsu", [:first, :rest, :size])

def order_of(line)
  fields = split(line, ",")
  {
    id: nth(0, fields),
    item: trim(nth(1, fields)),
    qty: to_int(trim(nth(2, fields)))
  }
end

# Every order in a CSV text with a header line; blank lines are skipped.
def orders_of(text)
  rows = filter((l) -> not is_blank(l), rest(lines(text)))
  map(order_of, rows)
end

def bad_orders(orders)
  filter((o) -> get(o, :qty).nil?, orders)
end

def total_qty(orders)
  sum(map((o) -> get(o, :qty), orders))
end

csv = unlines(["id,item,qty", "a1,apple,3", "a2,pear,x", "a3,apple,4"])

test "text becomes records"
  orders = orders_of(csv)
  assert size(orders) == 3
  assert first(orders) == {id: "a1", item: "apple", qty: 3}
end

test "a field that is not a number is found, not read as zero"
  bad = bad_orders(orders_of(csv))
  assert map((o) -> get(o, :id), bad) == ["a2"]
end

test "the good rows add up"
  good = filter((o) -> get(o, :qty) != nil, orders_of(csv))
  assert total_qty(good) == 7
end

test "JSON in and out"
  doc = json_parse("{\"item\": \"apple\", \"qty\": 3}")
  assert get_str(doc, "item", "") == "apple"
  assert get_int(doc, "qty", 0) == 3
  assert get_int(doc, "missing", 0) == 0
  assert json_stringify({item: "apple", qty: 3}) ==
    "{\"item\":\"apple\",\"qty\":3}"
end

test "no rows is an empty list, not nil"
  assert orders_of(unlines(["id,item,qty"])) == []
end
